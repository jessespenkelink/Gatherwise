-- Gatherwise core: node storage, skill filters, coordinates, and recording what you gather.
--
-- All nodes are kept in world coordinates (yards) per continent, the same system the game uses
-- internally: x grows to the north, y grows to the west. That makes minimap distances trivial and
-- lets the bundled spawn data (from the CMaNGOS classic database) and your own finds share one store.

local ADDON, ns = ...

local GRID = 250   -- yards per grid cell for quick "what's near me" lookups
local MERGE = 12   -- yards; a find this close to a known node of the same type is the same node
local GATHER_REACH = 25 -- yards around you that count as "the node you just gathered"

local defaults = {
    showMine = true, showHerb = true,   -- which kinds to show
    onlyGatherable = true,              -- hide nodes above your skill
    hideGrey = false,                   -- hide nodes that no longer give skill points
    showImported = true,                -- include the bundled spawn points
    worldMap = true, minimap = true,
    mapIconSize = 14, minimapIconSize = 12,
    showRoute = true, arrowScale = 1,
    announce = true,                    -- chat line when a new node is saved
    trackingStyle = "rings",            -- while Find Minerals/Herbs is on: "rings", "hide" or "icons"
    liveDetours = true,                 -- send the route to live nodes you spot
    closeDetect = false,                -- soft-targeting to detect nodes right in front of you
}

local db
ns.nodes = {}  -- continent -> list of nodes { x, y, def, learned }
ns.grid = {}   -- continent -> "cx:cy" -> list of nodes

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff5ad1a0Gatherwise|r: " .. msg)
end

ns.listeners = {}  -- called with no args whenever what should be shown changes
function ns.Changed()
    for _, fn in ipairs(ns.listeners) do fn() end
end

---------------------------------------------------------------------------
-- Node store
---------------------------------------------------------------------------
local function CellKey(x, y)
    return math.floor(x / GRID) .. ":" .. math.floor(y / GRID)
end

