-- Gatherwise live nodes: which spots actually have a vein or herb right now.
--
-- The game doesn't tell addons where the yellow Find Minerals / Find Herbs dots are. It does show
-- their names in the tooltip when you hover over them on the minimap. Gatherwise reads that tooltip,
-- works out the spot from where your cursor is, and marks the nearest spawn point as live. Hovering
-- the route's target ring when there is no dot marks it as empty.
--
-- Optionally, soft-targeting (a game setting) also reveals nodes right in front of you.

local ADDON, ns = ...

local LIVE_FOR = 8 * 60   -- seconds a spotted node stays "live" (someone else may take it)
local SNAP = 15           -- yards: a spotted dot this close to a known spawn point is that point
local HOVER_EMPTY = 0.6   -- seconds hovering an empty target ring before it counts as empty
local CURSOR_HIT = 10     -- pixels: how close the cursor must be to the target ring

local function Strip(text)
    return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

-- Cursor position on the minimap -> world yards. The inverse of the minimap projection.
local function CursorToWorld()
    local px, py, continent = ns.PlayerPosition()
    if not px then return nil end
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    local east, north = cx / scale - mx, cy / scale - my
    local pixelsPerYard = (Minimap:GetWidth() / 2) / ns.ViewRadius()
    east, north = east / pixelsPerYard, north / pixelsPerYard
    if GetCVar("rotateMinimap") == "1" then
        local f = GetPlayerFacing() or 0
        local c, s = math.cos(f), math.sin(f)
        east, north = east * c - north * s, east * s + north * c
    end
    return px + north, py - east, continent, math.sqrt(east * east + north * north) * pixelsPerYard
end
ns.CursorToWorld = CursorToWorld

-- A live node was seen near (x, y): find or save the spawn point and tell the route.
function ns.ReportLive(def, x, y, continent, source)
    local node = ns.Nearest(continent, x, y, def, SNAP)
    if not node then
        -- Not a known spot. A cursor position is only roughly right, so don't save it: the route
        -- can still go there, and gathering it saves the exact spot.
        node = { x = x, y = y, def = def, continent = continent, temporary = true }
    end
    local wasLive = node.liveUntil and node.liveUntil > GetTime()
    node.liveUntil = GetTime() + LIVE_FOR
    node.emptyUntil = nil
    if not wasLive and ns.OnLiveNode then ns.OnLiveNode(node, source) end
    return node
end

---------------------------------------------------------------------------
-- Minimap tooltip
---------------------------------------------------------------------------
local lastText, lastCheck = nil, 0
local emptyHoverStart

local function NamesFromLines(lines)
    local names = {}
    for _, text in ipairs(lines) do
        for part in text:gmatch("[^\n]+") do
            local name = Strip(part)
            if ns.TYPES[name] then names[#names + 1] = ns.TYPES[name] end
        end
    end
    return names
end

local function OnMinimapTooltip(lines)
    local now = GetTime()
    local names = NamesFromLines(lines)
    local x, y, continent = CursorToWorld()
    if not x then return end

    -- Live nodes under the cursor.
    -- Same names at (roughly) the same place: already handled. Another dot with the same name counts.
    local text = table.concat(lines, "|") .. "@" .. math.floor(x / 10) .. ":" .. math.floor(y / 10)
    if #names > 0 and text ~= lastText then
        for _, def in ipairs(names) do ns.ReportLive(def, x, y, continent, "minimap") end
    end
    lastText = text

    local pixelsPerYard = (Minimap:GetWidth() / 2) / ns.ViewRadius()

    -- Hovering a spot we thought was live, with no dot under it: it's gone.
    if #names == 0 then
        local reach = CURSOR_HIT / pixelsPerYard
        local cleared = {}
        ns.ForNodesNear(continent, x, y, reach, function(node)
            if node.liveUntil and node.liveUntil > now then cleared[#cleared + 1] = node end
        end)
        for _, node in ipairs(cleared) do ns.OnNodeEmpty(node) end
        local detour = ns.route and ns.route.detour
        if detour and math.sqrt((detour.x - x) ^ 2 + (detour.y - y) ^ 2) <= reach then
            for node in pairs(detour.nodes) do ns.OnNodeEmpty(node) end
        end
    end

    -- Hovering the target ring with no dot under it: nothing's there.
    local route = ns.route
    local target = ns.RouteTarget and ns.RouteTarget()
    if route and target and #names == 0 and route.continent == continent then
        local dx, dy = target.x - x, target.y - y
        if math.sqrt(dx * dx + dy * dy) * pixelsPerYard <= CURSOR_HIT then
            emptyHoverStart = emptyHoverStart or now
            if now - emptyHoverStart >= HOVER_EMPTY then
                emptyHoverStart = nil
                if ns.MarkTargetEmpty then ns.MarkTargetEmpty("no dot on the minimap") end
            end
            return
        end
    end
    emptyHoverStart = nil
end

-- What's under the cursor on the minimap right now (names of tracked dots), or {} for nothing.
local function ReadMouseover(tooltip)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover then
        local data = C_TooltipInfo.GetMinimapMouseover()
        for _, line in ipairs(data and data.lines or {}) do
            local text = ns.SafeString(line.leftText)
            if text then lines[#lines + 1] = text end
        end
    elseif tooltip:IsShown() then
        for i = 1, tooltip:NumLines() do
            local fs = _G["GameTooltipTextLeft" .. i]
            local text = fs and ns.SafeString(fs:GetText())
            if text then lines[#lines + 1] = text end
        end
    end
    return lines
end

local function HookTooltip()
    -- Blizzard calls this every frame while the mouse is over the minimap. Unlike the tooltip data
    -- hooks it also runs when there's nothing under the cursor, which is how we see empty spots.
    if GameTooltip.SetMinimapMouseover then
        hooksecurefunc(GameTooltip, "SetMinimapMouseover", function(tooltip)
            local now = GetTime()
            if now - lastCheck < 0.15 then return end
            lastCheck = now
            OnMinimapTooltip(ReadMouseover(tooltip))
        end)
    end
end

---------------------------------------------------------------------------
-- Close range: soft-targeting
---------------------------------------------------------------------------
-- With soft-targeting on, the game targets interactable objects right in front of you and fires
-- PLAYER_SOFT_INTERACT_CHANGED with the object's GUID, which tells us its type.
ns.softNode = nil

function ns.SoftTargetingOn()
    local value = tonumber(GetCVar("SoftTargetInteract") or "0") or 0
    return value >= 2 -- 2 = keyboard and mouse, 3 = always
end

function ns.SetCloseDetect(on)
    ns.db.closeDetect = on
    if on then
        if not ns.SoftTargetingOn() then
            ns.db.softTargetBefore = GetCVar("SoftTargetInteract")
            SetCVar("SoftTargetInteract", "3")
        end
        ns.Print("close-range detection on: nodes right in front of you are recognised"
            .. " (and you can gather them with your Interact key).")
    elseif ns.db.softTargetBefore then
        SetCVar("SoftTargetInteract", ns.db.softTargetBefore)
        ns.db.softTargetBefore = nil
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, _, newTarget)
    local def = ns.TypeFromGUID(newTarget)
    if not def then
        ns.softNode = nil
        return
    end
    local x, y, continent = ns.PlayerPosition()
    if x then ns.softNode = ns.ReportLive(def, x, y, continent, "close") end
end)

table.insert(ns.loginHandlers, function()
    HookTooltip()
    events:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
end)
