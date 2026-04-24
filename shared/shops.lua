if not Shops then
    Shops = {}
end

Shops["Weapon Vendor"] = {
    label = "Weapon Shop",
    type = "weapon",
    npc = {
        model = "s_m_y_ammucity_01",
        coords = vector4(1525.3685, 1683.9264, 109.0850, 89.6817),
        scenario = "WORLD_HUMAN_CLIPBOARD",
        icon = "fa-gun",
        interactLabel = "[E] Weapon Shop",
        interactDistance = 2.5
    },
    blip = {
        enabled = true,
        sprite = 110,
        color = 1,
        scale = 0.8,
        label = "Weapon Shop"
    },
    items = {
        {name = "WEAPON_WRENCH", price = 550, currency = "cash"},
        {name = "WEAPON_STONE_HATCHET", price = 1750, currency = "cash"},
        {name = "WEAPON_GOLFCLUB", price = 500, currency = "cash"},
        {name = "WEAPON_CROWBAR", price = 700, currency = "cash"},
        {name = "WEAPON_DAGGER", price = 1400, currency = "cash"},
        {name = "WEAPON_BAT", price = 450, currency = "cash"},
        {name = "WEAPON_STUNROD", price = 1200, currency = "cash"},
        {name = "WEAPON_HATCHET", price = 950, currency = "cash"}
    }
}

Shops["Vehicle Dealer"] = {
    label = "Bike Rental",
    type = "vehicle",
    catalogId = "bike_rental",
    npc = {
        model = "s_m_m_autoshop_02",
        coords = vector4(1521.7041, 1708.0355, 109.0362, 87.1826),
        scenario = "WORLD_HUMAN_CLIPBOARD",
        icon = "fa-car",
        interactLabel = "[E] Bike Rental",
        interactDistance = 2.5
    },
    spawnPoint = vector4(1514.8386, 1705.5475, 109.0917, 87.9302),
    blip = {
        enabled = true,
        sprite = 326,
        color = 3,
        scale = 0.8,
        label = "Bike Rental"
    },
    items = {}
}

local shopCount = 0
for _ in pairs(Shops) do shopCount = shopCount + 1 end
print('^2[COREX-INVENTORY] Shops configuration loaded (' .. shopCount .. ' shops)^0')
