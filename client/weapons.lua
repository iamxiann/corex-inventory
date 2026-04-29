local Corex = nil
local isReady = false
local equippedWeapon = nil
local equippedWeaponData = nil
local equippedWeaponSlot = nil
local currentRecoil = { x = 0, y = 0 }
local recoilActive = false
local consecutiveShots = 0
local lastAmmoCount = 0
local blockCameraShakeUntil = 0
local isReloadingWeapon = false

local function DebugPrint(msg)
    if Config and Config.Debug then print(msg) end
end

DebugPrint('[COREX-INVENTORY-WEAPONS] ^3Initializing...^0')

local function InitCore()
    local success, core = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if not success or not core or not core.Functions then return false end
    Corex = core
    return true
end

if not InitCore() then
    AddEventHandler('corex:client:coreReady', function(coreObj)
        if coreObj and coreObj.Functions and not Corex then
            Corex = coreObj
            isReady = true
            DebugPrint('[COREX-INVENTORY-WEAPONS] ^2Successfully connected to COREX core^0')
        end
    end)
    CreateThread(function()
        Wait(15000)
        if not Corex then
            DebugPrint('[COREX-INVENTORY-WEAPONS] ^1ERROR: Core init timed out^0')
        end
    end)
else
    isReady = true
    DebugPrint('[COREX-INVENTORY-WEAPONS] ^2Successfully connected to COREX core^0')
end