local function AddNode(continent, x, y, def, learned)
    local node = { x = x, y = y, def = def, learned = learned, continent = continent }
    local list = ns.nodes[continent]
    if not list then
        list = {}
        ns.nodes[continent] = list
        ns.grid[continent] = {}
    end
    list[#list + 1] = node
    local key = CellKey(x, y)
    local cell = ns.grid[continent][key]
    if not cell then
        cell = {}
        ns.grid[continent][key] = cell
    end
    cell[#cell + 1] = node
    return node
end

-- Calls fn(node) for every node within `radius` yards of (x, y).
function ns.ForNodesNear(continent, x, y, radius, fn)
    local grid = ns.grid[continent]
    if not grid then return end
    local r2 = radius * radius
    local x0, x1 = math.floor((x - radius) / GRID), math.floor((x + radius) / GRID)
    local y0, y1 = math.floor((y - radius) / GRID), math.floor((y + radius) / GRID)
    for cx = x0, x1 do
        for cy = y0, y1 do
            local cell = grid[cx .. ":" .. cy]
            if cell then
                for _, node in ipairs(cell) do
                    local dx, dy = node.x - x, node.y - y
                    if dx * dx + dy * dy <= r2 then fn(node) end
                end
            end
        end
    end
end

local function FindNear(continent, x, y, def)
    local found
    ns.ForNodesNear(continent, x, y, MERGE, function(node)
        if node.def == def then found = node end
    end)
    return found
end

-- "x y z x y z ..." -> fn(x, y, z)
local function ParseTriples(text, fn)
    local buffer, n = {}, 0
    for number in text:gmatch("%-?%d+%.?%d*") do
        n = n + 1
        buffer[n] = tonumber(number)
        if n == 3 then
            fn(buffer[1], buffer[2], buffer[3])
            n = 0
        end
    end
end

function ns.Rebuild()
    wipe(ns.nodes)
    wipe(ns.grid)
    if db.showImported and ns.SPAWNS then
        for continent, types in pairs(ns.SPAWNS) do
            for name, text in pairs(types) do
                local def = ns.TYPES[name]
                if def then
                    ParseTriples(text, function(x, y, z)
                        AddNode(continent, x, y, def, false).z = z
                    end)
                end
            end
        end
    end
    -- Your own finds; skip the ones that are already a known spawn point.
    for continent, types in pairs(db.learned) do
        for name, flat in pairs(types) do
            local def = ns.TYPES[name]
            if def then
                for i = 1, #flat, 2 do
                    local x, y = flat[i], flat[i + 1]
                    local known = FindNear(continent, x, y, def)
                    if known then known.confirmed = true else AddNode(continent, x, y, def, true) end
                end
            end
        end
    end
    ns.Changed()
end

function ns.CountNodes()
    local imported, learned = 0, 0
    for _, list in pairs(ns.nodes) do
        for _, node in ipairs(list) do
            if node.learned then learned = learned + 1 else imported = imported + 1 end
        end
    end
    return imported, learned
end

---------------------------------------------------------------------------
-- Skills and filters
---------------------------------------------------------------------------
ns.skill = { mine = nil, herb = nil } -- nil = you don't have the profession

function ns.UpdateSkills()
    local old = (ns.skill.mine or "") .. ":" .. (ns.skill.herb or "")
    ns.skill.mine, ns.skill.herb = nil, nil
    if GetProfessions then
        for _, index in ipairs({ GetProfessions() }) do
            if index then
                local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
                if skillLine == ns.SKILL_LINE.mine then ns.skill.mine = rank end
                if skillLine == ns.SKILL_LINE.herb then ns.skill.herb = rank end
            end
        end
    end
    if old ~= (ns.skill.mine or "") .. ":" .. (ns.skill.herb or "") then ns.Changed() end
end

function ns.IsVisible(node)
    local def = node.def
    if def.kind == "mine" and not db.showMine then return false end
    if def.kind == "herb" and not db.showHerb then return false end
    local skill = ns.skill[def.kind]
    if db.onlyGatherable and (not skill or skill < def.skill) then return false end
    if db.hideGrey and skill and skill >= def.skill + 100 then return false end
    return true
end

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
local boundsCache = {}

-- World bounds of a map: continent, top (max x), left (max y), bottom, right.
function ns.MapBounds(mapID)
    if not mapID then return nil end
    local cached = boundsCache[mapID]
    if cached == nil then
        cached = false
        local continent, topLeft = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, bottomRight = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if continent and topLeft and bottomRight then
            local top, left = topLeft.x, topLeft.y
            local bottom, right = bottomRight.x, bottomRight.y
            if top ~= bottom and left ~= right then
                cached = { continent = continent, top = top, left = left, bottom = bottom, right = right }
            end
        end
        boundsCache[mapID] = cached
    end
    return cached or nil
end

function ns.WorldToMap(b, x, y)
    return (b.left - y) / (b.left - b.right), (b.top - x) / (b.top - b.bottom)
end

-- Player position in world yards: x (north), y (west), continent.
-- Height is returned too when the game provides it (some clients always report 0: then nil).
function ns.PlayerPosition()
    local x, y, z, continent = UnitPosition("player")
    if x then return x, y, continent, (z ~= 0) and z or nil end
end

---------------------------------------------------------------------------
-- Recording what you gather
---------------------------------------------------------------------------
-- Nearest node of this type within `radius` yards, or nil.
function ns.Nearest(continent, x, y, def, radius)
    local best, bestDist
    ns.ForNodesNear(continent, x, y, radius, function(node)
        if node.def == def then
            local d = (node.x - x) ^ 2 + (node.y - y) ^ 2
            if not bestDist or d < bestDist then best, bestDist = node, d end
        end
    end)
    return best
end

-- Save a node seen at (x, y) that isn't known yet; returns the (new or existing) node.
function ns.SaveNode(continent, x, y, def, quiet)
    local node = FindNear(continent, x, y, def)
    if node then return node, false end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    db.learned[continent] = db.learned[continent] or {}
    local flat = db.learned[continent][def.name] or {}
    db.learned[continent][def.name] = flat
    flat[#flat + 1] = x
    flat[#flat + 1] = y
    node = AddNode(continent, x, y, def, true)
    if db.announce and not quiet then ns.Print("saved a new " .. def.name .. ".") end
    ns.Changed()
    return node, true
end

local function Record(def)
    if not def then return end
    local x, y, continent = ns.PlayerPosition()
    if not x then return end
    local node = FindNear(continent, x, y, def)
    if node then
        node.confirmed = true
    else
        node = ns.SaveNode(continent, x, y, def)
    end
    -- You just emptied it. You can gather from a few yards away and the database spot can be a bit
    -- off, so clear every node of this type around you, not just the one we matched.
    local emptied = { node }
    node.liveUntil = nil
    ns.ForNodesNear(continent, x, y, GATHER_REACH, function(n)
        if n.def == def and n ~= node then
            n.liveUntil = nil
            emptied[#emptied + 1] = n
        end
    end)
    if ns.OnGathered then ns.OnGathered(node, emptied) end
end

local pending = {} -- castGUID -> node type, while a Mining / Herb Gathering cast is running
local lastRecord = 0

local function SafeName(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "string" then return nil end
    return value
end
ns.SafeString = SafeName

-- Node type from a game object GUID ("GameObject-0-...-objectID-spawnUID").
function ns.TypeFromGUID(guid)
    guid = SafeName(guid)
    if not guid or not guid:match("^GameObject") then return nil end
    local objectID = tonumber(select(6, strsplit("-", guid)))
    return objectID and ns.TYPE_BY_OBJECT[objectID]
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        GatherwiseDB = GatherwiseDB or {}
        db = GatherwiseDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        db.learned = db.learned or {}
        ns.db = db
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.UpdateSkills()
        ns.Rebuild()
        for _, fn in ipairs(ns.loginHandlers) do fn() end
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        ns.UpdateSkills()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, castGUID = ...
        local name = SafeName(target)
        if unit == "player" and name and ns.TYPES[name] then pending[castGUID] = ns.TYPES[name] end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID = ...
        if unit == "player" and pending[castGUID] then
            Record(pending[castGUID])
            lastRecord = GetTime()
            wipe(pending)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, castGUID = ...
        if unit == "player" then pending[castGUID] = nil end
    elseif event == "LOOT_OPENED" then
        -- Backup: recognise the node from the loot window's source (its object ID).
        if GetTime() - lastRecord < 3 or not GetLootSourceInfo then return end
        local def = ns.TypeFromGUID(GetLootSourceInfo(1))
        if def then
            Record(def)
            lastRecord = GetTime()
        end
    end
end)
ns.loginHandlers = {}
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "LOOT_OPENED" }) do
    events:RegisterEvent(event)
end
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED" }) do
    events:RegisterUnitEvent(event, "player")
end
