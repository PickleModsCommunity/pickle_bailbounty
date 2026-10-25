BailRegistry = {}
local BailWarnings = {}

function AddBailToRegistry(bail, ignoreSync, insertSQL)
    if not bail.identifier then
        dprint("Bail missing target")
        return
    end
    if BailRegistry[bail.identifier] then
        dprint("Bail already exists for identifier: " .. bail.identifier)
        return
    end
    local entry = {
        source = GetSourceFromIdentifier(bail.identifier),
        identifier = bail.identifier,
        name = bail.name,
        image = bail.image or "NO_IMAGE",
        issuer = bail.issuer,
        reward = bail.reward,
        description = bail.description,
        startdate = bail.startdate,
        completiondate = bail.completiondate,
        nextcompliance = bail.nextcompliance,
        lastcompliance = bail.lastcompliance,
        status = bail.status or "compliant",
        sentence = bail.sentence or 0,
    }
    if insertSQL then
        BBExecute("INSERT INTO pickle_bailbounty_bail (identifier, name, image, issuer, reward, description, status, startdate, completiondate, nextcompliance, lastcompliance, sentence) VALUES (@identifier, @name, @image, @issuer, @reward, @description, @status, @startdate, @completiondate, @nextcompliance, @lastcompliance, @sentence)", {
            ["@identifier"] = bail.identifier,
            ["@name"] = bail.name,
            ["@image"] = bail.image or "NO_IMAGE",
            ["@issuer"] = bail.issuer,
            ["@reward"] = bail.reward,
            ["@description"] = bail.description,
            ["@status"] = bail.status,
            ["@startdate"] = bail.startdate and os.date("%Y-%m-%d %H:%M:%S", bail.startdate) or nil,
            ["@completiondate"] = bail.completiondate and os.date("%Y-%m-%d %H:%M:%S", bail.completiondate) or nil,
            ["@nextcompliance"] = bail.nextcompliance and os.date("%Y-%m-%d %H:%M:%S", bail.nextcompliance) or nil,
            ["@lastcompliance"] = bail.lastcompliance and os.date("%Y-%m-%d %H:%M:%S", bail.lastcompliance) or nil,
            ["@sentence"] = bail.sentence or 0,
        }, function(rowsChanged)
            dprint("Inserted bail into SQL: " .. rowsChanged)
        end)
    end
    BailRegistry[bail.identifier] = entry
    if ignoreSync then return end
    BBBroadcast("pickle_bailbounty:addbail", bail.identifier, BailRegistry[bail.identifier])
end

exports("AddBailToRegistry", function(bail)
    AddBailToRegistry(bail, false, true)
end)

function RemoveBailFromRegistry(identifier, ignoreSync)
    if not BailRegistry[identifier] then
        dprint("Bail does not exist for identifier: " .. identifier)
        return
    end
    BBExecute("DELETE FROM pickle_bailbounty_bail WHERE identifier = @identifier", {
        ["@identifier"] = identifier,
    }, function(rowsChanged)
        dprint("Deleted bail from SQL: " .. rowsChanged)
    end)
    BailRegistry[identifier] = nil
    if ignoreSync then return end
    BBBroadcast("pickle_bailbounty:removebail", identifier, GetSourceFromIdentifier(identifier))
end

exports("RemoveBailFromRegistry", function(identifier)
    RemoveBailFromRegistry(identifier, false)
end)

function GetBailStatus(index, params)
    local bail = BailRegistry[index]
    local extraData = {}
    if not bail then return end
    if params.onlyPlayer then
        if string.sub(bail.identifier, 1, 4) == "npc:" then return end
        if params.requireOnline then
            extraData.source = GetSourceFromIdentifier(bail.identifier)
            if not extraData.source then return end
        end
    end
    return bail, extraData
end

exports("GetBailStatus", GetBailStatus)

function DoesBailRequireCheckIn(bail)
    if not bail.nextcompliance then return false end
    return (bail.nextcompliance - os.time()) < 86400
end

exports("DoesBailRequireCheckIn", DoesBailRequireCheckIn)

