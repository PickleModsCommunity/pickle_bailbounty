if GetResourceState('es_extended') ~= 'started' then return end

ESX = exports.es_extended:getSharedObject()

function RegisterCallback(name, cb)
    ESX.RegisterServerCallback(name, cb)
end

function RegisterUsableItem(...)
    ESX.RegisterUsableItem(...)
end

function ShowNotification(target, text)
	TriggerClientEvent(GetCurrentResourceName()..":showNotification", target, text)
end

function GetIdentifier(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not xPlayer.identifier then return end
    return xPlayer.identifier
end

function GetSourceFromIdentifier(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    return xPlayer and xPlayer.source or nil
end

function GetPlayerCharacterName(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return "Unknown Name" end
    return xPlayer.getName()
end

function CanAccessGroup(source, data)
    if not data then return true end
    local pdata = ESX.GetPlayerFromId(source)
    for k,v in pairs(data.jobs) do 
        if (pdata.job.name == k and pdata.job.grade >= v) then return true end
    end
    return false
end 

function CheckPermission(source, permission)
    if permission.ignorePermissions then return true end
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    if not xPlayer then return false end
    local name = xPlayer.job.name
    local rank = xPlayer.job.grade
    local group = xPlayer.getGroup()
    if permission.jobs[name] and permission.jobs[name] <= rank then 
        return true
    end
    for i=1, #(permission.groups or {}) do 
        if group == permission.groups[i] then 
            return true 
        end
    end
end

function AddMoney(source,count)
    local p=ESX.GetPlayerFromId(source)
    if not p then return false end
    local before=p.getMoney()

    p.addMoney(count)
    return p.getMoney()==before + count
end

function RemoveMoney(source,count)
    local p=ESX.GetPlayerFromId(source)
    if not p then return false end
    local before=p.getMoney()
    if before<count then return false end
    p.removeMoney(count)
    return p.getMoney()==before - count
end

function GetMoney(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer.getMoney()
end

RegisterNetEvent('esx:setJob', function(player, job, lastJob)
    ResyncPermissions(player)
end)

-- Inventory Fallback

CreateThread(function()
    Wait(100)

    if InitializeInventory then return InitializeInventory() end -- Already loaded through inventory folder.
    
    Inventory = {}

    Inventory.Items = {}
    
    Inventory.Ready = false

    Inventory.CanCarryItem = function(source, name, count)
        local xPlayer = ESX.GetPlayerFromId(source)
        if Config.InventoryLimit then 
            local item = xPlayer.getInventoryItem(name)
            return (item.limit >= item.count + count)
        else 
            return xPlayer.canCarryItem(name, count)
        end
    end

    Inventory.GetInventory = function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        local items = {}
        if not xPlayer then return items end
        local data = xPlayer.getInventory()
        for i=1, #data do 
            local item = data[i]
            if item then
                items[#items + 1] = {
                    name = item.name,
                    label = item.label,
                    count = item.count,
                    weight = item.weight
                }
            end
        end
        return items
    end

    Inventory.UpdateInventory = function(source)
        local owner=GetIdentifier(source)
        SetTimeout(1000, function()
            if GetPlayerName(source) and GetIdentifier(source)==owner then TriggerClientEvent("pickle_bailbounty:updateInventory", source, Inventory.GetInventory(source)) end
        end)
    end

    Inventory.AddItem = function(source, name, count, metadata) -- Metadata is not required.
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        local before=Inventory.GetItemCount(source,name)
        if not Inventory.CanCarryItem(source,name,count) then return false end
        xPlayer.addInventoryItem(name, count)
        Inventory.UpdateInventory(source)
        return Inventory.GetItemCount(source,name)==before + count
    end

    Inventory.RemoveItem = function(source, name, count)
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        local before=Inventory.GetItemCount(source,name)
        if before<count then return false end
        xPlayer.removeInventoryItem(name, count)
        Inventory.UpdateInventory(source)
        return Inventory.GetItemCount(source,name)==before - count
    end

    Inventory.AddWeapon = function(source, name, count, metadata) -- Metadata is not required.
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer or xPlayer.hasWeapon(name) then return false end
        xPlayer.addWeapon(name, 0)
        Inventory.UpdateInventory(source)
        return xPlayer.hasWeapon(name)
    end

    Inventory.RemoveWeapon = function(source, name, count)
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer or not xPlayer.hasWeapon(name) then return false end
        xPlayer.removeWeapon(name, 0)
        Inventory.UpdateInventory(source)
        return not xPlayer.hasWeapon(name)
    end

    Inventory.GetItemCount = function(source, name)
        local xPlayer = ESX.GetPlayerFromId(source)
        local item = xPlayer.getInventoryItem(name)
        return item and item.count or 0
    end

    Inventory.HasWeapon = function(source, name, count)
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer.hasWeapon(name)
    end

    RegisterCallback("pickle_bailbounty:getInventory", function(source, cb)
        cb(Inventory.GetInventory(source))
    end)

    MySQL.ready(function() 
        MySQL.Async.fetchAll("SELECT * FROM items;", {}, function(results) 
            for i=1, #results do 
                Inventory.Items[results[i].name] = {label = results[i].label}
            end
            Inventory.Ready = true
        end)
    end)
end)
