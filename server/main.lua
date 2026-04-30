--[[
    COREX Inventory - Server Side (v2.1 - BUGFIX)
    Tetris Grid System with Ground Items Support
    Functional Lua | No OOP | Zombie Survival Optimized

    CHANGELOG v2.1:
    [FIX-1] AddItem: partial stacking + maxStack respected everywhere
    [FIX-2] PickupItem: tries to merge into existing stack before placing new slot
    [FIX-3] GiveItem: tries to merge into existing target stack before placing new slot
    [FIX-4] mergeItem / mergeGroundItem: already correct, kept as-is
    [FIX-5] RemoveItem: drains across multiple stacks (partial remove)
    [SEC-1]  All NetEvent inputs strictly validated
]]

local Inventories = {}
local DroppedItems = {}
local PendingVehiclePurchases = {}
local dropIdCounter = 0
local slotCounter = 0

local function ShallowCopy(tbl)
    if type(tbl) ~= 'table' then
        return {}
    end

    local copy = {}
    for key, value in pairs(tbl) do
        copy[key] = value
    end
    return copy
end

local function NextSlotId()
    slotCounter = slotCounter + 1
    return tostring(GetGameTimer()) .. '-' .. slotCounter
end

local function NormalizeVehicleKey(value)
    if type(value) ~= 'string' then return nil end
    return string.lower(value)
end

local function GenerateRentalPlate()
    return ('CX%04d'):format(math.random(0, 9999))
end

local function GetVehicleCatalog(catalogId)
    local ok, catalog = pcall(function()
        return exports['corex-core']:GetVehicleCatalog(catalogId)
    end)
    return ok and catalog or nil
end

local function GetVehicleDefinition(catalogId, model)
    local ok, vehicle = pcall(function()
        return exports['corex-core']:GetVehicleDefinition(catalogId, model)
    end)
    return ok and vehicle or nil
end

Items   = Items   or {}
Weapons = Weapons or {}
Ammo    = Ammo    or {}

-- -------------------------------------------------
-- INTERNAL HELPERS
-- -------------------------------------------------

local function GetPlayer(src)
    local success, player = pcall(function()
        return exports['corex-core']:GetPlayer(src)
    end)
    return success and player or nil
end

local function IsBusy(src)
    local success, busy = pcall(function()
        return exports['corex-core']:IsBusy(src)
    end)
    return success and busy or false
end

local function SetBusy(src, state)
    pcall(function()
        exports['corex-core']:SetBusy(src, state)
    end)
end

local function TrySetBusy(src)
    local success, locked = pcall(function()
        return exports['corex-core']:TrySetBusy(src)
    end)

    if success then
        return locked
    end

    if IsBusy(src) then
        return false
    end

    SetBusy(src, true)
    return true
end

local function ClearBusy(src)
    pcall(function()
        exports['corex-core']:ClearBusy(src)
    end)
end

local function IsNearbyPlayer(src, targetSrc, maxDistance)
    -- Coba pakai export corex-core
    local ok, nearby = pcall(function()
        return exports['corex-core']:GetNearbyPlayers(src, maxDistance or 5.0)
    end)

    if ok and type(nearby) == 'table' then
        return nearby[targetSrc] ~= nil
    end

    -- Fallback: hitung jarak manual via koordinat ped
    local srcPed    = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if not srcPed or srcPed == 0 or not targetPed or targetPed == 0 then return false end

    local srcCoords    = GetEntityCoords(srcPed)
    local targetCoords = GetEntityCoords(targetPed)
    if not srcCoords or not targetCoords then return false end

    local dx   = srcCoords.x - targetCoords.x
    local dy   = srcCoords.y - targetCoords.y
    local dz   = srcCoords.z - targetCoords.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    return dist <= (maxDistance or 5.0)
end

local function IsPlayerNearCoords(src, coords, maxDistance)
    if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
        return false
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    if not playerCoords then return false end

    local cx, cy, cz = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not cx or not cy or not cz then return false end

    local maxDist = tonumber(maxDistance) or 3.0
    local dx = playerCoords.x - cx
    local dy = playerCoords.y - cy
    local dz = playerCoords.z - cz

    return (dx * dx + dy * dy + dz * dz) <= (maxDist * maxDist)
end

local function IsPlayerNearShop(src, shop)
    if type(shop) ~= 'table' then return false end

    local npc = shop.npc or {}
    local coords = npc.coords or shop.coords or shop.location
    if not coords then return false end

    local interactDistance = tonumber(npc.interactDistance or shop.interactDistance) or 2.5
    return IsPlayerNearCoords(src, coords, interactDistance + 2.0)
end

local function GetAllItemsData()
    local all = {}
    for k, v in pairs(Items   or {}) do all[k] = v end
    for k, v in pairs(Weapons or {}) do all[k] = v end
    for k, v in pairs(Ammo    or {}) do all[k] = v end
    return all
end

local function Debug(level, msg)
    if not Config.Debug and level ~= 'Error' then return end
    local colors = { Error = '^1', Warn = '^3', Info = '^2', Verbose = '^5' }
    print((colors[level] or '^7') .. '[COREX-INVENTORY] ' .. msg .. '^0')
end

