-- Gatherwise settings panel (Esc > Options > AddOns > Gatherwise, or /gw) and chat commands.

local ADDON, ns = ...

local OPTIONS = {
    { key = "showMine", label = "Mining nodes", desc = "Show veins and deposits." },
    { key = "showHerb", label = "Herbs", desc = "Show herbs." },
    { key = "onlyGatherable", label = "Only what I can gather", desc = "Hide nodes above your skill (and professions you don't have)." },
    { key = "hideGrey", label = "Hide grey nodes", desc = "Hide nodes that no longer give skill points." },
    { key = "showImported", label = "Known spawn points", desc = "Include the built-in spawn points, not just your own finds.", rebuild = true },
    { key = "worldMap", label = "Show on world map", desc = "Node icons on the world map (zone maps)." },
    { key = "minimap", label = "Show on minimap", desc = "Nearby node icons on the minimap." },
    { key = "showRoute", label = "Show route lines", desc = "Draw the route on the map and minimap while routing." },
    { key = "announce", label = "Chat message for new finds", desc = "Say so in chat when a new node is saved." },
    { key = "liveDetours", label = "Detour to live nodes", desc = "When you spot a node (hover its yellow dot on the minimap), the route goes there first if it's close." },
    { key = "ringsWhileTracking", label = "Faint rings while tracking", desc = "With Find Minerals/Herbs on, show spawn points as faint rings so the real yellow dots stand out.",
      get = function() return ns.db.trackingStyle ~= "icons" end,
      set = function(v) ns.db.trackingStyle = v and "rings" or "icons" end },
    { key = "hideWhileTracking", label = "Hide spawn points while tracking", desc = "With Find Minerals/Herbs on, show only the route's target on the minimap.",
      get = function() return ns.db.trackingStyle == "hide" end,
      set = function(v) ns.db.trackingStyle = v and "hide" or "rings" end },
    { key = "closeDetect", label = "Close-range detection", desc = "Turns on soft-targeting for objects, so a node right in front of you is recognised (and gatherable with your Interact key).",
      set = function(v) ns.SetCloseDetect(v) end },
}

local panel = CreateFrame("Frame")
local built, updating = false, false
local checks, sliders = {}, {}

local function Text(template)
    return panel:CreateFontString(nil, "ARTWORK", template)
end

local function GetOption(option)
    if option.get then return option.get() end
    return ns.db[option.key]
end

local function SetOption(option, value)
    if option.set then option.set(value) else ns.db[option.key] = value end
    if option.rebuild then ns.Rebuild() else ns.Changed() end
end

local function AddSlider(title, key, x, y, minValue, maxValue, steps, format, apply)
    local label = Text("GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(title)
    local slider = CreateFrame("Frame", nil, panel, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    slider:SetWidth(240)
    slider:Init(ns.db[key], minValue, maxValue, steps, { [MinimalSliderWithSteppersMixin.Label.Right] = format })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if updating then return end
        ns.db[key] = value
        if apply then apply(value) end
        ns.Changed()
    end, slider)
    slider.key = key
    sliders[#sliders + 1] = slider
end

local function Build()
    built = true
    local title = Text("GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Gatherwise")
    local sub = Text("GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Mining and herb nodes on your map, and routes to follow.")

    local y = -60
    for i, option in ipairs(OPTIONS) do
        local x = (i % 2 == 1) and 16 or 330
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        if cb.Text then cb.Text:SetText("") end
        local label = Text("GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        label:SetText(option.label)
        local desc = Text("GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        desc:SetWidth(250)
        desc:SetJustifyH("LEFT")
        desc:SetText(option.desc)
        cb:SetScript("OnClick", function(self) SetOption(option, self:GetChecked() and true or false) end)
        cb.option = option
        checks[#checks + 1] = cb
        if i % 2 == 0 then y = y - 46 end
    end
    if #OPTIONS % 2 == 1 then y = y - 46 end

    y = y - 10
    local round = function(v) return tostring(math.floor(v + 0.5)) end
    AddSlider("World map icon size", "mapIconSize", 16, y, 8, 28, 20, round)
    AddSlider("Minimap icon size", "minimapIconSize", 330, y, 8, 24, 16, round)
    AddSlider("Arrow size", "arrowScale", 16, y - 56, 0.5, 2, 15, function(v) return ("%.1f"):format(v) end,
        function(v) if GatherwiseArrow then GatherwiseArrow:SetScale(v) end end)

    local route = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    route:SetSize(180, 24)
    route:SetPoint("TOPLEFT", 330, y - 74)
    route:SetText("Start / stop routing")
    route:SetScript("OnClick", function() ns.ToggleRoute() end)

    local tip = Text("GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", 16, y - 130)
    tip:SetWidth(580)
    tip:SetJustifyH("LEFT")
    tip:SetText("Set your routing key in Esc > Options > Keybindings > AddOns > Gatherwise. "
        .. "Spawn points come from the CMaNGOS classic database; your own finds are added as you gather. "
        .. "Type /gw help for chat commands.")
end

function ns.RefreshOptions()
    if not built then return end
    updating = true
    for _, cb in ipairs(checks) do cb:SetChecked(GetOption(cb.option)) end
    for _, slider in ipairs(sliders) do slider:SetValue(ns.db[slider.key]) end
    updating = false
end
table.insert(ns.listeners, ns.RefreshOptions)

panel:SetScript("OnShow", function()
    if not built then Build() end
    ns.RefreshOptions()
end)

local category
table.insert(ns.loginHandlers, function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Gatherwise")
        Settings.RegisterAddOnCategory(category)
    end
end)

local function OpenOptions()
    if InCombatLockdown() then return ns.Print("the settings can't be opened during combat.") end
    if category then Settings.OpenToCategory(category:GetID()) end
end

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
SLASH_GATHERWISE1 = "/gatherwise"
SLASH_GATHERWISE2 = "/gw"
SlashCmdList.GATHERWISE = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        OpenOptions()
    elseif cmd == "route" then
        ns.ToggleRoute()
    elseif cmd == "skip" then
        ns.SkipStop()
    elseif cmd == "mine" or cmd == "herb" then
        local key = cmd == "mine" and "showMine" or "showHerb"
        ns.db[key] = not ns.db[key]
        ns.Print(ns.KIND_LABEL[cmd] .. " nodes: " .. (ns.db[key] and "|cff00ff00shown|r" or "|cffff2020hidden|r"))
        ns.Changed()
    elseif cmd == "stats" then
        local imported, learned = ns.CountNodes()
        ns.Print(("%d known spawn points, %d of your own finds. Mining %s, Herbalism %s."):format(
            imported, learned, ns.skill.mine or "not learned", ns.skill.herb or "not learned"))
    else
        ns.Print("/gw - settings")
        ns.Print("/gw route - start or stop routing in this zone (or press your key, default Alt+R)")
        ns.Print("/gw skip - skip the current node")
        ns.Print("/gw mine, /gw herb - show or hide mining nodes or herbs")
        ns.Print("/gw stats - how many nodes are known")
    end
end
