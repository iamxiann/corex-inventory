--[[
    COREX Inventory - Weapons Definition
]]

Weapons = {
    ['WEAPON_WRENCH'] = {
        label = 'Wrench',
        weight = 2.1,
        size = {w = 1, h = 3},
        image = 'WEAPON_WRENCH.png',
        ammoType = nil,
        prop = 'w_me_wrench',
        rarity = 'common',
        category = 'melee'
    },

    ['WEAPON_STONE_HATCHET'] = {
        label = 'Stone Hatchet',
        weight = 2.4,
        size = {w = 2, h = 2},
        image = 'WEAPON_STONE_HATCHET.png',
        ammoType = nil,
        prop = 'w_me_stonehatchet',
        rarity = 'rare',
        category = 'melee'
    },

    ['WEAPON_GOLFCLUB'] = {
        label = 'Golf Club',
        weight = 1.9,
        size = {w = 1, h = 4},
        image = 'WEAPON_GOLFCLUB.png',
        ammoType = nil,
        prop = 'w_me_gclub',
        rarity = 'common',
        category = 'melee'
    },

    ['WEAPON_CROWBAR'] = {
        label = 'Crowbar',
        weight = 2.0,
        size = {w = 1, h = 3},
        image = 'WEAPON_CROWBAR.png',
        ammoType = nil,
        prop = 'w_me_crowbar',
        rarity = 'common',
        category = 'melee'
    },

    ['WEAPON_DAGGER'] = {
        label = 'Dagger',
        weight = 1.1,
        size = {w = 1, h = 2},
        image = 'WEAPON_DAGGER.png',
        ammoType = nil,
        prop = 'w_me_dagger',
        rarity = 'uncommon',
        category = 'melee'
    },

    ['WEAPON_BAT'] = {
        label = 'Bat',
        weight = 2.2,
        size = {w = 1, h = 4},
        image = 'WEAPON_BAT.png',
        ammoType = nil,
        prop = 'w_me_bat',
        rarity = 'common',
        category = 'melee'
    },

    ['WEAPON_STUNROD'] = {
        label = 'Stun Rod',
        weight = 1.8,
        size = {w = 1, h = 3},
        image = 'WEAPON_STUNROD.png',
        ammoType = nil,
        prop = 'w_me_nightstick',
        rarity = 'uncommon',
        category = 'melee'
    },

    ['WEAPON_HATCHET'] = {
        label = 'Hatchet',
        weight = 1.7,
        size = {w = 1, h = 3},
        image = 'WEAPON_HATCHET.png',
        ammoType = nil,
        prop = 'w_me_hatchet',
        rarity = 'common',
        category = 'melee'
    },
    -- ═══════════════════════════════════════
    -- PISTOLS
    -- ═══════════════════════════════════════
    
    ['WEAPON_CERAMICPISTOL'] = {
        label = 'Ceramic Pistol',
        weight = 1.8,
        size = {w = 2, h = 1},
        image = 'Ceramic_Pistol.png',
        ammoType = 'pistol_ammo',
        prop = 'w_pi_ceramic_pistol',
        rarity = 'uncommon',
        category = 'pistol'
    },
    
    ['WEAPON_GADGETPISTOL'] = {
        label = 'Perico Pistol',
        weight = 1.5,
        size = {w = 2, h = 1},
        image = 'weapon_perico_pistol.png',
        ammoType = 'pistol_ammo',
        prop = 'w_pi_singleshoth4',
        rarity = 'rare',
        category = 'pistol'
    },
    
    ['WEAPON_DOUBLEACTION'] = {
        label = 'Double-Action Revolver',
        weight = 2.2,
        size = {w = 2, h = 1},
        image = 'revolver_7.png',
        ammoType = 'pistol_ammo',
        prop = 'w_pi_wep1_gun',
        rarity = 'common',
        category = 'pistol'
    },
    
    ['WEAPON_RAYPISTOL'] = {
        label = 'Up-n-Atomizer',
        weight = 2.5,
        size = {w = 2, h = 1},
        image = 'weapon_raypistol.png',
        ammoType = nil,
        prop = 'w_pi_raygun',
        rarity = 'legendary',
        category = 'pistol'
    },
    
    ['WEAPON_PISTOL_MK2'] = {
        label = 'Pistol Mk II',
        weight = 2.0,
        size = {w = 2, h = 1},
        image = 'pistol_mk2.png',
        ammoType = 'pistol_ammo',
        prop = 'w_pi_pistolmk2',
        rarity = 'epic',
        category = 'pistol'
    },
    
    -- ═══════════════════════════════════════
    -- SMG
    -- ═══════════════════════════════════════
    
    ['WEAPON_COMBATPDW'] = {
        label = 'Combat PDW',
        weight = 3.0,
        size = {w = 2, h = 2},
        image = 'weapon_combatpdw.png',
        ammoType = 'smg_ammo',
        prop = 'w_sb_pdw',
        rarity = 'mythic',
        category = 'smg'
    },
    
    ['WEAPON_TECPISTOL'] = {
        label = 'Tactical SMG',
        weight = 2.8,
        size = {w = 2, h = 1},
        image = 'Tactical_SMG.png',
        ammoType = 'smg_ammo',
        prop = 'w_pi_pistolsmg_m31',
        rarity = 'epic',
        category = 'smg'
    },
    

}

Ammo = {
    ['pistol_ammo'] = {
        label = 'Pistol Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 200,
        image = 'pistol_ammopack.png',
        prop = 'prop_box_ammo07a',
        rarity = 'common'
    },
    
    ['smg_ammo'] = {
        label = 'SMG Ammo',
        weight = 0.1,
        size = {w = 1, h = 1},
        stackable = true,
        maxStack = 300,
        image = 'smg_ammopack.png',
        prop = 'prop_box_ammo07b',
        rarity = 'common'
    }
}
