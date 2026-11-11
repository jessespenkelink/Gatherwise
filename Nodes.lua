-- Gatherwise node types: what each vein or herb is, the skill it needs, and the item it gives
-- (the item's icon is used on the map). Object IDs let us recognise a node from its loot window.

local ADDON, ns = ...

-- name, kind, required skill, main item, object IDs
local TYPES = {
    -- Mining
    { "Copper Vein",                   "mine",   1, 2770,  { 1731, 2055, 3763, 103713, 181248 } },
    { "Tin Vein",                      "mine",  65, 2771,  { 1732, 2054, 3764, 103711, 181249 } },
    { "Incendicite Mineral Vein",      "mine",  65, 3340,  { 1610 } },
    { "Silver Vein",                   "mine",  75, 2775,  { 1733, 105569 } },
    { "Ooze Covered Silver Vein",      "mine",  75, 2775,  {} },
    { "Lesser Bloodstone Deposit",     "mine",  75, 4278,  { 2653 } },
    { "Iron Deposit",                  "mine", 125, 2772,  { 1735 } },
    { "Indurium Mineral Vein",         "mine", 150, 5833,  { 19903 } },
    { "Gold Vein",                     "mine", 155, 2776,  { 1734, 150080, 181109 } },
    { "Ooze Covered Gold Vein",        "mine", 155, 2776,  {} },
    { "Mithril Deposit",               "mine", 175, 3858,  { 2040, 150079, 176645 } },
    { "Ooze Covered Mithril Deposit",  "mine", 175, 3858,  {} },
    { "Truesilver Deposit",            "mine", 230, 7911,  { 2047, 150081, 181108 } },
    { "Ooze Covered Truesilver Deposit", "mine", 230, 7911, {} },
    { "Dark Iron Deposit",             "mine", 230, 11370, { 165658 } },
    { "Small Thorium Vein",            "mine", 245, 10620, { 324, 150082, 176643 } },
    { "Ooze Covered Thorium Vein",     "mine", 245, 10620, {} },
    { "Hakkari Thorium Vein",          "mine", 250, 10620, {} },
    { "Rich Thorium Vein",             "mine", 275, 10620, { 175404 } },
    { "Ooze Covered Rich Thorium Vein", "mine", 275, 10620, {} },

    -- Herbalism
    { "Peacebloom",          "herb",   1, 2447,  { 1618, 3724 } },
    { "Silverleaf",          "herb",   1, 765,   { 1617, 3725 } },
    { "Earthroot",           "herb",  15, 2449,  { 1619, 3726 } },
    { "Mageroyal",           "herb",  50, 785,   { 1620, 3727 } },
    { "Briarthorn",          "herb",  70, 2450,  { 1621, 3729 } },
    { "Stranglekelp",        "herb",  85, 3820,  { 2045 } },
    { "Bruiseweed",          "herb", 100, 2453,  { 1622, 3730 } },
    { "Wild Steelbloom",     "herb", 115, 3355,  { 1623 } },
    { "Grave Moss",          "herb", 120, 3369,  { 1628 } },
    { "Kingsblood",          "herb", 125, 3356,  { 1624 } },
    { "Liferoot",            "herb", 150, 3357,  { 2041 } },
    { "Fadeleaf",            "herb", 160, 3818,  { 2042 } },
    { "Goldthorn",           "herb", 170, 3821,  { 2046 } },
    { "Khadgar's Whisker",   "herb", 185, 3358,  { 2043 } },
    { "Wintersbite",         "herb", 195, 3819,  { 2044 } },
    { "Firebloom",           "herb", 205, 4625,  { 2866 } },
    { "Purple Lotus",        "herb", 210, 8831,  { 142140, 180165 } },
    { "Arthas' Tears",       "herb", 220, 8836,  { 142141, 176642 } },
    { "Sungrass",            "herb", 230, 8838,  { 142142, 176636, 180164 } },
    { "Blindweed",           "herb", 235, 8839,  { 142143, 183046 } },
    { "Ghost Mushroom",      "herb", 245, 8845,  { 142144 } },
    { "Gromsblood",          "herb", 250, 8846,  { 142145, 176637 } },
    { "Golden Sansam",       "herb", 260, 13464, { 176583, 176638, 180167 } },
    { "Dreamfoil",           "herb", 270, 13463, { 176584, 176639, 180168 } },
    { "Mountain Silversage", "herb", 280, 13465, { 176586, 176640, 180166 } },
    { "Plaguebloom",         "herb", 285, 13466, { 176587, 176641 } },
    { "Icecap",              "herb", 290, 13467, { 176588 } },
    { "Black Lotus",         "herb", 300, 13468, { 176589 } },
}

ns.TYPES = {}          -- name -> type
ns.TYPE_BY_OBJECT = {} -- object ID -> type
for _, t in ipairs(TYPES) do
    local def = { name = t[1], kind = t[2], skill = t[3], item = t[4] }
    ns.TYPES[def.name] = def
    for _, id in ipairs(t[5]) do ns.TYPE_BY_OBJECT[id] = def end
end

ns.SKILL_LINE = { mine = 186, herb = 182 } -- Mining, Herbalism
ns.KIND_LABEL = { mine = "Mining", herb = "Herbalism" }

-- Gathering colours: orange always gives a point, then yellow, green, grey (none).
function ns.Difficulty(def, skill)
    if not skill or skill < def.skill then return "red", { 1, 0.1, 0.1 } end
    local over = skill - def.skill
    if over < 25 then return "orange", { 1, 0.5, 0.25 } end
    if over < 50 then return "yellow", { 1, 1, 0 } end
    if over < 100 then return "green", { 0.25, 0.75, 0.25 } end
    return "grey", { 0.5, 0.5, 0.5 }
end

function ns.Icon(def)
    if def.icon == nil then
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        def.icon = (getIcon and getIcon(def.item))
            or (def.kind == "mine" and "Interface\\Icons\\Trade_Mining" or "Interface\\Icons\\INV_Misc_Flower_02")
    end
    return def.icon
end
