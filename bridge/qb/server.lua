if GetResourceState('qb-core') ~= 'started' then return end

QBCore = exports['qb-core']:GetCoreObject()

function RegisterCallback(name, cb)
    QBCore.Functions.CreateCallback(name, cb)
end

function RegisterUsableItem(...)
    QBCore.Functions.CreateUseableItem(...)
end

function ShowNotification(target, text)
	TriggerClientEvent(GetCurrentResourceName()..":showNotification", target, text)
end

function GetIdentifier(source)
    local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))?.PlayerData
    if not xPlayer or not xPlayer.citizenid then return end
    return xPlayer.citizenid 
end

function GetSourceFromIdentifier(identifier)
    local xPlayer = QBCore.Functions.GetPlayerByCitizenId(identifier)
    return xPlayer and xPlayer?.PlayerData.source or nil
end

function GetPlayerCharacterName(source)
    local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
    if not xPlayer or not xPlayer.PlayerData then return "Unknown Name" end
    return xPlayer.PlayerData.charinfo.firstname .. " " .. xPlayer.PlayerData.charinfo.lastname
end

function CanAccessGroup(source, data)
    if not data then return true end
    local pdata = QBCore.Functions.GetPlayer(tonumber(source)).PlayerData
    for k,v in pairs(data) do 
        if (pdata.job.name == k and pdata.job.grade.level >= v) then return true end
    end
    return false
end

function CheckPermission(source, permission)
    if permission.ignorePermissions then return true end
    local source = tonumber(source)
    local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))?.PlayerData
    if not xPlayer then return end
    if not xPlayer then return false end
    local name = xPlayer.job.name
    local rank = xPlayer.job.grade.level
    if permission.jobs[name] and permission.jobs[name] <= rank then 
        return true
    end
    for i=1, #(permission.groups or {}) do 
        if QBCore.Functions.HasPermission(source, permission.groups[i]) then 
            return true 
        end
    end
end

function AddMoney(source,count)
    local p=QBCore.Functions.GetPlayer(source)
    if not p then return false end
    return p.Functions.AddMoney('cash',count)==true
end

function RemoveMoney(source,count)
    local p=QBCore.Functions.GetPlayer(source)
    if not p then return false end
    return p.Functions.RemoveMoney('cash',count)==true
end

function GetMoney(source)
    local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
    return xPlayer.PlayerData.money.cash
end

RegisterNetEvent("QBCore:Server:OnJobUpdate", function(player)
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
        local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
        local weight = QBCore.Player.GetTotalWeight(xPlayer.PlayerData.items)
        local item = QBCore.Shared.Items[name:lower()]
        return ((weight + (item.weight * count)) <= QBCore.Config.Player.MaxWeight)
    end

    Inventory.GetInventory = function(source)
        local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
        local items = {}
        if not xPlayer then return items end
        local data = xPlayer.PlayerData.items
        for slot, item in pairs(data) do 
            items[#items + 1] = {
                name = item.name,
                label = item.label,
                count = item.amount,
                weight = item.weight
            }
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
        local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
        if not xPlayer then return false end
        local ok=xPlayer.Functions.AddItem(name, count, nil, metadata)
        Inventory.UpdateInventory(source)
        return ok==true
    end

    Inventory.RemoveItem = function(source, name, count)
        local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
        if not xPlayer then return false end
        local ok=xPlayer.Functions.RemoveItem(name, count)
        Inventory.UpdateInventory(source)
        return ok==true
    end

    Inventory.AddWeapon = function(source, name, count, metadata) -- Metadata is not required.
        return Inventory.AddItem(source, name, count, metadata)
    end

    Inventory.RemoveWeapon = function(source, name, count)
        Inventory.RemoveItem(source, name, count, metadata)
    end

    Inventory.GetItemCount = function(source, name)
        local xPlayer = QBCore.Functions.GetPlayer(tonumber(source))
        local item = xPlayer.Functions.GetItemByName(name)
        return item and item.amount or 0
    end

    Inventory.HasWeapon = function(source, name, count)
        return (Inventory.GetItemCount(source, name) > 0)
    end

    RegisterCallback("pickle_bailbounty:getInventory", function(source, cb)
        cb(Inventory.GetInventory(source))
    end)

    for item, data in pairs(QBCore.Shared.Items) do
        Inventory.Items[item] = {label = data.label}
    end
    Inventory.Ready = true
end)