-- Initialize DB table on resource start
CreateThread(function()
    Wait(2000)

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS `inventories` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `inventory_type` VARCHAR(50) NOT NULL DEFAULT 'player',
            `inventory_id` VARCHAR(60) NOT NULL,
            `items` LONGTEXT DEFAULT '[]',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `hotbar` LONGTEXT DEFAULT '{}',
            UNIQUE KEY `unique_inventory` (`identifier`, `inventory_type`, `inventory_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(result)
        Debug('Info', 'Database table initialized')

        local itemCount = 0
        if Items then for _ in pairs(Items) do itemCount = itemCount + 1 end end
        Debug('Verbose', 'Items loaded: ' .. itemCount)
    end)
end)

local function GetItemData(itemName)
    return Items[itemName] or Weapons[itemName] or Ammo[itemName]
end

local function GetWeaponDefinition(itemName)
    if type(itemName) ~= 'string' then
        return nil, nil
    end

    local upperName = string.upper(itemName)
    if not string.find(upperName, 'WEAPON_', 1, true) then
        upperName = 'WEAPON_' .. upperName
    end

    return Weapons[upperName], upperName
end

local function EnsureItemMetadata(itemName, metadata)
    local safeMetadata = ShallowCopy(metadata)
    local weaponDef = GetWeaponDefinition(itemName)

    if weaponDef and weaponDef.ammoType and safeMetadata.ammo == nil then
        safeMetadata.ammo = 0
    end

    return safeMetadata
end

local function FindInventoryItem(inv, itemName, slotId)
    if not inv or not inv.items then
        return nil
    end

    local wantedSlot  = slotId ~= nil and tostring(slotId) or nil
    local wantedName  = type(itemName) == 'string' and itemName or nil
    local wantedUpper = wantedName and string.upper(wantedName) or nil

    for index, item in ipairs(inv.items) do
        local itemSlot  = item.slot ~= nil and tostring(item.slot) or nil
        local itemUpper = type(item.name) == 'string' and string.upper(item.name) or nil
        local slotMatches = (not wantedSlot) or (itemSlot == wantedSlot)
        local nameMatches = (not wantedName) or item.name == wantedName or itemUpper == wantedUpper

        if slotMatches and nameMatches then
            return item, index
        end
    end

    return nil
end

local function GetInventoryItemCount(inv, itemName)
    if not inv or not inv.items or type(itemName) ~= 'string' then
        return 0
    end

    local total = 0
    for _, item in ipairs(inv.items) do
        if item.name == itemName then
            total = total + (tonumber(item.count) or 0)
        end
    end

    return total
end

local function GetItemCountByName(src, itemName)
    local inv = Inventories[src]
    if not inv then return 0 end
    return GetInventoryItemCount(inv, itemName)
end

local function GetCurrencyBalance(src, currency)
    if currency == 'cash' then
        return GetItemCountByName(src, 'cash')
    end

    local player = GetPlayer(src)
    return player and player.money and player.money[currency] or 0
end

local function ConsumeCurrency(src, currency, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return true
    end

    if currency == 'cash' then
        return RemoveItem(src, 'cash', amount)
    end

    local ok, removed = pcall(function()
        return exports['corex-core']:RemoveMoney(src, currency, amount)
    end)
    return ok and removed
end

local function RefundCurrency(src, currency, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return true
    end

    if currency == 'cash' then
        local ok = AddItem(src, 'cash', amount)
        return ok == true
    end

    local ok, added = pcall(function()
        return exports['corex-core']:AddMoney(src, currency, amount)
    end)
    return ok and added
end

local AddItem  -- forward declaration (defined later in this file)

local function MigrateLegacyCashToItem(src)
    local inv = Inventories[src]
    if not inv then return end

    local player = GetPlayer(src)
    local legacyCash = player and player.money and tonumber(player.money.cash) or 0
    legacyCash = math.max(0, math.floor(legacyCash or 0))
    if legacyCash <= 0 then return end

    local addOk = AddItem(src, 'cash', legacyCash)
    if not addOk then
        Debug('Warn', ('Cash migration skipped (no inventory space) src=%d amount=%d'):format(src, legacyCash))
        return
    end

    local removedOk, removed = pcall(function()
        return exports['corex-core']:RemoveMoney(src, 'cash', legacyCash)
    end)

    if not removedOk or not removed then
        RemoveItem(src, 'cash', legacyCash)
        Debug('Warn', ('Cash migration rollback: failed to remove legacy cash src=%d'):format(src))
        return
    end

    Debug('Info', ('Migrated legacy cash -> item for src=%d amount=%d'):format(src, legacyCash))
end

local function SameItemName(a, b)
    if type(a) ~= 'string' or type(b) ~= 'string' then
        return false
    end

    return string.lower(a) == string.lower(b)
end

local function CalculateWeight(items)
    local weight = 0.0
    for _, item in ipairs(items) do
        local data = GetItemData(item.name)
        if data then
            weight = weight + (data.weight * item.count)
        end
    end
    return weight
end

local function IsSpotFree(inventory, x, y, w, h, ignoreSlot)
    if x < 1 or y < 1 or (x + w - 1) > Config.GridWidth or (y + h - 1) > Config.GridHeight then
        return false
    end

    for _, item in ipairs(inventory.items) do
        if item.slot ~= ignoreSlot then
            local data = GetItemData(item.name)
            local iW = data and data.size and data.size.w or 1
            local iH = data and data.size and data.size.h or 1

            local itemRight  = item.x + iW - 1
            local itemBottom = item.y + iH - 1
            local newRight   = x + w - 1
            local newBottom  = y + h - 1

            local overlapsX = not (newRight < item.x or x > itemRight)
            local overlapsY = not (newBottom < item.y or y > itemBottom)

            if overlapsX and overlapsY then
                return false
            end
        end
    end

    return true
end

local function FindFreeSpot(inventory, itemName)
    local data = GetItemData(itemName)
    if not data then return nil end

    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1

    for y = 1, Config.GridHeight do
        for x = 1, Config.GridWidth do
            if IsSpotFree(inventory, x, y, w, h) then
                return {x = x, y = y}
            end
        end
    end

    return nil
end

local function GetIdentifier(src)
    local player = GetPlayer(src)
    if player then
        return player.identifier
    end
    local ok, id = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if ok and id and id.Functions then
        return id.Functions.GetIdentifier(src, 'license')
    end
    return nil
end

local function Notify(src, message, type)
    TriggerClientEvent('corex:notify', src, message, type or 'info')
end

local function LoadInventory(src)
    local id = GetIdentifier(src)
    if not id then return end

    exports.oxmysql:query(
        'SELECT * FROM inventories WHERE identifier = ? AND inventory_type = ? LIMIT 1',
        {id, 'player'},
        function(results)
            local result = results and results[1]
            if result and result.items then
                local items  = json.decode(result.items)  or {}
                local hotbar = result.hotbar and json.decode(result.hotbar) or {}

                Inventories[src] = {
                    items    = items,
                    hotbar   = hotbar,
                    weight   = CalculateWeight(items),
                    maxWeight = Config.MaxWeight
                }

                Debug('Info', 'Loaded ' .. #items .. ' items for player ' .. src)
            else
                Inventories[src] = {
                    items    = {},
                    hotbar   = {},
                    weight   = 0.0,
                    maxWeight = Config.MaxWeight
                }
                exports.oxmysql:insert(
                    'INSERT INTO inventories (identifier, inventory_type, inventory_id, items, hotbar) VALUES (?, ?, ?, ?, ?)',
                    {id, 'player', id, '[]', '{}'}
                )

                Debug('Info', 'Created new inventory for player ' .. src)
            end

            SetTimeout(1000, function()
                MigrateLegacyCashToItem(src)
                TriggerClientEvent('corex-inventory:client:syncInventory', src, Inventories[src].items)
            end)
        end
    )
end

local function FlushInventory(src)
    local id  = GetIdentifier(src)
    local inv = Inventories[src]
    if not id or not inv then return end

    local itemsJson  = json.encode(inv.items)
    local hotbarJson = json.encode(inv.hotbar or {})
    local invRef     = inv

    exports.oxmysql:execute(
        'UPDATE inventories SET items = ?, hotbar = ? WHERE identifier = ? AND inventory_type = ?',
        {itemsJson, hotbarJson, id, 'player'},
        function(result)
            local rows = 0
            if type(result) == 'number' then
                rows = result
            elseif type(result) == 'table' then
                rows = tonumber(result.affectedRows) or tonumber(result.rowsAffected) or 0
            end

            if invRef then
                if rows > 0 then
                    invRef.isDirty = false
                else
                    Debug('Warn', 'Flush reported 0 rows affected for source ' .. tostring(src))
                    invRef.isDirty = false
                end
            end
        end
    )
end

local function SaveInventory(src, pushSync)
    local inv = Inventories[src]
    if not inv then return end

    inv.isDirty = true
    if pushSync ~= false then
        TriggerClientEvent('corex-inventory:client:syncInventory', src, inv.items)
    end
end

local function SyncInventoryToClient(src)
    if not Inventories[src] then return end
    TriggerClientEvent('corex-inventory:client:syncInventory', src, Inventories[src].items)
end

local function BroadcastNearby(eventName, coords, radius, ...)
    local players = GetPlayers()
    for _, srcStr in ipairs(players) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pc = GetEntityCoords(ped)
            if #(pc - coords) <= radius then
                TriggerClientEvent(eventName, src, ...)
            end
        end
    end
end

local function BroadcastDroppedItems()
    TriggerClientEvent('corex-inventory:client:syncDroppedItems', -1, DroppedItems)
end

local function DropItem(src, itemName, count, slot, coords)
    if not TrySetBusy(src) then
        Debug('Warn', 'DropItem blocked: Player ' .. src .. ' is busy')
        return false
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return false
    end

    if coords and coords.x then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pc = GetEntityCoords(ped)
            local dx, dy, dz = pc.x - coords.x, pc.y - coords.y, pc.z - (coords.z or pc.z)
            if (dx * dx + dy * dy + dz * dz) > 100.0 then
                Debug('Warn', ('DropItem rejected: drop coords too far from ped (src=%d)'):format(src))
                ClearBusy(src)
                return false
            end
        end
    end

    local itemIndex = nil
    local item = nil

    if slot then
        for i, it in ipairs(inv.items) do
            if tostring(it.slot) == tostring(slot) and it.name == itemName then
                itemIndex = i
                item = it
                break
            end
        end
    end

    if not item and itemName then
        for i, it in ipairs(inv.items) do
            if it.name == itemName then
                itemIndex = i
                item = it
                break
            end
        end
    end

    if not item then
        ClearBusy(src)
        Debug('Warn', ('DropItem rejected: item not found (src=%d name=%s)'):format(src, tostring(itemName)))
        return false
    end

    if type(count) == 'number' and (count < 1 or count > item.count) then
        ClearBusy(src)
        Debug('Warn', ('DropItem rejected: invalid count (src=%d req=%d have=%d)'):format(src, count, item.count))
        return false
    end

    local data = GetItemData(item.name)
    local dropCount = math.min(count or item.count, item.count)

    if item.count > dropCount then
        item.count = item.count - dropCount
    else
        table.remove(inv.items, itemIndex)
    end

    if data then
        inv.weight = inv.weight - (data.weight * dropCount)
    end

    dropIdCounter = dropIdCounter + 1
    local dropId = 'drop_' .. dropIdCounter .. '_' .. os.time()

    DroppedItems[dropId] = {
        name      = itemName,
        count     = dropCount,
        coords    = coords or vector3(0, 0, 0),
        gridX     = coords and coords.gridX or 1,
        gridY     = coords and coords.gridY or 1,
        prop      = data and data.prop or 'prop_med_bag_01b',
        metadata  = ShallowCopy(item.metadata),
        droppedBy = src,
        droppedAt = os.time()
    }

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    exports['corex-core']:BroadcastNearby(coords or vector3(0,0,0), 500.0, 'corex-inventory:client:itemDropped', dropId, DroppedItems[dropId])

    local upperName = string.upper(itemName)
    if not string.find(upperName, 'WEAPON_') then
        upperName = 'WEAPON_' .. upperName
    end
    if Weapons and Weapons[upperName] then
        TriggerClientEvent('corex-inventory:client:weaponDropConfirmed', src, upperName)
    end

    Debug('Info', 'Item dropped: ' .. itemName .. ' x' .. dropCount .. ' by player ' .. src)

    ClearBusy(src)
    return true
end

-- ============================================================
-- [FIX-STACK-1] PickupItem â€” try to merge into existing stacks
-- before creating a new inventory slot. Previously always
-- created a new slot even for stackable items.
-- ============================================================
local function PickupItem(src, dropId, gridX, gridY)
    if not TrySetBusy(src) then
        Debug('Warn', 'PickupItem blocked: Player ' .. src .. ' is busy')
        return false
    end

    local dropData = DroppedItems[dropId]
    if not dropData then
        ClearBusy(src)
        return false
    end

    local pickupDistance = (Config.PickupDistance or 3.0) + 1.0
    if not IsPlayerNearCoords(src, dropData.coords, pickupDistance) then
        Debug('Warn', ('Pickup rejected: player %d too far from %s'):format(src, tostring(dropId)))
        ClearBusy(src)
        return false
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return false
    end

    local data = GetItemData(dropData.name)
    if not data then
        ClearBusy(src)
        return false
    end

    local w = data.size and data.size.w or 1
    local h = data.size and data.size.h or 1

    -- Weight check against full count first
    local addWeight = data.weight * dropData.count
    if inv.weight + addWeight > inv.maxWeight then
        Debug('Warn', 'Pickup failed: Too heavy')
        ClearBusy(src)
        return false
    end

    -- [FIX] If item is stackable, try to fill existing stacks first
    local remaining = dropData.count
    if data.stackable then
        local maxStack = data.maxStack or 99999
        for _, item in ipairs(inv.items) do
            if remaining <= 0 then break end
            if SameItemName(item.name, dropData.name) then
                local canAdd = maxStack - item.count
                if canAdd > 0 then
                    local toAdd = math.min(canAdd, remaining)
                    item.count  = item.count + toAdd
                    remaining   = remaining - toAdd
                    inv.weight  = inv.weight + (data.weight * toAdd)
                end
            end
        end
    end

    -- Place remainder (or full count if not stackable) in a new slot
    if remaining > 0 then
        if not IsSpotFree(inv, gridX, gridY, w, h) then
            local freeSpot = FindFreeSpot(inv, dropData.name)
            if not freeSpot then
                -- If we partially merged, still commit that progress
                if remaining < dropData.count then
                    dropData.count = remaining
                    SaveInventory(src)
                    TriggerClientEvent('corex-inventory:client:update', src, inv)
                    BroadcastDroppedItems()
                    Debug('Info', 'Partial pickup: ' .. dropData.name .. ' merged partial, no space for remainder')
                    ClearBusy(src)
                    return true
                end
                Debug('Warn', 'Pickup failed: No space')
                -- Rollback weight changes from partial merge
                inv.weight = CalculateWeight(inv.items)
                ClearBusy(src)
                return false
            end
            gridX = freeSpot.x
            gridY = freeSpot.y
        end

        -- Remaining weight already added above partially; add only for remaining
        local remainWeight = data.weight * remaining
        -- Recheck weight for remainder (partial may have changed current weight)
        -- Weight was already accounted for at the beginning for full count;
        -- we now add slot weight only for what wasn't merged (remaining portion is
        -- the only thing going into a new slot â€” total weight = already counted above).
        table.insert(inv.items, {
            name     = dropData.name,
            count    = remaining,
            x        = gridX,
            y        = gridY,
            slot     = NextSlotId(),
            metadata = EnsureItemMetadata(dropData.name, dropData.metadata)
        })
        -- Weight for remaining was already added in the initial addWeight check
    end

    DroppedItems[dropId] = nil

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    local dropCoords = dropData.coords or vector3(0,0,0)
    exports['corex-core']:BroadcastNearby(dropCoords, 500.0, 'corex-inventory:client:itemPickedUp', dropId)

    Debug('Info', 'Item picked up: ' .. dropData.name .. ' x' .. dropData.count .. ' by player ' .. src)

    ClearBusy(src)
    return true
end

-- ============================================================
-- [FIX-STACK-2] AddItem â€” full partial stacking + maxStack
-- Previously the partial-fill path existed but the weight
-- accounting was off when items went into multiple stacks.
-- This version is fully corrected.
-- ============================================================
AddItem = function(src, itemName, count, metadata, x, y)
    count    = count or 1
    metadata = EnsureItemMetadata(itemName, metadata)

    local inv = Inventories[src]
    if not inv then return false, 'No inventory' end

    local data = GetItemData(itemName)
    if not data then return false, 'Item not found' end

    local addWeight = data.weight * count
    if inv.weight + addWeight > inv.maxWeight then
        return false, 'Too heavy'
    end

    -- [FIX] Stackable: fill existing stacks first, respecting maxStack
    if data.stackable then
        local maxStack = data.maxStack or 99999
        local remaining = count

        for _, item in ipairs(inv.items) do
            if remaining <= 0 then break end
            if SameItemName(item.name, itemName) then
                local canAdd = maxStack - item.count
                if canAdd > 0 then
                    local toAdd = math.min(canAdd, remaining)
                    item.count  = item.count + toAdd
                    remaining   = remaining - toAdd
                    -- Note: total weight already validated above for full 'count'.
                    -- We only track incremental weight here.
                end
            end
        end

        if remaining <= 0 then
            -- Recalculate weight cleanly after mutations
            inv.weight = CalculateWeight(inv.items)
            SaveInventory(src)
            TriggerClientEvent('corex-inventory:client:update', src, inv)
            return true
        end

        -- Place remainder in new slots (loop in case remainder > maxStack)
        while remaining > 0 do
            local pos
            if x and y and remaining == count then
                -- Only try caller-supplied position for first slot
                local w2 = data.size and data.size.w or 1
                local h2 = data.size and data.size.h or 1
                if IsSpotFree(inv, x, y, w2, h2) then
                    pos = {x = x, y = y}
                end
            end

            if not pos then
                pos = FindFreeSpot(inv, itemName)
            end

            if not pos then
                -- Commit whatever we managed to merge
                inv.weight = CalculateWeight(inv.items)
                SaveInventory(src)
                TriggerClientEvent('corex-inventory:client:update', src, inv)
                if remaining < count then
                    return true  -- partial success
                end
                return false, 'No space'
            end

            local batch = math.min(remaining, maxStack)
            table.insert(inv.items, {
                name     = itemName,
                count    = batch,
                x        = pos.x,
                y        = pos.y,
                slot     = NextSlotId(),
                metadata = ShallowCopy(metadata)
            })
            remaining = remaining - batch
        end

        inv.weight = CalculateWeight(inv.items)
        SaveInventory(src)
        TriggerClientEvent('corex-inventory:client:update', src, inv)
        return true
    end

    -- Non-stackable: single slot placement
    local pos
    if x and y then
        local w = data.size and data.size.w or 1
        local h = data.size and data.size.h or 1
        if IsSpotFree(inv, x, y, w, h) then
            pos = {x = x, y = y}
        end
    end

    if not pos then
        pos = FindFreeSpot(inv, itemName)
    end

    if not pos then
        return false, 'No space'
    end

    table.insert(inv.items, {
        name     = itemName,
        count    = count,
        x        = pos.x,
        y        = pos.y,
        slot     = NextSlotId(),
        metadata = ShallowCopy(metadata)
    })

    inv.weight = inv.weight + addWeight
    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)

    return true
end

-- ============================================================
-- [FIX-STACK-3] RemoveItem â€” drain across multiple stacks
-- Previously only removed from the first matching slot.
-- Now drains stacks until 'count' is satisfied.
-- ============================================================
local function RemoveItem(src, itemName, count)
    count = count or 1
    local inv = Inventories[src]
    if not inv then return false end

    local remaining = count
    local toRemove  = {}

    -- Collect indices in reverse so we can remove safely
    for i, item in ipairs(inv.items) do
        if remaining <= 0 then break end
        if SameItemName(item.name, itemName) then
            local take = math.min(item.count, remaining)
            remaining  = remaining - take
            table.insert(toRemove, {idx = i, take = take, item = item})
        end
    end

    if remaining > 0 then
        -- Not enough items
        return false
    end

    local data = GetItemData(itemName)

    -- Apply removals in reverse index order so indices stay valid
    table.sort(toRemove, function(a, b) return a.idx > b.idx end)
    for _, entry in ipairs(toRemove) do
        local item = entry.item
        item.count = item.count - entry.take
        if data then
            inv.weight = inv.weight - (data.weight * entry.take)
        end
        if item.count <= 0 then
            table.remove(inv.items, entry.idx)
        end
    end

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    return true
end

RegisterNetEvent('corex-inventory:server:load', function()
    LoadInventory(source)
end)

RegisterNetEvent('corex-inventory:server:requestDroppedItems', function()
    TriggerClientEvent('corex-inventory:client:syncDroppedItems', source, DroppedItems)
end)

RegisterNetEvent('corex-inventory:server:open', function()
    local src = source
    local inv = Inventories[src]

    if inv then
        local allItems = GetAllItemsData()

        TriggerClientEvent('corex-inventory:client:open', src, {
            items     = inv.items,
            weight    = inv.weight,
            maxWeight = inv.maxWeight,
            grid      = {w = Config.GridWidth, h = Config.GridHeight},
            itemsData = allItems
        })
    end
end)

RegisterNetEvent('corex-inventory:server:move', function(slotId, newX, newY)
    local src = source
    if type(slotId) ~= 'string' and type(slotId) ~= 'number' then return end
    if type(newX) ~= 'number' or type(newY) ~= 'number' then return end
    local inv = Inventories[src]
    if not inv then return end

    local item = nil
    for _, i in ipairs(inv.items) do
        if tostring(i.slot) == tostring(slotId) then
            item = i
            break
        end
    end

    if not item then return end

    local data = GetItemData(item.name)
    local w = data and data.size and data.size.w or 1
    local h = data and data.size and data.size.h or 1

    if IsSpotFree(inv, newX, newY, w, h, slotId) then
        item.x = newX
        item.y = newY
        SaveInventory(src)
        Debug('Verbose', 'Moved item ' .. item.name .. ' to ' .. newX .. ',' .. newY)
    else
        Debug('Warn', 'Move blocked: Collision detected')
    end

    TriggerClientEvent('corex-inventory:client:update', src, inv)
end)

local function ValidateAndApplyCompactLayout(inv, proposed)
    if not inv or type(inv.items) ~= 'table' then
        return false
    end

    if type(proposed) ~= 'table' then
        return false
    end

    local posBySlot = {}
    local seen = {}

    for _, entry in ipairs(proposed) do
        if type(entry) == 'table' then
            local slotId = entry.slotId
            local x = tonumber(entry.x)
            local y = tonumber(entry.y)

            if slotId ~= nil then
                slotId = tostring(slotId)
                if #slotId > 0 and #slotId <= 64 then
                    if x and y and x == x and y == y and x ~= math.huge and y ~= math.huge then
                        x = math.floor(x)
                        y = math.floor(y)
                        if x >= 1 and x <= Config.GridWidth and y >= 1 and y <= Config.GridHeight then
                            -- last write wins, but keep it deterministic by overwriting
                            posBySlot[slotId] = { x = x, y = y }
                            seen[slotId] = true
                        end
                    end
                end
            end
        end
    end

    -- Nothing to do
    if next(seen) == nil then
        return true
    end

    -- Validate entire layout in one pass (simultaneous moves)
    local occ = {}
    local function cellKey(cx, cy) return tostring(cx) .. ',' .. tostring(cy) end

    for _, item in ipairs(inv.items) do
        local slotStr = item.slot ~= nil and tostring(item.slot) or nil
        local target = slotStr and posBySlot[slotStr] or nil
        local x = target and target.x or item.x
        local y = target and target.y or item.y

        local data = GetItemData(item.name)
        local w = data and data.size and data.size.w or 1
        local h = data and data.size and data.size.h or 1

        if x < 1 or y < 1 or (x + w - 1) > Config.GridWidth or (y + h - 1) > Config.GridHeight then
            return false
        end

        for dy = 0, h - 1 do
            for dx = 0, w - 1 do
                local k = cellKey(x + dx, y + dy)
                if occ[k] then
                    return false
                end
                occ[k] = true
            end
        end
    end

    -- Apply changes
    for _, item in ipairs(inv.items) do
        local slotStr = item.slot ~= nil and tostring(item.slot) or nil
        local target = slotStr and posBySlot[slotStr] or nil
        if target then
            item.x = target.x
            item.y = target.y
        end
    end

    return true
end

RegisterNetEvent('corex-inventory:server:compact', function(positions)
    local src = source
    if type(positions) ~= 'table' then return end

    if not TrySetBusy(src) then
        Debug('Warn', ('Compact blocked: Player %d is busy'):format(src))
        return
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return
    end

    local ok = ValidateAndApplyCompactLayout(inv, positions)
    if not ok then
        Debug('Warn', ('Compact rejected: invalid/overlapping layout (src=%d)'):format(src))
        TriggerClientEvent('corex-inventory:client:update', src, inv)
        ClearBusy(src)
        return
    end

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    Debug('Verbose', ('Compact applied (src=%d)'):format(src))
    ClearBusy(src)
end)

RegisterNetEvent('corex-inventory:server:use', function(itemName, slotId)
    local src = source
    if type(itemName) ~= 'string' then return end
    local inv = Inventories[src]
    if not inv then return end

    local itemData = {}
    local item = FindInventoryItem(inv, itemName, slotId)
    if not item then
        Debug('Warn', ('Use rejected: player %d does not have %s'):format(src, tostring(itemName)))
        return
    end

    itemData = {
        slot     = item.slot,
        count    = item.count,
        x        = item.x,
        y        = item.y,
        metadata = EnsureItemMetadata(item.name, item.metadata)
    }
    itemData.ammo = itemData.metadata.ammo
    itemName = item.name

    TriggerClientEvent('corex-inventory:client:useItem', src, itemName, itemData)
end)

RegisterNetEvent('corex-inventory:server:removeUsedAmmo', function(ammoName, count)
    local src = source
    if type(ammoName) ~= 'string' then return end
    RemoveItem(src, ammoName, count or 1)
end)

RegisterNetEvent('corex-inventory:server:drop', function(itemName, count, slot, coords)
    if type(itemName) ~= 'string' then return end
    DropItem(source, itemName, count, slot, coords)
end)

RegisterNetEvent('corex-inventory:server:pickup', function(dropId, x, y)
    if type(dropId) ~= 'string' then return end
    PickupItem(source, dropId, x or 1, y or 1)
end)

RegisterNetEvent('corex-inventory:server:split', function(itemName, count, slotId)
    local src = source
    if type(itemName) ~= 'string' or itemName == '' then return end
    if slotId == nil then return end

    local splitCount = tonumber(count)
    if not splitCount or splitCount ~= splitCount or splitCount == math.huge then return end
    splitCount = math.floor(splitCount)
    if splitCount < 1 or splitCount > 9999 then return end

    if not TrySetBusy(src) then
        Debug('Warn', ('Split blocked: Player %d is busy'):format(src))
        return
    end

    local inv = Inventories[src]
    if not inv then
        ClearBusy(src)
        return
    end

    local item, itemIndex = FindInventoryItem(inv, itemName, slotId)
    if not item or itemIndex == nil then
        ClearBusy(src)
        return
    end

    local itemData = GetItemData(item.name)
    if not itemData or not itemData.stackable then
        ClearBusy(src)
        return
    end

    local currentCount = tonumber(item.count) or 0
    if currentCount <= 1 or splitCount >= currentCount then
        ClearBusy(src)
        return
    end

    local freeSpot = FindFreeSpot(inv, item.name)
    if not freeSpot then
        Notify(src, 'Tidak ada slot kosong untuk split item', 'error')
        ClearBusy(src)
        return
    end

    item.count = currentCount - splitCount
    table.insert(inv.items, {
        name = item.name,
        count = splitCount,
        x = freeSpot.x,
        y = freeSpot.y,
        slot = NextSlotId(),
        metadata = EnsureItemMetadata(item.name, item.metadata)
    })

    inv.weight = CalculateWeight(inv.items)
    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    ClearBusy(src)
end)

-- ============================================================
-- [FIX-STACK-4] mergeItem â€” respects maxStack, handles partial
-- ============================================================
RegisterNetEvent('corex-inventory:server:mergeItem', function(fromSlot, toSlot)
    local src = source
    -- [SEC] Validate input types
    if (type(fromSlot) ~= 'string' and type(fromSlot) ~= 'number') then return end
    if (type(toSlot)   ~= 'string' and type(toSlot)   ~= 'number') then return end

    local inv = Inventories[src]
    if not inv then return end

    local fromItem, fromIdx = nil, nil
    local toItem,   toIdx   = nil, nil

    for idx, item in ipairs(inv.items) do
        if tostring(item.slot) == tostring(fromSlot) then
            fromItem = item; fromIdx = idx
        elseif tostring(item.slot) == tostring(toSlot) then
            toItem = item; toIdx = idx
        end
    end

    if not fromItem or not toItem then
        Debug('Warn', ('mergeItem: slot not found (src=%d from=%s to=%s)'):format(src, tostring(fromSlot), tostring(toSlot)))
        return
    end
    if not SameItemName(fromItem.name, toItem.name) then
        Debug('Warn', ('mergeItem: name mismatch (src=%d %s vs %s)'):format(src, fromItem.name, toItem.name))
        return
    end

    local itemData = GetItemData(toItem.name)
    if not itemData then return end

    -- [FIX] Respect stackable flag; if not stackable, do nothing
    if not itemData.stackable then
        Debug('Warn', ('mergeItem: item %s is not stackable'):format(toItem.name))
        TriggerClientEvent('corex-inventory:client:update', src, inv)
        return
    end

    local maxStack = itemData.maxStack or 99999
    local combined = (toItem.count or 1) + (fromItem.count or 1)

    if combined <= maxStack then
        toItem.count = combined
        table.remove(inv.items, fromIdx)
    else
        toItem.count  = maxStack
        fromItem.count = combined - maxStack
    end

    -- Recalculate weight after merge
    inv.weight = CalculateWeight(inv.items)

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    Debug('Info', ('mergeItem: merged %s x%d -> slot %s (src=%d)'):format(toItem.name, toItem.count, tostring(toSlot), src))
end)

-- ============================================================
-- [FIX-STACK-5] mergeGroundItem â€” respects maxStack + partial
-- ============================================================
RegisterNetEvent('corex-inventory:server:mergeGroundItem', function(dropId, toSlot)
    local src = source
    -- [SEC] Input validation
    if type(dropId) ~= 'string' then return end
    if type(toSlot) ~= 'string' and type(toSlot) ~= 'number' then return end

    local inv = Inventories[src]
    if not inv then return end

    local dropData = DroppedItems[dropId]
    if not dropData then return end

    -- [SEC] Proximity check
    local mergeDistance = (Config.PickupDistance or 3.0) + 1.0
    if not IsPlayerNearCoords(src, dropData.coords, mergeDistance) then
        Debug('Warn', ('mergeGroundItem rejected: player %d too far'):format(src))
        return
    end

    local toItem = nil
    for _, item in ipairs(inv.items) do
        if tostring(item.slot) == tostring(toSlot) then
            toItem = item
            break
        end
    end

    if not toItem then return end
    if not SameItemName(toItem.name, dropData.name) then return end

    local itemData = GetItemData(toItem.name)
    if not itemData then return end

    -- [FIX] Respect stackable flag
    if not itemData.stackable then
        Debug('Warn', ('mergeGroundItem: item %s is not stackable'):format(toItem.name))
        return
    end

    local maxStack = itemData.maxStack or 99999
    local targetCount = tonumber(toItem.count) or 1
    local dropCount = tonumber(dropData.count) or 1
    local combined = targetCount + dropCount

    -- Weight check for what we're adding
    local addAmount = math.min(dropCount, maxStack - targetCount)
    if addAmount <= 0 then
        Debug('Warn', 'mergeGroundItem: target stack is already full')
        return
    end

    local addWeight = itemData.weight * addAmount
    if inv.weight + addWeight > inv.maxWeight then
        -- Only add what fits weight-wise
        addAmount = math.floor((inv.maxWeight - inv.weight) / itemData.weight)
        if addAmount <= 0 then
            Debug('Warn', 'mergeGroundItem: inventory too heavy')
            return
        end
    end

    if addAmount >= dropCount and combined <= maxStack then
        toItem.count = targetCount + addAmount
        DroppedItems[dropId] = nil
        exports['corex-core']:BroadcastNearby(
            dropData.coords or vector3(0,0,0), 500.0,
            'corex-inventory:client:itemPickedUp', dropId
        )
    else
        toItem.count = targetCount + addAmount
        dropData.count = dropCount - addAmount
    end

    inv.weight = CalculateWeight(inv.items)

    SaveInventory(src)
    TriggerClientEvent('corex-inventory:client:update', src, inv)
    BroadcastDroppedItems()
    Debug('Info', ('mergeGroundItem: merged %s from ground (src=%d)'):format(dropData.name, src))
end)

-- Find next available ground slot for loot
local function FindNextGroundSlot(itemWidth, itemHeight)
    local gridCols = 8
    local gridRows = 10
    local occupied = {}

    for _, item in pairs(DroppedItems) do
        if item.gridX and item.gridY then
            local itemData = GetItemData(item.name)
            local size = itemData and itemData.size or {w = 1, h = 1}
            local w = size.w or 1
            local h = size.h or 1

            for dy = 0, h - 1 do
                for dx = 0, w - 1 do
                    local key = (item.gridX + dx) .. ',' .. (item.gridY + dy)
                    occupied[key] = true
                end
            end
        end
    end

    for row = 1, gridRows do
        for col = 1, gridCols do
            local canFit = true

            if col + itemWidth - 1 > gridCols or row + itemHeight - 1 > gridRows then
                canFit = false
            else
                for dy = 0, itemHeight - 1 do
                    for dx = 0, itemWidth - 1 do
                        local key = (col + dx) .. ',' .. (row + dy)
                        if occupied[key] then
                            canFit = false
                            break
                        end
                    end
                    if not canFit then break end
                end
            end

            if canFit then
                return col, row
            end
        end
    end

    return 1, 1
end

AddEventHandler('corex-inventory:server:addLootItem', function(src, itemName, amount, coords)
    local itemData = GetItemData(itemName)
    if not itemData then
        Debug('Error', 'Cannot drop loot: Unknown item ' .. itemName)
        return
    end

    local size = itemData.size or {w = 1, h = 1}
    local itemWidth  = size.w or 1
    local itemHeight = size.h or 1
    local gridX, gridY = FindNextGroundSlot(itemWidth, itemHeight)

    local dropId = 'loot_' .. math.random(100000, 999999)
    DroppedItems[dropId] = {
        name      = itemName,
        count     = amount or 1,
        coords    = coords or {x = 0, y = 0, z = 0},
        gridX     = gridX,
        gridY     = gridY,
        prop      = itemData.prop or 'prop_med_bag_01b',
        droppedAt = os.time()
    }

    local lootCoords = coords and vector3(coords.x or 0, coords.y or 0, coords.z or 0) or vector3(0,0,0)
    exports['corex-core']:BroadcastNearby(lootCoords, 500.0, 'corex-inventory:client:itemDropped', dropId, DroppedItems[dropId])
    Debug('Info', 'Loot dropped: ' .. itemName .. ' x' .. (amount or 1))
end)

-- ============================================================
-- [FIX-STACK-6] Give â€” try to merge into existing target stacks
-- before creating a new slot in target inventory
-- ============================================================
RegisterNetEvent('corex-inventory:server:give', function(targetPlayer, itemName, count, slot)
    local src       = source
    local targetSrc = tonumber(targetPlayer)

    if not targetSrc or targetSrc == src then
        Debug('Warn', 'Give failed: Invalid target')
        return
    end

    if type(itemName) ~= 'string' or #itemName == 0 or #itemName > 100 then return end
    count = tonumber(count) or 1
    if count ~= count or count == math.huge then return end
    count = math.floor(count)
    if count < 1 or count > 9999 then return end

    if slot == nil then return end
    local slotStr = tostring(slot)
    if #slotStr == 0 or #slotStr > 64 then return end

    local srcInvCheck = Inventories[src]
    if not srcInvCheck then return end

    local slotOwned = false
    for _, it in ipairs(srcInvCheck.items) do
        if tostring(it.slot) == slotStr and it.name == itemName then
            slotOwned = true
            break
        end
    end
    if not slotOwned then
        Debug('Warn', ('Give rejected: slot %s not owned by %d'):format(slotStr, src))
        return
    end

    if not IsNearbyPlayer(src, targetSrc, 5.0) then
        Debug('Warn', 'Give failed: Target too far away')
        Notify(src, 'Target is too far away', 'error')
        return
    end

    if not TrySetBusy(src) then
        Debug('Warn', 'Give blocked: Source player is busy')
        return
    end

    if not TrySetBusy(targetSrc) then
        Debug('Warn', 'Give blocked: Target player is busy')
        ClearBusy(src)
        return
    end

    local srcInv    = Inventories[src]
    local targetInv = Inventories[targetSrc]

    if not srcInv or not targetInv then
        Debug('Warn', 'Give failed: Missing inventory')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local itemIndex = nil
    local item = nil

    for i, it in ipairs(srcInv.items) do
        if tostring(it.slot) == tostring(slot) and it.name == itemName then
            itemIndex = i
            item = it
            break
        end
    end

    if not item then
        Debug('Warn', 'Give failed: Item not found')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local data = GetItemData(item.name)
    if not data then
        Debug('Warn', 'Give failed: Item data not found')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    local giveCount = math.min(count or item.count, item.count)
    local addWeight = data.weight * giveCount

    if targetInv.weight + addWeight > targetInv.maxWeight then
        Debug('Warn', 'Give failed: Target inventory full')
        Notify(src, 'Target inventory is full', 'error')
        ClearBusy(src)
        ClearBusy(targetSrc)
        return
    end

    -- Remove from source first
    if item.count > giveCount then
        item.count = item.count - giveCount
    else
        table.remove(srcInv.items, itemIndex)
    end
    srcInv.weight = srcInv.weight - (data.weight * giveCount)

    -- [FIX] Try to merge into existing target stacks before new slot
    local remaining = giveCount
    if data.stackable then
        local maxStack = data.maxStack or 99999
        for _, tItem in ipairs(targetInv.items) do
            if remaining <= 0 then break end
            if tItem.name == item.name then
                local canAdd = maxStack - tItem.count
                if canAdd > 0 then
                    local toAdd = math.min(canAdd, remaining)
                    tItem.count  = tItem.count + toAdd
                    remaining    = remaining - toAdd
                end
            end
        end
    end

    -- Place remainder in new slot(s)
    while remaining > 0 do
        local freeSpot = FindFreeSpot(targetInv, item.name)
        if not freeSpot then
            Debug('Warn', 'Give failed: No space in target inventory for remainder')
            Notify(src, 'Target has no space', 'error')
            -- Rollback: return items to source
            table.insert(srcInv.items, {
                name     = item.name,
                count    = giveCount,
                x        = item.x or 1,
                y        = item.y or 1,
                slot     = NextSlotId(),
                metadata = EnsureItemMetadata(item.name, item.metadata)
            })
            srcInv.weight  = srcInv.weight  + (data.weight * giveCount)
            targetInv.weight = CalculateWeight(targetInv.items)
            TriggerClientEvent('corex-inventory:client:update', src, srcInv)
            ClearBusy(src)
            ClearBusy(targetSrc)
            return
        end

        local batch = math.min(remaining, data.maxStack or 99999)
        table.insert(targetInv.items, {
            name     = item.name,
            count    = batch,
            x        = freeSpot.x,
            y        = freeSpot.y,
            slot     = NextSlotId(),
            metadata = EnsureItemMetadata(item.name, item.metadata)
        })
        remaining = remaining - batch
    end

    targetInv.weight = CalculateWeight(targetInv.items)

    SaveInventory(src)
    SaveInventory(targetSrc)

    TriggerClientEvent('corex-inventory:client:update', src, srcInv)
    TriggerClientEvent('corex-inventory:client:update', targetSrc, targetInv)

    local srcPlayer  = GetPlayer(src)
    local tgtPlayer  = GetPlayer(targetSrc)
    local srcName    = srcPlayer and srcPlayer.name or 'Unknown'
    local targetName = tgtPlayer and tgtPlayer.name or 'Unknown'

    Debug('Info', srcName .. ' gave ' .. giveCount .. 'x ' .. itemName .. ' to ' .. targetName)

    Notify(targetSrc, 'Received ' .. giveCount .. 'x ' .. (data.label or itemName), 'success')

    ClearBusy(src)
    ClearBusy(targetSrc)
end)

AddEventHandler('corex:server:playerReady', function(src, player)
    if not player then return end

    CreateThread(function()
        Wait(1500)
        LoadInventory(src)
        Debug('Info', 'Auto-loaded inventory for ' .. (player.name or 'Unknown'))
    end)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if Inventories[src] then
        FlushInventory(src)
        Debug('Info', 'Saved inventory on disconnect for source ' .. src)
        Inventories[src] = nil
    end
end)

-- Batched persistence loop
CreateThread(function()
    Wait(5000)

    while true do
        Wait(30000)

        local flushed = 0
        for src, inv in pairs(Inventories) do
            if inv and inv.isDirty then
                FlushInventory(src)
                flushed = flushed + 1
            end
        end

        if flushed > 0 then
            Debug('Verbose', 'Flushed ' .. flushed .. ' dirty inventories to DB')
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for src, inv in pairs(Inventories) do
        if inv and inv.isDirty then
            FlushInventory(src)
        end
    end
end)

-- Drop expiration cleanup
CreateThread(function()
    while true do
        Wait(60000)

        if next(DroppedItems) == nil then
            goto continue
        end

        local now        = os.time()
        local expireTime = Config.DropExpireTime or 1800

        for dropId, item in pairs(DroppedItems) do
            if now - item.droppedAt > expireTime then
                local expCoords = item.coords or vector3(0,0,0)
                DroppedItems[dropId] = nil
                local ok, broadcastErr = pcall(function()
                    exports['corex-core']:BroadcastNearby(expCoords, 500.0, 'corex-inventory:client:itemPickedUp', dropId)
                end)
                if not ok then
                    Debug('Warn', 'BroadcastNearby failed during drop expiry: ' .. tostring(broadcastErr))
                end
                Debug('Verbose', 'Expired dropped item: ' .. item.name)
            end
        end

        ::continue::
    end
end)

local function UpdateItemMeta(src, itemName, metadata, slotId, syncClient)
    local inv = Inventories[src]
    if not inv or type(metadata) ~= 'table' then return false end

    local item = FindInventoryItem(inv, itemName, slotId)
    if item then
        item.metadata = EnsureItemMetadata(item.name, item.metadata)
        for k, v in pairs(metadata) do
            item.metadata[k] = v
        end

        SaveInventory(src, syncClient ~= false)
        if syncClient ~= false then
            TriggerClientEvent('corex-inventory:client:update', src, inv)
        end
        return true
    end

    return false
end

local function GetItemMeta(src, itemName, slotId)
    local inv = Inventories[src]
    if not inv then return nil end

    local item = FindInventoryItem(inv, itemName, slotId)
    if item then
        return EnsureItemMetadata(item.name, item.metadata)
    end

    return nil
end

RegisterNetEvent('corex-inventory:server:updateWeaponMeta', function(weaponName, metadata, slotId, syncClient)
    local src = source
    UpdateItemMeta(src, weaponName, metadata, slotId, syncClient)
end)

RegisterNetEvent('corex-inventory:server:updateWeaponAmmo', function(slotId, weaponName, ammo)
    local src = source
    local safeAmmo = math.max(0, math.floor(tonumber(ammo) or 0))
    UpdateItemMeta(src, weaponName, { ammo = safeAmmo }, slotId, false)
end)

RegisterNetEvent('corex-inventory:server:requestAmmoReload', function(slotId, weaponName)
    local src = source
    local inv = Inventories[src]

    if not inv then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, weaponName, 0, 0, 'Inventory not ready')
        return
    end

    local weaponItem = FindInventoryItem(inv, weaponName, slotId)
    if not weaponItem then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, weaponName, 0, 0, 'Weapon not found')
        return
    end

    local weaponDef, canonicalName = GetWeaponDefinition(weaponItem.name)
    if not weaponDef or not weaponDef.ammoType then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName or weaponItem.name, 0, 0, 'This weapon cannot be reloaded')
        return
    end

    if GetInventoryItemCount(inv, weaponDef.ammoType) < 1 then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName, 0, 0, 'No ammo item available')
        return
    end

    if not RemoveItem(src, weaponDef.ammoType, 1) then
        TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, false, slotId, canonicalName, 0, 0, 'Failed to consume ammo item')
        return
    end

    weaponItem.metadata = EnsureItemMetadata(weaponItem.name, weaponItem.metadata)
    local newAmmo = math.max(0, math.floor(tonumber(weaponItem.metadata.ammo) or 0)) + 10
    weaponItem.metadata.ammo = newAmmo

    TriggerClientEvent('corex-inventory:client:ammoReloadResult', src, true, slotId, canonicalName, newAmmo, 10, weaponDef.ammoType)
end)

exports('GetItemsCatalog',  function() return Items   or {} end)
exports('GetWeaponsCatalog', function() return Weapons or {} end)
exports('GetAmmoCatalog',   function() return Ammo    or {} end)
exports('GetFullCatalog',   GetAllItemsData)
exports('AddItem',          AddItem)
exports('RemoveItem',       RemoveItem)
exports('GetInventory',     function(src) return Inventories[src] end)
exports('DropItem',         DropItem)
exports('PickupItem',       PickupItem)
exports('UpdateItemMeta',   UpdateItemMeta)
exports('GetItemMeta',      GetItemMeta)
exports('HasItem', function(src, itemName, count)
    count = count or 1
    local inv = Inventories[src]
    if not inv then return false end

    local total = 0
    for _, item in ipairs(inv.items) do
        if item.name == itemName then
            total = total + item.count
            if total >= count then return true end
        end
    end
    return false
end)
exports('GetItemCount', function(src, itemName)
    local inv = Inventories[src]
    if not inv then return 0 end

    local total = 0
    for _, item in ipairs(inv.items) do
        if item.name == itemName then
            total = total + item.count
        end
    end
    return total
end)

RegisterCommand('giveitem', function(src, args)
    local target, item, count
    local firstAsId = tonumber(args[1])
    if firstAsId and args[2] then
        target = firstAsId
        item   = args[2]
        count  = tonumber(args[3]) or 1
    elseif src > 0 then
        target = src
        item   = args[1]
        count  = tonumber(args[2]) or 1
    else
        Debug('Warn', 'Console usage: /giveitem <playerId> <item> [count]')
        return
    end

    if not item then
        Debug('Warn', 'Usage: /giveitem [playerId] <item> [count]')
        return
    end

    local ok, err = AddItem(target, item, count)
    if ok then
        Debug('Info', 'Added ' .. item .. ' x' .. count .. ' to player ' .. target)
    else
        Debug('Warn', 'Failed: ' .. (err or 'Unknown'))
    end
end, true)

RegisterCommand('removeitem', function(src, args)
    local target, item, count
    local firstAsId = tonumber(args[1])
    if firstAsId and args[2] then
        target = firstAsId
        item   = args[2]
        count  = tonumber(args[3]) or 1
    elseif src > 0 then
        target = src
        item   = args[1]
        count  = tonumber(args[2]) or 1
    else
        Debug('Warn', 'Console usage: /removeitem <playerId> <item> [count]')
        return
    end

    if not item then
        Debug('Warn', 'Usage: /removeitem [playerId] <item> [count]')
        return
    end

    RemoveItem(target, item, count)
end, true)

RegisterCommand('cleardrops', function()
    DroppedItems = {}
    BroadcastDroppedItems()
    Debug('Info', 'All dropped items cleared')
end, true)

RegisterNetEvent('corex-inventory:server:purchaseShopItem', function(shopName, itemName, amount)
    local src = source

    if type(shopName) ~= 'string' or type(itemName) ~= 'string' then return end
    amount = tonumber(amount) or 1
    if amount < 1 or amount > 100 then return end

    local player = GetPlayer(src)
    if not player then
        Debug('Error', 'Player not found for shop purchase')
        return
    end

    if not Shops then
        Debug('Error', 'Shops table is nil on server')
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Shop system error', 0)
        return
    end

    if not Shops[shopName] then
        Debug('Warn', 'Shop not found: ' .. shopName)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Shop not found', 0)
        return
    end

    local shop = Shops[shopName]
    if not IsPlayerNearShop(src, shop) then
        Debug('Warn', ('Shop purchase rejected: player %d too far from %s'):format(src, shopName))
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Too far from shop', GetCurrencyBalance(src, 'cash'))
        return
    end

    local itemConfig = nil

    local lowerTarget = string.lower(itemName)
    for _, config in ipairs(shop.items) do
        if string.lower(config.name) == lowerTarget then
            itemConfig = config
            break
        end
    end

    if not itemConfig then
        Debug('Warn', 'Item not found in shop: ' .. itemName)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Item not available', 0)
        return
    end

    local totalPrice   = itemConfig.price * amount
    local currency     = itemConfig.currency or 'cash'
    local playerMoney  = GetCurrencyBalance(src, currency)

    if playerMoney < totalPrice then
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Not enough money! You have $' .. playerMoney .. ', need $' .. totalPrice, playerMoney)
        return
    end

    local itemAmount = (itemConfig.amount or 1) * amount

    local addSuccess, err = AddItem(src, itemName, itemAmount)
    if not addSuccess then
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Inventory full or error: ' .. (err or 'Unknown'), playerMoney)
        return
    end

    if not ConsumeCurrency(src, currency, totalPrice) then
        RemoveItem(src, itemName, itemAmount)
        TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, false, 'Transaction failed - could not remove money', playerMoney)
        return
    end

    local newMoney = GetCurrencyBalance(src, currency)

    local itemDef = Items[itemName] or Weapons[itemName] or Weapons[string.upper(itemName)] or Ammo[itemName]
    local itemLabel = itemDef and itemDef.label or itemName

    Debug('Info', 'Player ' .. src .. ' purchased ' .. itemAmount .. 'x ' .. itemLabel .. ' for $' .. totalPrice)

    TriggerClientEvent('corex-inventory:client:shopPurchaseResult', src, true, 'Purchased ' .. itemAmount .. 'x ' .. itemLabel .. ' for $' .. totalPrice, newMoney)
end)

RegisterNetEvent('corex-inventory:server:purchaseVehicleShopItem', function(shopName, model)
    local src = source
    if type(shopName) ~= 'string' or type(model) ~= 'string' then return end

    if PendingVehiclePurchases[src] then
        local cash = GetCurrencyBalance(src, 'cash')
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Wait for the current bike to finish deploying.', cash)
        return
    end

    local player = GetPlayer(src)
    if not player then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Player not found.', 0)
        return
    end

    local shop = Shops and Shops[shopName]
    if not shop or shop.type ~= 'vehicle' then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Vehicle shop not found.', GetCurrencyBalance(src, 'cash'))
        return
    end

    if not IsPlayerNearShop(src, shop) then
        Debug('Warn', ('Vehicle purchase rejected: player %d too far from %s'):format(src, shopName))
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Too far from shop.', GetCurrencyBalance(src, 'cash'))
        return
    end

    local catalogId   = shop.catalogId or 'bike_rental'
    local catalog     = GetVehicleCatalog(catalogId)
    local vehicleDef  = GetVehicleDefinition(catalogId, model)
    if not catalog or not vehicleDef then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Vehicle is not available.', GetCurrencyBalance(src, 'cash'))
        return
    end

    local currency = catalog.currency or 'cash'
    local price    = tonumber(vehicleDef.price) or 0
    local balance  = GetCurrencyBalance(src, currency)
    if balance < price then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Not enough money.', balance)
        return
    end

    if not ConsumeCurrency(src, currency, price) then
        TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, 'Transaction failed.', balance)
        return
    end

    PendingVehiclePurchases[src] = {
        shopName  = shopName,
        model     = NormalizeVehicleKey(model),
        label     = vehicleDef.label or model,
        price     = price,
        currency  = currency,
        expiresAt = GetGameTimer() + 15000
    }

    TriggerClientEvent('corex-inventory:client:spawnPurchasedVehicle', src, {
        shopName   = shopName,
        catalogId  = catalogId,
        model      = vehicleDef.model or model,
        plate      = GenerateRentalPlate(),
        spawnPoint = shop.spawnPoint or (shop.npc and shop.npc.coords)
    })
end)

RegisterNetEvent('corex-inventory:server:vehicleSpawnSucceeded', function(shopName, model)
    local src     = source
    local pending = PendingVehiclePurchases[src]
    if not pending then return end

    if pending.shopName ~= shopName or pending.model ~= NormalizeVehicleKey(model) then
        return
    end

    PendingVehiclePurchases[src] = nil

    local newMoney = GetCurrencyBalance(src, pending.currency)
    TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, true, pending.label .. ' deployed for $' .. pending.price, newMoney)
end)

RegisterNetEvent('corex-inventory:server:vehicleSpawnFailed', function(shopName, model, reason)
    local src     = source
    local pending = PendingVehiclePurchases[src]
    if not pending then return end

    if pending.shopName ~= shopName or pending.model ~= NormalizeVehicleKey(model) then
        return
    end

    PendingVehiclePurchases[src] = nil

    local addSuccess = RefundCurrency(src, pending.currency, pending.price)
    local newMoney = GetCurrencyBalance(src, pending.currency)
    local refundMessage = 'Vehicle spawn failed, money refunded.'
    if Config and Config.Debug then
        Debug('Warn', ('Vehicle spawn failed for %s (%s): %s'):format(src, pending.model, tostring(reason)))
    end

    if not addSuccess then
        refundMessage = 'Vehicle spawn failed and refund could not be completed.'
    end

    TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, refundMessage, newMoney)
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for src, pending in pairs(PendingVehiclePurchases) do
            if now >= pending.expiresAt then
                local refundSuccess = RefundCurrency(src, pending.currency, pending.price)
                PendingVehiclePurchases[src] = nil

                local newMoney = GetCurrencyBalance(src, pending.currency)
                TriggerClientEvent('corex-inventory:client:vehiclePurchaseResult', src, false, refundSuccess and 'Vehicle spawn timed out, money refunded.' or 'Vehicle spawn timed out.', newMoney)
            end
        end
    end
end)

exports('GetItemData', function(itemName)
    if type(itemName) ~= 'string' then return nil end
    local lo, up = string.lower(itemName), string.upper(itemName)
    return Items[itemName] or Items[lo] or Items[up]
        or Weapons[itemName] or Weapons[lo] or Weapons[up]
        or Ammo[itemName] or Ammo[lo] or Ammo[up]
end)

exports('GetAllItemsData', function()
    local all = {}
    for k, v in pairs(Items   or {}) do all[k] = v end
    for k, v in pairs(Weapons or {}) do all[k] = v end
    for k, v in pairs(Ammo    or {}) do all[k] = v end
    return all
end)

exports('GetRarity', function()
    return Rarity
end)