function UpdateBail(identifier, bail, noSQL)
    BailRegistry[identifier] = bail
    local event = function()
        BBBroadcast("pickle_bailbounty:updatebail", identifier, BailRegistry[identifier])
    end
    if noSQL then event() return end
    BBExecute("UPDATE pickle_bailbounty_bail SET status = @status, startdate = @startdate, completiondate = @completiondate, nextcompliance = @nextcompliance, lastcompliance = @lastcompliance WHERE identifier = @identifier", {
        ["@identifier"] = identifier,
        ["@status"] = bail.status,
        ["@startdate"] = bail.startdate and os.date("%Y-%m-%d %H:%M:%S", bail.startdate) or nil,
        ["@completiondate"] = bail.completiondate and os.date("%Y-%m-%d %H:%M:%S", bail.completiondate) or nil,
        ["@nextcompliance"] = bail.nextcompliance and os.date("%Y-%m-%d %H:%M:%S", bail.nextcompliance) or nil,
        ["@lastcompliance"] = bail.lastcompliance and os.date("%Y-%m-%d %H:%M:%S", bail.lastcompliance) or nil,
    }, function(rowsChanged)
        event()
    end)
end

RegisterNetEvent('pickle_bailbounty:placeBail',function(data)
    local src=source
    if not GetPlayerPermissions(src).bailPlacement or not BBValidData(src,data,true) then return end
    local target=data.source; local id=GetIdentifier(target)
    if not id or BBLocks[id] or BailRegistry[id] or BountyRegistry[id] or GetMoney(target)<data.penalty
        or Inventory.GetItemCount(src,'ankle_monitor')<1 then return end
    BBLocks[id]=true
    if not Inventory.RemoveItem(src,'ankle_monitor',1) then BBLocks[id]=nil; return end
    if not RemoveMoney(target,data.penalty) then Inventory.AddItem(src,'ankle_monitor',1); BBLocks[id]=nil; return end
    local bail={identifier=id,name=GetPlayerCharacterName(target),image=data.image,issuer=GetIdentifier(src),
        reward=data.penalty,description=data.description or '',startdate=os.time(),completiondate=os.time()+data.length*86400,
        nextcompliance=os.time()+86400,lastcompliance=os.time(),status='compliant',sentence=data.sentence or 0}
    local ok=pcall(AddBailToRegistry,bail,false,true)
    if not ok then
        BBPay(id,data.penalty,'failed-placement:'..id..':'..bail.startdate)
        Inventory.AddItem(src,'ankle_monitor',1)
    end
    BBLocks[id]=nil
end)

RegisterNetEvent('pickle_bailbounty:clearBail', function(target)
    local bail = BailRegistry[target]
    if not bail then return end
    local permissions = GetPlayerPermissions(source)
    if not permissions.bailManage then
        return ShowNotification(source, _L("no_permission_bailmanage"))
    end
    ShowNotification(source, _L("bail_cleared", bail.name))
    RemoveBailFromRegistry(target, false)
end)

RegisterNetEvent("pickle_bailbounty:revokeBail", function(target, selfRemove)
    local source = source
    if selfRemove then
        if not Config.Bail.tracker.removal.enabled then return end
        target = GetIdentifier(source)
        ShowNotification(source, _L("tracker_removed"))
        local removeData = {
            coords = GetEntityCoords(GetPlayerPed(source)), 
            name = GetPlayerCharacterName(source), 
            source = source, 
            identifier = target,
        }
        Config.Bail.tracker.onTrackerRemoval.server(removeData)
        TriggerClientEvent("pickle_bailbounty:trackerRemoved", source, removeData)
    else
        local permissions = GetPlayerPermissions(source)
        if not permissions.bailManage then
            return ShowNotification(source, _L("no_permission_bailmanage"))
        end
    end
    local bail = BailRegistry[target]
    if not bail then return end
    BBConvertBail(target)
    if not selfRemove then
        ShowNotification(source, _L("bail_revoked", bail.name))
    end
end)

