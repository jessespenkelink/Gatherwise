-- Gatherwise minimap: nearby nodes as icons, and the route as a see-through line.

local ADDON, ns = ...

local UPDATE_INTERVAL = 0.05
local overlay, routeLayer
local pins, lines = {}, {}
local elapsedSince = 0

-- Minimap view radius in yards (Blizzard API, with a fallback for older clients).
local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then return C_Minimap.GetViewRadius() end
    local zoom = Minimap:GetZoom()
    local outdoor = { [0] = 233.3, 200, 166.7, 133.3, 100, 66.7 }
    return outdoor[zoom] or 233.3
end

ns.ViewRadius = ViewRadius

local function IsSquare()
    return GetMinimapShape and GetMinimapShape() == "SQUARE"
end

-- Is Find Minerals / Find Herbs on? Then the game already shows the live nodes as yellow dots.
local TRACKING = { [2580] = "mine", [2383] = "herb", ["Find Minerals"] = "mine", ["Find Herbs"] = "herb" }
ns.tracking = { mine = false, herb = false }

function ns.UpdateTracking()
    ns.tracking.mine, ns.tracking.herb = false, false
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active then
            local kind = TRACKING[info.spellID or 0] or TRACKING[info.name or ""]
            if kind then ns.tracking[kind] = true end
        end
    end
end

-- World offset (yards) -> minimap offset (pixels), honouring "Rotate Minimap".
local function Project(dx, dy, scale, rotate, facing)
    local east, north = -dy, dx
    if rotate then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, -east * s + north * c
    end
    return east * scale, north * scale
end
ns.Project = Project

local function Inside(px, py, half)
    if IsSquare() then return math.abs(px) <= half and math.abs(py) <= half end
    return px * px + py * py <= half * half
end

-- Cut a segment to the minimap circle (radius r). Returns nil when nothing is visible.
local function ClipToCircle(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local sq = math.sqrt(disc)
    local t0, t1 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
    t0, t1 = math.max(0, t0), math.min(1, t1)
    if t0 >= t1 then return nil end
    return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end
ns.ClipToCircle = ClipToCircle

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function GetPin(i)
    local pin = pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, overlay)
        pin:SetFrameLevel(overlay:GetFrameLevel() + 2)
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetAllPoints()
        local mask = pin:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
        pin.icon:AddMaskTexture(mask)
        pin.ring = pin:CreateTexture(nil, "OVERLAY")
        pin.ring:SetTexture("Interface\\Cooldown\\ping4")
        pin.ring:SetBlendMode("ADD")
        pin.ring:SetVertexColor(0.35, 0.95, 0.85)
        pin.ring:SetPoint("TOPLEFT", -5, 5)
        pin.ring:SetPoint("BOTTOMRIGHT", 5, -5)
        -- Faint ring: how spawn points look while Find Minerals/Herbs shows the real nodes.
        pin.faint = pin:CreateTexture(nil, "ARTWORK")
        pin.faint:SetTexture("Interface\\Cooldown\\ping4")
        pin.faint:SetBlendMode("ADD")
        pin.faint:SetAllPoints()
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self) ns.ShowNodeTooltip(self, self.node) end)
        pin:SetScript("OnLeave", GameTooltip_Hide)
        pins[i] = pin
    end
    return pin
end

local function GetLine(i)
    local line = lines[i]
    if not line then
        line = routeLayer:CreateLine(nil, "ARTWORK")
        line:SetColorTexture(0.35, 0.95, 0.85, 0.55)
        line:SetThickness(2)
        lines[i] = line
    end
    return line
end

