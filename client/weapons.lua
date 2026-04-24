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

local function ApplyRecoil(category)
    if not Config.Recoil or not Config.Recoil.WeaponKick then return end
    if not Config.Recoil.WeaponKick.Enabled then return end
    if not Config.Recoil.Patterns then return end
    
    local pattern = Config.Recoil.Patterns[category] or Config.Recoil.Patterns.pistol
    if not pattern then return end
    
    local globalMult = Config.Recoil.WeaponKick.GlobalMultiplier or 1.0
    local attachmentMod = GetAttachmentModifiers()
    
    local recoilMultiplier = 1.0
    if consecutiveShots > 2 then
        recoilMultiplier = 1.0 + (math.min(consecutiveShots - 2, 15) * 0.08)
    end
    
    local verticalKick = (pattern.vertical or 0.4) * globalMult * attachmentMod * recoilMultiplier
    local horizontalKick = (pattern.horizontal or 0.2) * globalMult * attachmentMod
    
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