RegisterNetEvent("pickle_bailbounty:completeParoleCheckin", function()
    local source = source
    local identifier = GetIdentifier(source)
    if not identifier then return end
    local bail = BailRegistry[identifier]
    local mission=BBParole[source]
    if not bail or not mission or mission.identity~=identifier or mission.period~=bail.nextcompliance
        or os.time()>mission.period or mission.progress<mission.required then return end
    BBParole[source]=nil
    bail.lastcompliance = os.time()
    local nextDate = bail.startdate
    repeat
        nextDate = nextDate + 86400
    until nextDate > bail.lastcompliance
    bail.nextcompliance = nextDate
    bail.status = "compliant"
    UpdateBail(identifier, bail)
end)

RegisterCallback("pickle_bailbounty:getBailInfo", function(source, cb, target)
    local target = target or GetIdentifier(source)
    if target~=GetIdentifier(source) and not GetPlayerPermissions(source).bailManage and not GetPlayerPermissions(source).bailPlacement then cb(); return end
    local bail, data = GetBailStatus(target, {onlyPlayer = true, requireOnline = true})
    if not bail then return cb() end
    cb({
        startdate = bail.startdate and os.date("%m/%d/%Y %H:%M:%S", bail.startdate) or _L("bail_registry_never"),
        completiondate = bail.completiondate and os.date("%m/%d/%Y %H:%M:%S", bail.completiondate) or _L("bail_registry_never"),
        lastcompliance = bail.lastcompliance and os.date("%m/%d/%Y %H:%M:%S", bail.lastcompliance) or _L("bail_registry_never"),
        checkIn = DoesBailRequireCheckIn(bail),
    })
end)

RegisterUsableItem("ankle_monitor", function(source)
    local permissions = GetPlayerPermissions(source)
    if not permissions.bailManage then
        return ShowNotification(source, _L("no_permission_bailmanage"))
    end
    TriggerClientEvent("pickle_bailbounty:openRegisterBail", source)
end)

function GetTimeLeft(timeLeft)
    local hours = math.floor(timeLeft / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    return string.format(_L("time_left"), hours, minutes)
end

CreateThread(function() 
    Wait(1000)
    while true do 
        for k,v in pairs(BailRegistry) do
            local bail, data = GetBailStatus(k, {onlyPlayer = true, requireOnline = true})
            if bail then
                local currentTime = os.time()
                local nextcompliance = bail.nextcompliance
                local timeLeft = nextcompliance - currentTime
                if currentTime > nextcompliance and nextcompliance < bail.completiondate then
                    BBConvertBail(k)
                elseif currentTime > bail.completiondate then
                    local reward = bail.reward
                    RemoveBailFromRegistry(k)
                    BBPay(bail.identifier,reward,"bail:"..bail.identifier..":"..bail.startdate)
                    ShowNotification(data.source, _L("bail_registry_reward", NumberWithCommas(reward)))
                else
                    local notifyTime = Config.Bail.notifyTime * 3600
                    local bailWarning = BailWarnings[k] or 0
                    if timeLeft < notifyTime and os.time() > bailWarning then 
                        local formatTimeLeft = GetTimeLeft(timeLeft)
                        ShowNotification(data.source, _L("bail_registry_compliance_notice_1", formatTimeLeft))
                        ShowNotification(data.source, _L("bail_registry_compliance_notice_2"))
                        BailWarnings[k] = os.time() + (Config.Bail.reminderInterval * 60)
                    end
                end
            end
        end
        Wait(60 * 1000)
    end
end)

CreateThread(function() 
    Wait(1000)
    while true do
        local BailPlayers = {} 
        for k,v in pairs(BailRegistry) do
            local bail, data = GetBailStatus(k, {onlyPlayer = true, requireOnline = true})
            if bail then
                local ped = GetPlayerPed(data.source)
                local coords = GetEntityCoords(ped)
                BailPlayers[data.source] = {coords = coords, name = GetPlayerCharacterName(data.source)}
            end
        end
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id); local p=GetPlayerPermissions(src)
            TriggerClientEvent('pickle_bailbounty:updateBailPlayers',src,(p.bailPlacement or p.bailManage) and BailPlayers or {})
        end
        Wait(5000)
    end
end)