local function HideFrom(list, first)
    for i = first, #list do list[i]:Hide() end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local function Update()
    local db = ns.db
    local px, py, continent = ns.PlayerPosition()
    if not (db and db.minimap and px) then
        HideFrom(pins, 1)
        HideFrom(lines, 1)
        return
    end

    local radius = ViewRadius()
    local half = Minimap:GetWidth() / 2
    local scale = half / radius
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = GetPlayerFacing() or 0

    local route = ns.route
    local target = ns.RouteTarget and ns.RouteTarget()

    -- Nodes
    local count, size = 0, db.minimapIconSize
    local now = GetTime()
    ns.ForNodesNear(continent, px, py, radius * 1.45, function(node)
        if count >= 120 or not ns.IsVisible(node) then return end
        local isTarget = target and target.nodes[node] or false
        -- With tracking on, Blizzard's yellow dots are the truth; keep our spawn points out of the way.
        local subtle = ns.tracking[node.def.kind] and db.trackingStyle ~= "icons"
        if subtle and db.trackingStyle == "hide" and not isTarget then return end
        local sx, sy = Project(node.x - px, node.y - py, scale, rotate, facing)
        if Inside(sx, sy, half - 4) then
            count = count + 1
            local pin = GetPin(count)
            local live = node.liveUntil and node.liveUntil > now
            pin.node = node
            pin.icon:SetShown(not subtle)
            pin.faint:SetShown(subtle)
            -- Never yellow or gold: those colours belong to Blizzard's tracking dots.
            if subtle then
                local s = (isTarget or live) and size or size * 0.75
                pin:SetSize(s, s)
                if live then
                    pin.faint:SetVertexColor(0.35, 0.95, 0.85, 0.9) -- you spotted a node here: teal
                else
                    pin.faint:SetVertexColor(0.8, 0.8, 0.8, 0.35)  -- just a possible spot: faint grey
                end
            else
                local s = isTarget and size * 1.4 or size
                pin:SetSize(s, s)
                pin.icon:SetTexture(ns.Icon(node.def))
            end
            pin.ring:SetShown(isTarget or live)
            if isTarget then
                pin.ring:SetVertexColor(0.35, 0.95, 0.85)
            else
                pin.ring:SetVertexColor(1, 1, 1, 0.6) -- spotted live, not the target yet
            end
            -- Let the mouse through to Blizzard's tooltip, so hovering a yellow dot still works.
            pin:EnableMouse(not subtle)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", overlay, "CENTER", sx, sy)
            pin:Show()
        end
    end)
    HideFrom(pins, count + 1)

    -- Route
    local used = 0
    if route and db.showRoute and route.continent == continent then
        local stops, n = route.stops, #route.stops
        local edge = half - 2
        -- Draw from the current target onwards, plus the leg from you to it.
        local function Segment(ax, ay, bx, by)
            local x0, y0, x1, y1 = ax, ay, bx, by
            if IsSquare() then
                if not (Inside(ax, ay, edge) or Inside(bx, by, edge)) then return end
            else
                x0, y0, x1, y1 = ClipToCircle(ax, ay, bx, by, edge)
                if not x0 then return end
            end
            used = used + 1
            local line = GetLine(used)
            line:SetStartPoint("CENTER", routeLayer, x0, y0)
            line:SetEndPoint("CENTER", routeLayer, x1, y1)
            line:Show()
        end
        local tx, ty = Project(target.x - px, target.y - py, scale, rotate, facing)
        Segment(0, 0, tx, ty)
        if route.detour then
            -- After the detour, back to the loop.
            local back = stops[route.index]
            local bx, by = Project(back.x - px, back.y - py, scale, rotate, facing)
            Segment(tx, ty, bx, by)
        end
        for k = 0, math.min(n - 1, 40) - 1 do
            local a = stops[(route.index + k - 1) % n + 1]
            local b = stops[(route.index + k) % n + 1]
            local ax, ay = Project(a.x - px, a.y - py, scale, rotate, facing)
            local bx, by = Project(b.x - px, b.y - py, scale, rotate, facing)
            Segment(ax, ay, bx, by)
        end
    end
    HideFrom(lines, used + 1)
end
ns.UpdateMinimap = Update

table.insert(ns.loginHandlers, function()
    overlay = CreateFrame("Frame", nil, Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    routeLayer = CreateFrame("Frame", nil, overlay)
    routeLayer:SetAllPoints(overlay)
    routeLayer:SetFrameLevel(overlay:GetFrameLevel() + 1)

    ns.UpdateTracking()
    overlay:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    overlay:SetScript("OnEvent", function()
        ns.UpdateTracking()
        Update()
    end)

    overlay:SetScript("OnUpdate", function(_, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= UPDATE_INTERVAL then
            elapsedSince = 0
            Update()
        end
    end)
end)
table.insert(ns.listeners, function() if overlay then Update() end end)
