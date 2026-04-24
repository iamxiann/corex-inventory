local Corex = nil
local isReady = false
local spawnedNPCs = {}
local spawnedBlips = {}

CreateThread(function()
    while not Corex do
        Wait(100)
        local success, core = pcall(function()
            return exports['corex-core']:GetCoreObject()
        end)
        if success and core and core.Functions then
            Corex = core
            isReady = true
            break
        end
    end
end)

local function SpawnNPC(shopName, npcData)
    if not npcData or not npcData.coords then return nil end

    local modelHash = GetHashKey(npcData.model)

    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 50 do
        Wait(100)
        attempts = attempts + 1
    end

    if not HasModelLoaded(modelHash) then
        print('^1[COREX-INVENTORY] Failed to load NPC model: ' .. npcData.model .. '^0')
        return nil
    end

    local npc = CreatePed(4, modelHash, npcData.coords.x, npcData.coords.y, npcData.coords.z, npcData.coords.w, false, true)

    SetEntityAsMissionEntity(npc, true, true)
    SetPedFleeAttributes(npc, 0, false)
    SetPedCombatAttributes(npc, 17, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetEntityInvincible(npc, true)
    FreezeEntityPosition(npc, true)

    if npcData.scenario then
        TaskStartScenarioInPlace(npc, npcData.scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(modelHash)

    return npc
end

local function CreateShopBlips()
    for shopName, shopData in pairs(Shops) do
        if shopData.blip and shopData.blip.enabled and shopData.npc then
            local coords = shopData.npc.coords
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, shopData.blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, shopData.blip.scale)
            SetBlipColour(blip, shopData.blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(shopData.blip.label or shopData.label)
            EndTextCommandSetBlipName(blip)

            table.insert(spawnedBlips, blip)
        end
    end
end

local function SpawnShopNPCs()
    for shopName, shopData in pairs(Shops) do
        if shopData.npc then
            print('^3[COREX-INVENTORY] Spawning shop NPC: ' .. shopName .. '^0')
            local npc = SpawnNPC(shopName, shopData.npc)

            if npc then
                print('^2[COREX-INVENTORY] NPC spawned: ' .. shopName .. ' (Entity: ' .. npc .. ')^0')
                table.insert(spawnedNPCs, {
                    entity = npc,
                    shopName = shopName,
                    data = shopData.npc
                })

                Wait(500)

                local success, result = pcall(function()
                    return exports['corex-core']:AddTarget(npc, {
                        text = shopData.npc.interactLabel or ("[E] " .. shopData.label),
                        icon = shopData.npc.icon or "fa-store",
                        distance = shopData.npc.interactDistance or 2.5,
                        event = 'corex-inventory:client:openShopFromInteract',
                        data = {
                            shopName = shopName
                        }
                    })
                end)

                if success then
                    print('^2[COREX-INVENTORY] Added interact target for: ' .. shopName .. '^0')
                else
                    print('^1[COREX-INVENTORY] Failed to add target: ' .. tostring(result) .. '^0')
                end
            else
                print('^1[COREX-INVENTORY] Failed to spawn NPC: ' .. shopName .. '^0')
            end
        end
    end
end

CreateThread(function()
    while not isReady or not Shops do
        Wait(500)
    end

    Wait(2000)
    CreateShopBlips()
    SpawnShopNPCs()
end)

RegisterNetEvent('corex-inventory:client:openShopFromInteract', function(entity, data)
    TriggerEvent('corex-inventory:client:openShopFromNPC', data.shopName)
end)

AddEventHandler('corex-inventory:client:openShopFromNPC', function(shopName)
    if not shopName then return end

    print('^3[COREX-INVENTORY] Opening shop from NPC: ' .. shopName .. '^0')

    if Shops[shopName] then
        if Shops[shopName].type == "vehicle" then
            OpenVehicleShop(shopName)
            return
        end

        OpenShop(shopName)
    else
        print('^1[COREX-INVENTORY] Shop not found: ' .. shopName .. '^0')
        Corex.Functions.Notify('Shop not available!', 'error', 3000)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, npcInfo in ipairs(spawnedNPCs) do
        if DoesEntityExist(npcInfo.entity) then
            DeleteEntity(npcInfo.entity)
        end
    end

    for _, blip in ipairs(spawnedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
end)

exports('GetShopNPCs', function()
    return spawnedNPCs
end)
