-- Gatherwise world map: node pins, the route as a line, and options in the map's filter menu.

local ADDON, ns = ...

local NODE_PIN = "GatherwiseNodePinTemplate"
local ROUTE_PIN = "GatherwiseRoutePinTemplate"
local MAX_PINS = 1500 -- continent maps can hold thousands of spawn points; only zones get pins

---------------------------------------------------------------------------
-- Pins (templates in Templates.xml)
---------------------------------------------------------------------------
GatherwiseNodePinMixin = CreateFromMixins(MapCanvasPinMixin)

function GatherwiseNodePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_DIG_SITE")
    self:SetScalingLimits(1, 1.0, 1.25) -- same size on screen at every zoom level
end

function GatherwiseNodePinMixin:OnAcquired(node, x, y, isTarget)
    self.node = node
    local size = ns.db.mapIconSize * (isTarget and 1.6 or 1)
    self:SetSize(size, size)
    self.Icon:SetTexture(ns.Icon(node.def))
    self.Ring:SetShown(isTarget or false)
    self:SetPosition(x, y)
end

function GatherwiseNodePinMixin:OnMouseEnter()
    ns.ShowNodeTooltip(self, self.node)
end

function GatherwiseNodePinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

GatherwiseRoutePinMixin = CreateFromMixins(MapCanvasPinMixin)

function GatherwiseRoutePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self:SetIgnoreGlobalPinScale(true) -- scale with the map itself
    self.lines = {}
end

function GatherwiseRoutePinMixin:OnAcquired(points)
    local canvas = self:GetMap():GetCanvas()
    local w, h = canvas:GetSize()
    self:SetSize(w, h)
    self:SetPosition(0.5, 0.5)

    local count = #points
    for i = 1, count do
        local a, b = points[i], points[i % count + 1]
        local line = self.lines[i]
        if not line then
            line = self:CreateLine(nil, "ARTWORK")
            line:SetColorTexture(0.35, 0.95, 0.85, 0.75)
            self.lines[i] = line
        end
        line:SetThickness(math.max(2, w / 500))
        line:SetStartPoint("TOPLEFT", self, a[1] * w, -a[2] * h)
        line:SetEndPoint("TOPLEFT", self, b[1] * w, -b[2] * h)
        line:Show()
    end
    for i = count + 1, #self.lines do self.lines[i]:Hide() end
end

---------------------------------------------------------------------------
-- Tooltip shared with the minimap
---------------------------------------------------------------------------
function ns.ShowNodeTooltip(owner, node)
    local def = node.def
    local skill = ns.skill[def.kind]
    local _, color = ns.Difficulty(def, skill)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(def.name, color[1], color[2], color[3])
    GameTooltip:AddLine(("Requires %s %d"):format(ns.KIND_LABEL[def.kind], def.skill), 1, 1, 1)
    if skill then
        GameTooltip:AddLine(("Your %s: %d"):format(ns.KIND_LABEL[def.kind], skill), 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(("You don't have %s."):format(ns.KIND_LABEL[def.kind]), 1, 0.3, 0.3)
    end
    if node.learned then
        GameTooltip:AddLine("You gathered here.", 0.35, 0.95, 0.85)
    else
        GameTooltip:AddLine("Known spawn point" .. (node.confirmed and " (you gathered here)" or "")
            .. ": it isn't always up.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(NODE_PIN)
    self:GetMap():RemoveAllPinsByTemplate(ROUTE_PIN)
end

function provider:RefreshAllData()
    self:RemoveAllData()
    local db = ns.db
    if not db or not db.worldMap then return end

    local map = self:GetMap()
    local mapID = map:GetMapID()
    local bounds = ns.MapBounds(mapID)
    if not bounds then return end
    local info = C_Map.GetMapInfo(mapID)
    local isZone = info and Enum.UIMapType and info.mapType >= Enum.UIMapType.Zone

    local route = ns.route
    local target = ns.RouteTarget and ns.RouteTarget()

    if isZone then
        local shown = 0
        for _, node in ipairs(ns.nodes[bounds.continent] or {}) do
            if ns.IsVisible(node) then
                local x, y = ns.WorldToMap(bounds, node.x, node.y)
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    map:AcquirePin(NODE_PIN, node, x, y, target and target.nodes[node] or false)
                    shown = shown + 1
                    if shown >= MAX_PINS then break end
                end
            end
        end
    end

    if route and db.showRoute and route.continent == bounds.continent then
        local points = {}
        for _, stop in ipairs(route.stops) do
            local x, y = ns.WorldToMap(bounds, stop.x, stop.y)
            points[#points + 1] = { x, y }
        end
        if #points >= 2 then map:AcquirePin(ROUTE_PIN, points) end
    end
end

local function Refresh()
    if WorldMapFrame and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end
table.insert(ns.listeners, Refresh)
ns.RefreshWorldMap = Refresh

---------------------------------------------------------------------------
-- Map filter menu (the funnel button at the top right of the world map)
---------------------------------------------------------------------------
local function Toggle(key)
    return function()
        ns.db[key] = not ns.db[key]
        ns.Changed()
    end
end

local function Checked(key)
    return function() return ns.db[key] end
end

local function BuildMenu(root)
    root:CreateDivider()
    root:CreateTitle("Gatherwise")
    root:CreateCheckbox("Show on world map", Checked("worldMap"), Toggle("worldMap"))
    root:CreateCheckbox("Show on minimap", Checked("minimap"), Toggle("minimap"))
    root:CreateCheckbox("Mining nodes", Checked("showMine"), Toggle("showMine"))
    root:CreateCheckbox("Herbs", Checked("showHerb"), Toggle("showHerb"))
    root:CreateCheckbox("Only what I can gather", Checked("onlyGatherable"), Toggle("onlyGatherable"))
    root:CreateCheckbox("Hide grey (no skill-ups)", Checked("hideGrey"), Toggle("hideGrey"))
    root:CreateCheckbox("Show route", Checked("showRoute"), Toggle("showRoute"))
    root:CreateCheckbox("Faint rings while tracking", function() return ns.db.trackingStyle ~= "icons" end, function()
        ns.db.trackingStyle = (ns.db.trackingStyle == "icons") and "rings" or "icons"
        ns.Changed()
    end)
    root:CreateCheckbox("Detour to live nodes", Checked("liveDetours"), Toggle("liveDetours"))
    root:CreateButton(ns.route and "Stop routing" or "Start routing in this zone", function()
        ns.ToggleRoute()
    end)
end

local menuAdded = false
local function AddMenu()
    if menuAdded or not WorldMapFrame then return end
    menuAdded = true
    WorldMapFrame:AddDataProvider(provider)

    if Menu and Menu.ModifyMenu and WorldMapFrame.WorldMapTrackingOptionsButton then
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root) BuildMenu(root) end)
    elseif MenuUtil and MenuUtil.CreateContextMenu then
        -- No filter button on this map: add a small one of our own.
        local button = CreateFrame("Button", nil, WorldMapFrame:GetCanvasContainer())
        button:SetSize(28, 28)
        button:SetPoint("TOPRIGHT", -40, -2)
        button:SetFrameStrata("HIGH")
        button:SetNormalTexture("Interface\\Icons\\Trade_Mining")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, function(_, root) BuildMenu(root) end)
        end)
    end
end

table.insert(ns.loginHandlers, AddMenu)
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_WorldMap" and ns.db then AddMenu() end
end)
