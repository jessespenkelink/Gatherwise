-- Gatherwise routes: the shortest loop past every node you can gather in your zone, and an
-- arrow that guides you from node to node.
--
-- Press your key (default Alt+R if it's free; change it in Key Bindings > AddOns) or use
-- the world map's filter menu to start and stop.

local ADDON, ns = ...

local CLUSTER = 25     -- yards: nodes this close together become one stop
local REACHED = 15     -- yards: closer than this counts as "arrived"
local MAX_STOPS = 400
local RESPAWN = 10 * 60 -- seconds a visited or empty spot is skipped on later laps
local DETOUR = 150      -- yards of extra walking that's worth it for a live node
local BUDGET = 0.012   -- seconds of route calculation per frame, so the game never stutters
local CLIMB = 2.5      -- each yard of height difference counts as this many yards of walking
local SAME_LEVEL = 12  -- yards of height within which nearby nodes count as one stop
local RETARGET = 0.5   -- go to another stop first when it's less than half as far as the target
local RETARGET_MIN = 100 -- ...but only when the target is further away than this (yards)

ns.route = nil

local function Dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Walking effort between two spots: distance, plus extra for climbing up or down.
-- Spots on a ridge above you are much further away than the map suggests.
local function Cost(a, b)
    local d = Dist(a, b)
    if a.z and b.z then d = d + CLIMB * math.abs(a.z - b.z) end
    return d
end
ns.RouteCost = Cost

---------------------------------------------------------------------------
-- Route calculation
---------------------------------------------------------------------------
-- Group nearby nodes (veins of different ores often share a spot) into stops.
local function BuildStops(nodes)
    local stops = {}
    for _, node in ipairs(nodes) do
        local joined
        for _, stop in ipairs(stops) do
            local level = not (stop.z and node.z) or math.abs(stop.z - node.z) <= SAME_LEVEL
            if level and Dist(stop, node) <= CLUSTER then joined = stop break end
        end
        if joined then
            joined.nodes[node] = true
            joined.count = joined.count + 1
            joined.x = joined.x + (node.x - joined.x) / joined.count
            joined.y = joined.y + (node.y - joined.y) / joined.count
            if joined.z and node.z then joined.z = joined.z + (node.z - joined.z) / joined.count end
        else
            stops[#stops + 1] = { x = node.x, y = node.y, z = node.z, nodes = { [node] = true }, count = 1, first = node }
        end
    end
    return stops
end

local function TourLength(tour)
    local total, n = 0, #tour
    for i = 1, n do total = total + Dist(tour[i], tour[i % n + 1]) end
    return total
end

-- Nearest neighbour tour from the stop closest to `start`, then 2-opt until no swap helps.
-- Runs as a coroutine; yields whenever the frame budget is used up.
local function Solve(stops, start, Yield)
    local n = #stops
    local first, best = 1, math.huge
    for i, stop in ipairs(stops) do
        local d = Dist(stop, start)
        if d < best then first, best = i, d end
    end

    local used, tour = { [first] = true }, { stops[first] }
    for _ = 2, n do
        local last, pick, pickDist = tour[#tour], nil, math.huge
        for i, stop in ipairs(stops) do
            if not used[i] then
                local d = Cost(last, stop)
                if d < pickDist then pick, pickDist = i, d end
            end
        end
        used[pick] = true
        tour[#tour + 1] = stops[pick]
        Yield()
    end

    local improved = true
    while improved and n >= 4 do
        improved = false
        for i = 1, n - 2 do
            local a, b = tour[i], tour[i + 1]
            for j = i + 2, (i == 1) and (n - 1) or n do
                local c, d = tour[j], tour[j % n + 1]
                local delta = Cost(a, c) + Cost(b, d) - Cost(a, b) - Cost(c, d)
                if delta < -0.01 then
                    -- reverse tour[i+1 .. j]
                    local lo, hi = i + 1, j
                    while lo < hi do
                        tour[lo], tour[hi] = tour[hi], tour[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    b = tour[i + 1]
                    improved = true
                end
            end
            Yield()
        end
    end
    return tour
end
ns.SolveRoute = Solve

---------------------------------------------------------------------------
-- Guide arrow
---------------------------------------------------------------------------
local arrow

local function CreateArrow()
    arrow = CreateFrame("Frame", "GatherwiseArrow", UIParent)
    arrow:SetSize(64, 80)
    arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
    arrow:SetMovable(true)
    arrow:EnableMouse(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetClampedToScreen(true)
    arrow:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.arrowPos = { point, relPoint, x, y }
    end)
    arrow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Gatherwise route")
        GameTooltip:AddLine("Follow the arrow to the next node.", 1, 1, 1)
        GameTooltip:AddLine("Right-click: skip this node", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Shift-drag: move the arrow", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    arrow:SetScript("OnLeave", GameTooltip_Hide)
    arrow:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns.SkipStop() end end)

    arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
    arrow.icon:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    arrow.icon:SetSize(48, 48)
    arrow.icon:SetPoint("TOP")

    arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow.text:SetPoint("TOP", arrow.icon, "BOTTOM", 0, -2)

    arrow.node = arrow:CreateTexture(nil, "ARTWORK")
    arrow.node:SetSize(16, 16)
    arrow.node:SetPoint("RIGHT", arrow.text, "LEFT", -4, 0)
    arrow.sub = arrow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    arrow.sub:SetPoint("TOP", arrow.text, "BOTTOM", 0, -2)

    local pos = ns.db.arrowPos
    if pos then
        arrow:ClearAllPoints()
        arrow:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    arrow:Hide()
end

local function StopLabel(stop)
    local names = {}
    for node in pairs(stop.nodes) do names[node.def.name] = true end
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    table.sort(list)
    return table.concat(list, " / ")
end

-- Where the arrow points: a detour to a live node, or the next stop on the loop.
function ns.RouteTarget()
    local route = ns.route
    if not route then return nil end
    return route.detour or route.stops[route.index]
end

local function IsLive(stop)
    local now = GetTime()
    for node in pairs(stop.nodes) do
        if node.liveUntil and node.liveUntil > now then return true end
    end
    return false
end

-- Next stop on the loop that isn't known to be empty (or recently visited).
local function NextIndex(route, from)
    local n, now = #route.stops, GetTime()
    local i = from
    for _ = 1, n do
        i = i % n + 1
        local stop = route.stops[i]
        if IsLive(stop) or not (stop.emptyUntil and stop.emptyUntil > now) then return i end
    end
    return from % n + 1 -- everything is on cooldown: just keep walking the loop
end
ns.NextIndex = NextIndex

-- Done with the current target (gathered, empty or skipped): it won't have a node for a while.
local function FinishTarget()
    local route = ns.route
    local stop = ns.RouteTarget()
    if stop then
        stop.emptyUntil = GetTime() + RESPAWN
        for node in pairs(stop.nodes) do node.liveUntil = nil end
    end
    if route.detour then
        route.detour = nil
    else
        route.index = NextIndex(route, route.index)
    end
    route.done = route.done + 1
    route.arrivedAt = nil
    ns.Changed()
end
ns.FinishTarget = FinishTarget

function ns.MarkTargetEmpty(reason)
    if not ns.route then return end
    FinishTarget()
end

-- The loop's next stop isn't always the sensible next step: you may have wandered off, or the
-- loop may come back to the spots around you only later. When another available stop is much
-- closer than the target, go there and continue the loop from that point.
local function Retarget(route, px, py, pz)
    if route.detour then return end
    local now = GetTime()
    if route.nextRetarget and now < route.nextRetarget then return end
    route.nextRetarget = now + 1

    local me = { x = px, y = py, z = pz }
    local target = route.stops[route.index]
    local toTarget = Cost(me, target)
    if Dist(me, target) < RETARGET_MIN then return end

    local bestIndex, bestCost
    for i, stop in ipairs(route.stops) do
        if i ~= route.index and (IsLive(stop) or not (stop.emptyUntil and stop.emptyUntil > now)) then
            local c = Cost(me, stop) * (IsLive(stop) and 0.5 or 1) -- known live nodes count double
            if not bestCost or c < bestCost then bestIndex, bestCost = i, c end
        end
    end
    if bestIndex and bestCost < RETARGET * toTarget then
        route.index = bestIndex
        ns.Changed()
    end
end
ns.Retarget = Retarget

local function UpdateArrow()
    local route = ns.route
    if not route then return end
    local px, py, continent, pz = ns.PlayerPosition()
    if px and continent == route.continent then Retarget(route, px, py, pz) end
    local stop = ns.RouteTarget()
    if not px or continent ~= route.continent then
        arrow.text:SetText("Route is on another continent")
        arrow.sub:SetText("")
        return
    end

    local dx, dy = stop.x - px, stop.y - py
    local dist = math.sqrt(dx * dx + dy * dy)
    local live = IsLive(stop)
    if dist <= REACHED then
        -- With close-range detection we can tell whether the node is really here: wait for you
        -- to gather it, or move on after a moment when there's nothing.
        if ns.db.closeDetect and ns.SoftTargetingOn() then
            route.arrivedAt = route.arrivedAt or GetTime()
            local soft = ns.softNode
            local here = soft and (stop.nodes[soft] or Dist(stop, soft) <= CLUSTER) and soft.liveUntil
            if not here and GetTime() - route.arrivedAt > 1.2 then
                FinishTarget()
                return
            end
            if here then
                arrow.text:SetText(StopLabel(stop) .. "  |cff40ff40is here, gather it!|r")
                return
            end
        else
            FinishTarget()
            return
        end
    else
        route.arrivedAt = nil
    end

    -- Direction to the node relative to where you're facing (counter-clockwise radians).
    local angle = math.atan2(dy, dx) - (GetPlayerFacing() or 0)
    arrow.icon:SetRotation(angle)
    local t = math.min(1, dist / 300)
    arrow.icon:SetVertexColor(0.35 + 0.65 * t, 1, 0.85 - 0.5 * t) -- greener when close

    arrow.node:SetTexture(ns.Icon(stop.first.def))
    local tag = live and "  |cff40ff40live|r" or ""
    arrow.text:SetText(("%s  |cffffffff%d yd|r%s"):format(StopLabel(stop), math.floor(dist), tag))
    local tracked = ns.tracking and ns.tracking[stop.first.def.kind]
    if tracked and not live and ns.ViewRadius and dist <= ns.ViewRadius() then
        -- The spot is on your minimap, where Find Minerals/Herbs shows whether anything is there.
        local key = GetBindingKey("GATHERWISE_SKIP_STOP")
        local keyText = key and (GetBindingText and GetBindingText(key) or key) or "right-click here"
        arrow.sub:SetText(("No yellow dot at the ring? Hover it, or press %s"):format(keyText))
    elseif tracked and not route.detour then
        -- Gatherwise can't see the yellow dots by itself; a hover tells it where they are.
        arrow.sub:SetText("See a yellow dot on your minimap? Hover it and the route goes there first")
    elseif route.detour then
        arrow.sub:SetText("detour to a live node, then back to the loop")
    else
        arrow.sub:SetText(("stop %d of %d"):format(route.index, #route.stops))
    end
end

---------------------------------------------------------------------------
-- Start / stop
---------------------------------------------------------------------------
local computing

function ns.StartRoute()
    if computing then return end
    local px, py, continent = ns.PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    local bounds = ns.MapBounds(mapID)
    if not (px and bounds) then
        ns.Print("can't make a route here (no map position, e.g. inside a dungeon).")
        return
    end

    local nodes = {}
    for _, node in ipairs(ns.nodes[continent] or {}) do
        if ns.IsVisible(node) then
            local x, y = ns.WorldToMap(bounds, node.x, node.y)
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then nodes[#nodes + 1] = node end
        end
    end
    local stops = BuildStops(nodes)
    if #stops < 2 then
        ns.Print("no nodes you can gather in this zone with the current filters. Check the map's filter menu.")
        return
    end
    if #stops > MAX_STOPS then
        -- Keep the stops closest to you so the calculation stays quick.
        local me = { x = px, y = py }
        table.sort(stops, function(a, b) return Dist(a, me) < Dist(b, me) end)
        for i = #stops, MAX_STOPS + 1, -1 do stops[i] = nil end
    end

    computing = coroutine.create(function()
        local deadline = debugprofilestop() + BUDGET * 1000
        local function Yield()
            if debugprofilestop() > deadline then
                coroutine.yield()
                deadline = debugprofilestop() + BUDGET * 1000
            end
        end
        return Solve(stops, { x = px, y = py }, Yield)
    end)

    ns.Print(("planning a route past %d stops..."):format(#stops))
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local ok, tour = coroutine.resume(computing)
        if not ok then
            ticker:Cancel()
            computing = nil
            ns.Print("route calculation failed: " .. tostring(tour))
        elseif coroutine.status(computing) == "dead" then
            ticker:Cancel()
            computing = nil
            ns.route = { continent = continent, mapID = mapID, stops = tour, index = 1, done = 0 }
            local yards = TourLength(tour)
            ns.Print(("route ready: %d stops, %.1f km loop. Follow the arrow!"):format(#tour, yards * 0.9144 / 1000))
            arrow:Show()
            ns.Changed()
        end
    end)
end

function ns.StopRoute()
    ns.route = nil
    if arrow then arrow:Hide() end
    ns.Changed()
end

function ns.ToggleRoute()
    if ns.route or computing then ns.StopRoute() else ns.StartRoute() end
end

function ns.SkipStop()
    if ns.route then FinishTarget() end
end

local function StopFor(route, node)
    for i, stop in ipairs(route.stops) do
        if stop.nodes[node] or Dist(stop, node) <= CLUSTER then return stop, i end
    end
end

-- Gathering at the target moves you on; gathering at another stop on the loop takes it off for a while.
-- A stop that has nothing to gather for now: skip it on later laps and forget it was live.
local function EmptyStop(stop)
    stop.emptyUntil = GetTime() + RESPAWN
    for n in pairs(stop.nodes) do n.liveUntil = nil end
end

function ns.OnGathered(node, emptied)
    local route = ns.route
    if not route then return end
    local target = ns.RouteTarget()
    local hitTarget = target and (target.nodes[node] or Dist(target, node) <= CLUSTER + REACHED)
    for _, n in ipairs(emptied or { node }) do
        local stop = StopFor(route, n)
        if stop then
            EmptyStop(stop)
            if stop == target then hitTarget = true end
        end
        if route.detour and (route.detour.nodes[n] or Dist(route.detour, n) <= CLUSTER) then
            EmptyStop(route.detour)
            if route.detour == target then hitTarget = true end
        end
    end
    if hitTarget then FinishTarget() else ns.Changed() end
end

-- A node turned out not to be there (hovered its spot, no yellow dot).
function ns.OnNodeEmpty(node)
    local route = ns.route
    node.liveUntil = nil
    if not route then return end
    local stop = StopFor(route, node)
    if stop then EmptyStop(stop) end
    if route.detour and (route.detour.nodes[node] or Dist(route.detour, node) <= CLUSTER) then
        route.detour = nil
    end
    ns.Changed()
end

-- A live node was spotted (minimap hover or close range). Put it on the route, and go there first
-- when that costs little extra walking.
function ns.OnLiveNode(node, source)
    local route = ns.route
    if not route or not ns.db.liveDetours or node.continent ~= route.continent or not ns.IsVisible(node) then
        return
    end
    local px, py = ns.PlayerPosition()
    if not px then return end
    local me = { x = px, y = py }

    local stop = StopFor(route, node)
    if not stop then
        -- A spot the route didn't have: insert it where it adds the least walking.
        stop = { x = node.x, y = node.y, nodes = { [node] = true }, count = 1, first = node }
        local n, bestAt, bestCost = #route.stops, 1, math.huge
        for i = 1, n do
            local a, b = route.stops[i], route.stops[i % n + 1]
            local cost = Dist(a, stop) + Dist(stop, b) - Dist(a, b)
            if cost < bestCost then bestAt, bestCost = i + 1, cost end
        end
        table.insert(route.stops, bestAt, stop)
        if bestAt <= route.index then route.index = route.index + 1 end
    end
    stop.emptyUntil = nil

    local target = ns.RouteTarget()
    if stop == target then return ns.Changed() end
    local direct = Dist(me, target)
    local extra = Dist(me, stop) + Dist(stop, target) - direct
    if extra <= DETOUR or Dist(me, stop) < direct then
        local current = route.detour
        if not current or Dist(me, stop) < Dist(me, current) then
            route.detour = stop
            if ns.db.announce then
                ns.Print(("live %s spotted: going there first (+%d yd)."):format(node.def.name, math.floor(math.max(0, extra))))
            end
        end
    end
    ns.Changed()
end

-- Key bindings (Bindings.xml)
BINDING_HEADER_GATHERWISE = "Gatherwise"
BINDING_NAME_GATHERWISE_TOGGLE_ROUTE = "Start / stop routing"
BINDING_NAME_GATHERWISE_SKIP_STOP = "Skip current node"
function Gatherwise_ToggleRoute() ns.ToggleRoute() end
function Gatherwise_SkipStop() ns.SkipStop() end

table.insert(ns.loginHandlers, function()
    CreateArrow()
    arrow:SetScale(ns.db.arrowScale)
    arrow:SetScript("OnUpdate", UpdateArrow)

    -- Default keys, set once and only if nothing else uses them: Alt+R routes, Alt+S skips a spot.
    local defaults = {
        { flag = "boundDefault", action = "GATHERWISE_TOGGLE_ROUTE", key = "ALT-R", text = "Alt+R starts or stops routing" },
        { flag = "boundSkip", action = "GATHERWISE_SKIP_STOP", key = "ALT-S", text = "Alt+S skips a spot with no node" },
    }
    if not InCombatLockdown() then
        local changed = false
        for _, d in ipairs(defaults) do
            if not ns.db[d.flag] then
                ns.db[d.flag] = true
                if not GetBindingKey(d.action) and (GetBindingAction(d.key) or "") == "" then
                    SetBinding(d.key, d.action)
                    changed = true
                    ns.Print(d.text .. " (change it in Key Bindings > AddOns).")
                end
            end
        end
        if changed then SaveBindings(GetCurrentBindingSet()) end
    end
end)