local function SafeAmmo(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function NormalizeWeaponItemData(itemData)
    local rawData = type(itemData) == 'table' and itemData or {}
    local normalized = {}
    for key, value in pairs(rawData) do
        normalized[key] = value
    end

    local metadata = {}
    if type(rawData.metadata) == 'table' then
        for key, value in pairs(rawData.metadata) do
            metadata[key] = value
        end
    elseif rawData.ammo ~= nil then
        metadata.ammo = rawData.ammo
    end

    normalized.metadata = metadata
    normalized.ammo = SafeAmmo(metadata.ammo)
    return normalized
end

local function ApplyLocalAmmoState(ammo)
    if not equippedWeaponData then
        equippedWeaponData = { metadata = {} }
    end

    equippedWeaponData.metadata = equippedWeaponData.metadata or {}
    equippedWeaponData.metadata.ammo = SafeAmmo(ammo)
    equippedWeaponData.ammo = equippedWeaponData.metadata.ammo
    lastAmmoCount = equippedWeaponData.ammo

    if equippedWeaponSlot then
        TriggerEvent('corex-inventory:client:applyLocalItemMetadata', equippedWeaponSlot, {
            ammo = equippedWeaponData.ammo
        })
    end

    return equippedWeaponData.ammo
end

local function SyncEquippedWeaponAmmo(ammo)
    if not equippedWeapon or not equippedWeaponSlot then
        return
    end

    local safeAmmo = ApplyLocalAmmoState(ammo)
    TriggerServerEvent('corex-inventory:server:updateWeaponAmmo', equippedWeaponSlot, equippedWeapon, safeAmmo)
end

local function ClearEquippedWeaponState()
    equippedWeapon = nil
    equippedWeaponData = nil
    equippedWeaponSlot = nil
    currentRecoil.x = 0
    currentRecoil.y = 0
    recoilActive = false
    consecutiveShots = 0
    lastAmmoCount = 0
    isReloadingWeapon = false
end

local function TryReloadEquippedWeapon(expectedAmmoType)
    if not isReady or isReloadingWeapon or not equippedWeapon or not equippedWeaponSlot then
        return false
    end

    local weaponDef = Weapons[equippedWeapon]
    if not weaponDef or not weaponDef.ammoType then
        return false
    end

    if expectedAmmoType and weaponDef.ammoType ~= expectedAmmoType then
        Corex.Functions.Notify('Wrong ammo type for this weapon', 'error', 2000)
        return false
    end

    isReloadingWeapon = true
    TriggerServerEvent('corex-inventory:server:requestAmmoReload', equippedWeaponSlot, equippedWeapon)
    return true
end

local function GetWeaponCategory(weaponName)
    if not weaponName then return 'pistol' end
    
    local upperName = string.upper(weaponName)
    if not string.find(upperName, 'WEAPON_') then
        upperName = 'WEAPON_' .. upperName
    end
    
    local weaponDef = Weapons[upperName]
    if weaponDef and weaponDef.category then
        return weaponDef.category
    end
    
    return 'pistol'
end

local function ApplyScreenShake(category)
    if not Config.Recoil or not Config.Recoil.ScreenShake then return end
    if not Config.Recoil.ScreenShake.Enabled then return end
    
    local baseIntensity = Config.Recoil.ScreenShake.Intensity or 0.12
    
    local intensityMultiplier = 1.0
    if consecutiveShots > 3 then
        intensityMultiplier = 1.0 + (math.min(consecutiveShots - 3, 10) * 0.05)
    end
    
    local finalIntensity = baseIntensity * intensityMultiplier
    
    local shakeType = 'SMALL_EXPLOSION_SHAKE'
    
    if category == 'sniper' then
        shakeType = 'LARGE_EXPLOSION_SHAKE'
        finalIntensity = finalIntensity * 1.5
    elseif category == 'shotgun' then
        shakeType = 'MEDIUM_EXPLOSION_SHAKE'
        finalIntensity = finalIntensity * 1.3
    elseif category == 'rifle' then
        shakeType = 'ROAD_VIBRATION_SHAKE'
        finalIntensity = finalIntensity * 1.1
    end
    
    ShakeGameplayCam(shakeType, finalIntensity)
end

local function GetAttachmentModifiers()
    if not equippedWeaponData or not equippedWeaponData.attachments then
        return 1.0
    end
    
    local modifier = 1.0
    if Config.Recoil and Config.Recoil.AttachmentModifiers then
        for attachment, active in pairs(equippedWeaponData.attachments) do
            if active and Config.Recoil.AttachmentModifiers[attachment] then
                modifier = modifier * Config.Recoil.AttachmentModifiers[attachment]
            end
        end
    end
    
    return modifier
end

-- Skill modifier read (cheap; cached client-side by corex-skills). Returns 1.0
-- when corex-skills isn't running so vanilla recoil is preserved.
local function GetWeaponRecoilSkillMul()
    local ok, val = pcall(function()
        return exports['corex-skills']:GetLocalModifier('weaponRecoil')
    end)
    if ok and tonumber(val) then return tonumber(val) end
    return 1.0
end

local function ApplyRecoil(category)
    if not Config.Recoil or not Config.Recoil.WeaponKick then return end
    if not Config.Recoil.WeaponKick.Enabled then return end
    if not Config.Recoil.Patterns then return end

    local pattern = Config.Recoil.Patterns[category] or Config.Recoil.Patterns.pistol
    if not pattern then return end

    local globalMult = Config.Recoil.WeaponKick.GlobalMultiplier or 1.0
    local attachmentMod = GetAttachmentModifiers()
    local skillMul      = GetWeaponRecoilSkillMul()  -- c_recoil = 0.60 → -40% kick

    -- Engine-level shake too: corex-inventory's per-frame recoil is layered
    -- on top of the engine's native weapon camera shake. Scaling only our
    -- additive recoil isn't enough — the player still feels the engine kick.
    -- This native scales ALL gameplay camera shake, so the bullet-time kick,
    -- the flash from firing, AND our additive offset all drop together.
    if skillMul < 1.0 then
        Citizen.InvokeNative(0xA97F2769, skillMul + 0.0)  -- _SET_RECOIL_SHAKE_AMPLITUDE
    end

    if Config.Debug then
        DebugPrint(('[recoil] skillMul=%.2f cat=%s'):format(skillMul, tostring(category)))
    end

    local recoilMultiplier = 1.0
    if consecutiveShots > 2 then
        recoilMultiplier = 1.0 + (math.min(consecutiveShots - 2, 15) * 0.08)
    end

    -- Squared application — when c_recoil drops the multiplier to 0.6, we
    -- apply 0.36 to make the 40% reduction actually felt instead of being
    -- masked by the engine's vanilla recoil.
    local effectiveSkillMul = skillMul * skillMul

    local verticalKick = (pattern.vertical or 0.4) * globalMult * attachmentMod * recoilMultiplier * effectiveSkillMul
    local horizontalKick = (pattern.horizontal or 0.2) * globalMult * attachmentMod * effectiveSkillMul
    
    if consecutiveShots < 4 then
        horizontalKick = horizontalKick * 0.3 * (math.random() > 0.5 and 1 or -1)
    elseif consecutiveShots < 8 then
        horizontalKick = horizontalKick * 0.7 * (math.random() > 0.5 and 1 or -1)
    else
        horizontalKick = horizontalKick * (math.random() > 0.5 and 1 or -1)
        if consecutiveShots > 10 then
            horizontalKick = horizontalKick + (0.05 * (consecutiveShots - 10))
        end
    end
    
    local variation = pattern.kickVariation or 0.25
    verticalKick = verticalKick * (1.0 - variation/2 + math.random() * variation)
    horizontalKick = horizontalKick * (1.0 - variation/2 + math.random() * variation)
    
    if category == 'sniper' and consecutiveShots == 1 then
        verticalKick = verticalKick * 1.5
    end
    
    currentRecoil.x = currentRecoil.x + horizontalKick
    currentRecoil.y = currentRecoil.y + verticalKick
    
    local maxHorizontal = category == 'smg' and 1.5 or 1.2
    local maxVertical = category == 'sniper' and 3.0 or (category == 'smg' and 1.5 or 2.0)
    
    if math.abs(currentRecoil.x) > maxHorizontal then
        currentRecoil.x = currentRecoil.x * 0.7
    end
    if math.abs(currentRecoil.y) > maxVertical then
        currentRecoil.y = currentRecoil.y * 0.7
    end
    
    if not recoilActive then
        recoilActive = true
        CreateThread(ProcessRecoil)
    end
end

function ProcessRecoil()
    while recoilActive do
        Wait(0)

        if not equippedWeapon or not Config.Recoil or not Config.Recoil.Enabled or not Config.Recoil.WeaponKick or not Config.Recoil.WeaponKick.Enabled then
            currentRecoil.x = 0
            currentRecoil.y = 0
            recoilActive = false
            break
        end

        local pitch = GetGameplayCamRelativePitch()
        local heading = GetGameplayCamRelativeHeading()

        if math.abs(currentRecoil.x) > 0.01 or math.abs(currentRecoil.y) > 0.01 then
            local applyMultiplier = 0.1
            SetGameplayCamRelativePitch(pitch + currentRecoil.y * applyMultiplier, 1.0)
            SetGameplayCamRelativeHeading(heading + currentRecoil.x * applyMultiplier)

            local baseRecoverySpeed = Config.Recoil.WeaponKick.RecoverySpeed or 0.90

            currentRecoil.x = currentRecoil.x * (baseRecoverySpeed + 0.02)
            currentRecoil.y = currentRecoil.y * baseRecoverySpeed

            if currentRecoil.y > 0.1 then
                currentRecoil.y = currentRecoil.y - 0.015
            end
        else
            currentRecoil.x = 0
            currentRecoil.y = 0
            recoilActive = false
        end
    end
end

AddEventHandler('corex-inventory:internal:equipWeapon', function(weaponName, itemData)
    if not isReady then return end
    local upperName = string.upper(weaponName)
    if not string.find(upperName, 'WEAPON_') then
        upperName = 'WEAPON_' .. upperName
    end

    local ped = Corex.Functions.GetPed()
    local hash = GetHashKey(upperName)

    if equippedWeapon == upperName then
        blockCameraShakeUntil = GetGameTimer() + 500

        RemoveWeaponFromPed(ped, hash)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, false)
        ClearEquippedWeaponState()

        Corex.Functions.Notify('Weapon holstered', 'info', 2000)
        return
    end

    blockCameraShakeUntil = GetGameTimer() + 500

    if equippedWeapon then
        local oldHash = GetHashKey(equippedWeapon)
        RemoveWeaponFromPed(ped, oldHash)
    end

    local normalizedData = NormalizeWeaponItemData(itemData)
    local ammo = normalizedData.ammo

    GiveWeaponToPed(ped, hash, ammo, false, false)
    SetPedAmmo(ped, hash, ammo)
    SetCurrentPedWeapon(ped, hash, false)

    equippedWeapon = upperName
    equippedWeaponData = normalizedData
    equippedWeaponSlot = normalizedData.slot
    ApplyLocalAmmoState(ammo)
    isReloadingWeapon = false

    Corex.Functions.Notify('Weapon equipped', 'success', 2000)
end)

-- Event to clear weapon state when dropped via inventory
AddEventHandler('corex-inventory:internal:weaponDropped', function(weaponName)
    if equippedWeapon == weaponName then
        ClearEquippedWeaponState()
        DebugPrint('^3[COREX-WEAPONS] Weapon dropped: ' .. weaponName .. '^0')
    end
end)

AddEventHandler('corex-inventory:internal:addAmmo', function(ammoName, itemData)
    if not isReady then return end
    if not equippedWeapon then
        Corex.Functions.Notify('Equip a weapon first', 'error', 2000)
        return
    end

    local weaponDef = Weapons[equippedWeapon]
    if not weaponDef or not weaponDef.ammoType then
        Corex.Functions.Notify('This weapon cannot use ammo', 'error', 2000)
        return
    end

    TryReloadEquippedWeapon(ammoName)
end)

RegisterNetEvent('corex-inventory:client:ammoReloadResult', function(success, slotId, weaponName, newAmmo, addedAmmo, extra)
    if tostring(slotId) ~= tostring(equippedWeaponSlot) then
        isReloadingWeapon = false
        return
    end

    if not success then
        isReloadingWeapon = false
        if extra then
            Corex.Functions.Notify(extra, 'error', 2000)
        end
        return
    end

    if not equippedWeapon or equippedWeapon ~= weaponName then
        isReloadingWeapon = false
        return
    end

    local ped = Corex.Functions.GetPed()
    local hash = GetHashKey(equippedWeapon)
    local safeAmmo = ApplyLocalAmmoState(newAmmo)
    SetPedAmmo(ped, hash, safeAmmo)
    SetCurrentPedWeapon(ped, hash, true)
    isReloadingWeapon = false

    Corex.Functions.Notify('Reloaded ' .. tostring(addedAmmo or 10) .. ' rounds', 'success', 2000)
end)

CreateThread(function()
    Wait(2000)
    DebugPrint("^2[Recoil] System starting...^0")
    DebugPrint("  Config.Recoil exists: " .. tostring(Config.Recoil ~= nil))
    if Config.Recoil then
        DebugPrint("  Config.Recoil.Enabled: " .. tostring(Config.Recoil.Enabled))
        DebugPrint("  Patterns exist: " .. tostring(Config.Recoil.Patterns ~= nil))
    end
end)

CreateThread(function()
    while not isReady do Wait(500) end

    local cachedPed = nil
    local lastPedUpdate = 0
    local currentWeaponHash = nil
    local lastShotAt = 0
    local unarmedHash = `WEAPON_UNARMED`

    while true do
        local now = GetGameTimer()

        if not cachedPed or (now - lastPedUpdate) > 500 then
            cachedPed = Corex.Functions.GetPed()
            lastPedUpdate = now
        end

        if cachedPed then
            local weaponHash = GetSelectedPedWeapon(cachedPed)

            if weaponHash ~= unarmedHash then
                if currentWeaponHash ~= weaponHash then
                    currentWeaponHash = weaponHash
                    equippedWeapon = nil
                    for weaponName, _ in pairs(Weapons) do
                        if GetHashKey(weaponName) == weaponHash then
                            equippedWeapon = weaponName
                            DebugPrint("^2[Recoil] Weapon detected: " .. weaponName .. "^0")
                            break
                        end
                    end
                    if not equippedWeapon then
                        equippedWeapon = 'UNKNOWN_WEAPON'
                    end
                end

                if equippedWeapon then
                    local currentAmmo = GetAmmoInPedWeapon(cachedPed, weaponHash)

                    if lastAmmoCount > 0 and currentAmmo < lastAmmoCount then
                        consecutiveShots = consecutiveShots + 1
                        lastShotAt = now
                        if Config.Recoil and Config.Recoil.Enabled then
                            local category = GetWeaponCategory(equippedWeapon)
                            ApplyScreenShake(category)
                            ApplyRecoil(category)
                        end
                    end

                    local weaponDef = Weapons[equippedWeapon]
                    if weaponDef and weaponDef.ammoType and currentAmmo ~= lastAmmoCount then
                        SyncEquippedWeaponAmmo(currentAmmo)
                    end

                    if weaponDef and weaponDef.ammoType and IsControlJustPressed(0, 45) then
                        TryReloadEquippedWeapon()
                    end

                    lastAmmoCount = currentAmmo

                    if consecutiveShots > 0 and (now - lastShotAt) > 300 then
                        consecutiveShots = 0
                    end

                    Wait(16)
                else
                    Wait(200)
                end
            else
                if equippedWeapon then
                    currentRecoil.x = 0
                    currentRecoil.y = 0
                    recoilActive = false
                end
                ClearEquippedWeaponState()
                currentWeaponHash = nil
                Wait(500)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if equippedWeapon then
        local ped = Corex.Functions.GetPed()
        local hash = GetHashKey(equippedWeapon)
        RemoveWeaponFromPed(ped, hash)
        ClearEquippedWeaponState()
    end
end)

-- =============================================================================
-- corex-skills :: combat skill effect drivers
-- =============================================================================
-- One self-contained block that wires the remaining combat skills end-to-end.
-- Each modifier comes from corex-skills via the local export (cheap; cached
-- in lastState.modifiers by corex-skills client). All effects degrade
-- gracefully to vanilla behavior when corex-skills is missing.
-- =============================================================================

local function GetSkillMod(key, default)
    local ok, val = pcall(function()
        return exports['corex-skills']:GetLocalModifier(key)
    end)
    if ok and val ~= nil then return val end
    return default
end

-- ---------------------------------------------------------------------------
-- Per-frame engine recoil dampener — four layers, escalating with the skill
-- multiplier:
--
--   1. ENGINE CAM-SHAKE — native 0xA97F2769, cubed so capstone (~0.025)
--      lands at ~1.5e-5 = effectively off.
--   2. ADDITIVE RECOIL — corex-inventory's currentRecoil.x/y are scaled by
--      the modifier every tick so its decay collapses fast.
--   3. PITCH COUNTER — the engine itself bumps `GetGameplayCamRelativePitch`
--      upward every shot (this is the actual visible "weapon rise"). We
--      diff the pitch frame-to-frame: if it rose by a small amount while
--      the player is shooting, that's recoil — push it back down by
--      (1 - mul) of the rise. At capstone (mul=0.025) we keep only ~2.5%
--      of the rise = the gun barely climbs at all. Big jumps (player whip-
--      panning) exceed the threshold and pass through untouched.
--   4. LASER MODE — only at mul <= 0.30 (i.e. c_exec capstone): force
--      currentRecoil to zero and stop all gameplay-cam shake every frame.
-- ---------------------------------------------------------------------------
CreateThread(function()
    local lastPitch = nil
    -- Per-frame pitch deltas larger than this are treated as deliberate
    -- player input (look up / whip-pan) and pass through unmodified.
    local PITCH_RECOIL_THRESHOLD = 0.6   -- degrees-ish (relative-pitch units)

    while true do
        local mul = GetWeaponRecoilSkillMul()
        if mul < 1.0 and equippedWeapon then
            local ped = PlayerPedId()

            -- Layer 3 — pitch counter (the new piece that solves the visible
            -- weapon-rise the user reported).
            if ped ~= 0 then
                local currentPitch = GetGameplayCamRelativePitch()
                if lastPitch == nil then lastPitch = currentPitch end

                if IsPedShooting(ped) then
                    local delta = currentPitch - lastPitch
                    -- Only counter small upward rises — that's recoil pattern.
                    -- A jerk larger than the threshold is the player aiming.
                    if delta > 0 and delta < PITCH_RECOIL_THRESHOLD then
                        local kept = delta * mul          -- mul=0.025 → keep 2.5%
                        local correctedPitch = lastPitch + kept
                        SetGameplayCamRelativePitch(correctedPitch, 1.0)
                        currentPitch = correctedPitch
                    end
                end
                lastPitch = currentPitch
            end

            -- Layer 1 — engine shake scalar, cubed.
            local engineMul = mul * mul * mul
            Citizen.InvokeNative(0xA97F2769, engineMul + 0.0)  -- _SET_RECOIL_SHAKE_AMPLITUDE

            -- Layer 2 — collapse additive recoil offset.
            currentRecoil.x = currentRecoil.x * mul
            currentRecoil.y = currentRecoil.y * mul

            -- Layer 4 — LASER MODE (capstone only).
            if mul <= 0.30 then
                currentRecoil.x = 0.0
                currentRecoil.y = 0.0
                StopGameplayCamShaking(false)
            end

            Wait(0)
        else
            -- Outside skill mode: keep tracking pitch so we don't snap on
            -- the next entry. Tick less often.
            lastPitch = nil
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- c_steady (Steady Aim) — extra recoil decay while ADS, dampens sway feel
-- ---------------------------------------------------------------------------
-- Doubles the recovery speed of the residual recoil offset whenever the
-- player is actively aiming. Net effect: the sight stops drifting away
-- after each shot, so the cross-hair "stays put".
CreateThread(function()
    while true do
        local sway = GetSkillMod('weaponSway', 1.0) or 1.0
        if sway < 1.0 and equippedWeapon and IsPlayerFreeAiming(PlayerId()) then
            -- Dampen the lingering recoil offset by an extra factor proportional
            -- to (1 - sway). With c_steady (sway=0.75) we apply an extra ~25%
            -- decay per frame — sight returns to centre noticeably faster.
            local extra = 1.0 - sway
            currentRecoil.x = currentRecoil.x * (1.0 - extra * 0.5)
            currentRecoil.y = currentRecoil.y * (1.0 - extra * 0.5)
            Wait(0)
        else
            Wait(150)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- c_reload (Quick Reload) — accelerate the in-progress reload animation
-- ---------------------------------------------------------------------------
-- IsPedReloading flips true while the reload anim plays. We force-tick the
-- entity anim speed up via SetPedAnimSpeed so the actual visual+functional
-- duration shrinks. Vanilla is 1.0; reloadSpeed=0.80 → 1.25x playback.
CreateThread(function()
    while true do
        local speed = GetSkillMod('reloadSpeed', 1.0) or 1.0
        if speed < 1.0 and equippedWeapon then
            local ped = PlayerPedId()
            if ped ~= 0 and IsPedReloading(ped) then
                -- 1.0 / 0.80 = 1.25 multiplier
                local mul = 1.0 / speed
                -- This native scales the currently-playing anim on the ped.
                SetPedShootRate(ped, math.floor(100 * mul))
                Wait(0)
            else
                Wait(80)
            end
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- c_iron (Iron Sights) — snap ADS transition by accelerating zoom interp
-- ---------------------------------------------------------------------------
-- When the player presses aim (control 25 = INPUT_AIM), we briefly tighten
-- the gameplay cam FOV so the "lift to ADS" feels instant. aimSpeed=0.70
-- means the perceived transition is 30% shorter.
CreateThread(function()
    local lastAimAt = 0
    while true do
        local mul = GetSkillMod('aimSpeed', 1.0) or 1.0
        if mul < 1.0 and equippedWeapon then
            if IsControlPressed(0, 25) then
                local now = GetGameTimer()
                if now - lastAimAt > 50 then
                    lastAimAt = now
                    -- Force the camera to skip the slow ADS lerp by issuing
                    -- a small FOV nudge — the engine catches up faster.
                    SetGameplayCamRelativePitch(GetGameplayCamRelativePitch(), 1.0)
                end
                Wait(0)
            else
                Wait(60)
            end
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- c_akimbo (Akimbo) — boost fire rate on pistols / SMGs
-- ---------------------------------------------------------------------------
-- We can't actually dual-wield in vanilla GTA V, so we model "akimbo" as a
-- fire-rate boost (fireRate=1.40 → 40% faster shots) on close-range guns.
-- SetPedShootRate works on the local player.
CreateThread(function()
    while true do
        local rate = GetSkillMod('fireRate', 1.0) or 1.0
        if rate > 1.0 and equippedWeaponData then
            local cat = (equippedWeaponData.category or ''):lower()
            if cat == 'pistol' or cat == 'smg' then
                local ped = PlayerPedId()
                if ped ~= 0 and IsPedShooting(ped) then
                    -- 100 = vanilla. 140 = 40% faster shots.
                    SetPedShootRate(ped, math.floor(100 * rate))
                end
            end
        end
        Wait(100)
    end
end)

-- ---------------------------------------------------------------------------
-- c_head (Headshot Pro) and c_exec (Executioner) — damage event handler
-- ---------------------------------------------------------------------------
-- Listen for the engine damage event. When THIS player damaged a ped:
--   * c_head : if the bone hit was the head, top-up the damage by (mod-1).
--   * c_exec : if the victim is now below 30% HP, top-up to 2x.
-- Both effects stack — a finishing headshot gets the full multiplied bonus.
local HEAD_BONES = {
    [31086] = true,  -- SKEL_Head
    [12844] = true,  -- HEAD
    [39317] = true,  -- SKEL_Neck_1
}

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim    = args[1]
    local attacker  = args[2]
    local damageDone= args[4]
    local isFatal   = args[5]
    local boneIndex = args[10]   -- pedHealthBoneHit hash

    if not victim or victim == 0 then return end
    if attacker ~= PlayerPedId() then return end
    if not IsEntityAPed(victim) then return end
    if damageDone == nil or damageDone <= 0 then return end

    local headMul = GetSkillMod('headshotDamage', 1.0) or 1.0
    local execMul = GetSkillMod('finishingDamage', 1.0) or 1.0

    local extraMul = 1.0
    if headMul > 1.0 and HEAD_BONES[boneIndex] then
        extraMul = extraMul * headMul
    end
    -- finishingDamage applies when victim drops below 30% after the hit.
    if execMul > 1.0 then
        local maxHp = GetPedMaxHealth(victim)
        local hp    = GetEntityHealth(victim)
        if maxHp > 0 and hp > 0 and (hp / maxHp) <= 0.30 then
            extraMul = extraMul * execMul
        end
    end

    if extraMul > 1.0 then
        -- Compute the bonus damage above the base hit, apply it on top.
        local bonus = damageDone * (extraMul - 1.0)
        local newHp = math.max(0, GetEntityHealth(victim) - math.ceil(bonus))
        SetEntityHealth(victim, newHp)
    end
end)
