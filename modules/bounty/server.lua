BountyRegistry = {}
BountyInfo = {}
BountyHunters = {}

function AddBountyToRegistry(bounty, ignoreSync, insertSQL) 
    if not bounty.target then
        dprint("Bounty missing target")
        return
    end
    if BountyRegistry[bounty.target] then
        dprint("Bounty already exists for target: " .. bounty.target)
        return
    end
    local entry = {
        source = GetSourceFromIdentifier(bounty.target),
        npc = bounty.npc or nil,
        target = bounty.target,
        targetname = bounty.targetname,
        image = bounty.image or "NO_IMAGE",
        issuer = bounty.issuer,
        reward = bounty.reward,
        description = bounty.description,
        datetime = bounty.datetime or os.time(),
        risk = bounty.risk or (string.find(bounty.target, "npc:") and 1 or 3),
        sentence = bounty.sentence or 0,
    }
    if insertSQL then
        BBExecute("INSERT INTO pickle_bailbounty_bounties (target, targetname, image, issuer, reward, description, datetime, sentence) VALUES (@target, @targetname, @image, @issuer, @reward, @description, @datetime, @sentence)", {
            ["@target"] = bounty.target,
            ["@targetname"] = bounty.targetname,
            ["@image"] = bounty.image or "NO_IMAGE",
            ["@issuer"] = bounty.issuer,
            ["@reward"] = bounty.reward,
            ["@description"] = bounty.description,
            ["@datetime"] = bounty.datetime and os.date("%Y-%m-%d %H:%M:%S", bounty.datetime) or nil,
            ["@sentence"] = bounty.sentence or 0,
        }, function(rowsChanged)
            dprint("Inserted bounty into SQL: " .. rowsChanged)
        end)
    end
    BountyRegistry[bounty.target]=entry
    if ignoreSync then return end
    BBBroadcast("pickle_bailbounty:addBounty", bounty.target, BountyRegistry[bounty.target])
end

exports("AddBountyToRegistry", function(bounty)
    AddBountyToRegistry(bounty, false, true)
end)

function RemoveBountyFromRegistry(target, ignoreSync, deleteSQL, source)
    if not BountyRegistry[target] then
        dprint("Bounty does not exist for target: " .. target)
        return
    end
    local info=BountyInfo[target]
    if info then
        BBBroadcast('pickle_bailbounty:setBountyState',target,{type='removeBountyTarget',source=source})
    end
    BountyRegistry[target] = nil
    BountyInfo[target] = nil
    if source then
        BBBroadcast("pickle_bailbounty:setBountyState", target, {
            type = "removeBountyTarget",
            source = source,
        })
    end
    if deleteSQL then
        MySQL.Async.execute("DELETE FROM pickle_bailbounty_bounties WHERE target = @target", {
            ["@target"] = target,
        }, function(rowsChanged)
            dprint("Deleted bounty from SQL: " .. rowsChanged)
        end)
    end
    if ignoreSync then return end
    BBBroadcast("pickle_bailbounty:removeBounty", target)
end

exports("RemoveBountyFromRegistry", function(target)
    RemoveBountyFromRegistry(target, false, true)
end)

function UpdateBounty(target, bounty)
    if not BountyRegistry[target] then
        dprint("Bounty does not exist for target: " .. target)
        return
    end
    BountyRegistry[target] = bounty
    BBBroadcast("pickle_bailbounty:updateBounty", target, bounty)
end

function GenerateNPCBounty(ignoreSync)
    if not Config.NPCBounties.enabled then return end
    local count=0
    for _,b in pairs(BountyRegistry) do if b.npc then count=count+1 end end
    if count>=Config.NPCBounties.maxNPCBounties then return end
    local risk = 1
    local rng = math.random(1, 100)
    local chances = {
        Config.NPCBounties.riskLevels[1].riskChance,
        Config.NPCBounties.riskLevels[2].riskChance,
        Config.NPCBounties.riskLevels[3].riskChance,
    }
    local rng = math.random(1, 100)
    local cumulativeChance = 0
    for scenario, chance in pairs(chances) do
        cumulativeChance = cumulativeChance + chance
        if rng <= cumulativeChance * 100 then
            risk = scenario
            break
        end
    end
    local riskCfg = Config.NPCBounties.riskLevels[risk]
    local crimes = riskCfg.crimes
    local crime = crimes[math.random(1, #crimes)]
    local target = nil
    local gender = (math.random(1, 2) == 1 and "male" or "female")
    local genderCfg = Config.NPCBounties.characters[gender]
    local firstname = genderCfg.firstnames[math.random(1, #genderCfg.firstnames)]
    local lastname = Config.NPCBounties.characters.lastnames[math.random(1, #Config.NPCBounties.characters.lastnames)]
    local model = genderCfg.peds[math.random(1, #genderCfg.peds)]
    repeat
        target = "npc:" .. math.random(1, 999999)
    until not BountyRegistry[target]
    BountyRegistry[target] = {
        target = target,
        targetname = firstname .. " " .. lastname,
        npc = {
            model = model,
        },
        image = "https://cfx-nui-pickle_bailbounty/nui/images/"..model..".png",
        issuer = "system",
        reward = math.random(Config.NPCBounties.rewardRange[1], Config.NPCBounties.rewardRange[2]) * riskCfg.rewardMultiplier,
        description = _L("npc_description", firstname .. " " .. lastname, crime, _L("available_bounties_risk_" .. risk)),
        datetime = os.time(),
        risk = risk,
    }
    if ignoreSync then return end
    BBBroadcast("pickle_bailbounty:addBounty", target, BountyRegistry[target])
end

exports("GenerateNPCBounty", function()
    GenerateNPCBounty(false)
end)

function GetPlayerCurrentBounty(source)
    for k,v in pairs(BountyRegistry) do
        if v.bountyHunter == source then
            return k, v
        end
    end
end

exports("GetPlayerCurrentBounty", GetPlayerCurrentBounty)

function CancelBounty(target, remove)
    local bounty = BountyRegistry[target]
    if remove then
        RemoveBountyFromRegistry(target, false, true)
        if bounty.npc then
            GenerateNPCBounty(false)
        end
    else
        BBBroadcast('pickle_bailbounty:setBountyState',target,{type='removeBountyTarget'})
        BountyInfo[target]=nil
        bounty.bountyHunter = nil
        UpdateBounty(target, bounty)
    end
    BountyInfo[target] = nil
    BBBroadcast("pickle_bailbounty:setBountyState", target, {
        type = "removeBountyTarget"
    })
end

exports("CancelBounty", CancelBounty)

function CompleteBounty(identifier, source, jailPlayer, policeSource)
    local bounty = BountyRegistry[identifier]
    local bountyInfo = BountyInfo[identifier]  
    if not bounty or not bountyInfo then return end
    if BBLocks[identifier] then return end
    local entity=BBEntity(bountyInfo)
    if not entity or not DoesEntityExist(entity) or not bountyInfo.isDetained or GetEntityHealth(entity)<=0
        or bounty.hunterIdentifier~=GetIdentifier(bounty.bountyHunter) or not BountyHunters[bounty.bountyHunter]
        or GetEntityRoutingBucket(entity)~=GetPlayerRoutingBucket(source)
        or #(GetEntityCoords(entity)-GetEntityCoords(GetPlayerPed(source)))>10
        or not BBAt(source,policeSource and Config.Bail.paroleOfficers or Config.BountyHunters.cellLocations,15) then return end
    if not policeSource and source~=bounty.bountyHunter then return end
    BBLocks[identifier]=true
    if not bounty.npc then
        local changed=MySQL.Sync.execute('DELETE FROM pickle_bailbounty_bounties WHERE target=@target',{['@target']=identifier})
        if changed~=1 then BBLocks[identifier]=nil; return end
    end
    local settlement='bounty:'..identifier..':'..(bounty.datetime or 0)
    local function pay(src,amount) return BBPay(GetIdentifier(src),amount,settlement..':'..GetIdentifier(src)) end
    local reward = bounty.reward
    local bountyHunterCut = 1.0 * (policeSource and Config.BailOfficers.custodyRewardFactor or 1.0)
    if policeSource then
        pay(source, Config.BailOfficers.custodyRewardOfficer)
        ShowNotification(source, _L("bounty_custody_reward", NumberWithCommas(Config.BailOfficers.custodyRewardOfficer)))
        pay(bounty.bountyHunter, math.floor(reward * bountyHunterCut))
        ShowNotification(bounty.bountyHunter, _L("bounty_reward_self", NumberWithCommas(reward * bountyHunterCut)))
    else
        if bounty.bountyHunter ~= source then
            bountyHunterCut = bountyHunterCut - Config.BountyHunters.backupRewardFactor
            pay(source, math.floor(reward * Config.BountyHunters.backupRewardFactor))
            ShowNotification(source, _L("bounty_reward_aid", NumberWithCommas(reward * Config.BountyHunters.backupRewardFactor)))
            pay(bounty.bountyHunter, math.floor(reward * bountyHunterCut))
            ShowNotification(bounty.bountyHunter, _L("bounty_reward_deducted", NumberWithCommas(reward * bountyHunterCut), NumberWithCommas(reward * Config.BountyHunters.backupRewardFactor)))
        else
            pay(bounty.bountyHunter, math.floor(reward * bountyHunterCut))
            ShowNotification(bounty.bountyHunter, _L("bounty_reward_self", NumberWithCommas(reward * bountyHunterCut)))
        end        
    end
    if jailPlayer and bounty.source and bounty.sentence and bounty.sentence > 0 then
        Config.JailEvent(bounty.source, bounty.sentence or 0)
    end
    RemoveBountyFromRegistry(identifier, false, true, source)
    BBLocks[identifier]=nil
    if bounty.npc then SetTimeout(Config.NPCBounties.generateCooldown*1000,function() GenerateNPCBounty(false) end) end
end

function IsPlayerBountyHunter(source)
    return BountyHunters[source] ~= nil
end

exports("IsPlayerBountyHunter", IsPlayerBountyHunter)

RegisterNetEvent("pickle_bailbounty:setCurrentBountyNPC", function(netId)
    local source = source
    local currentBountyId, currentBounty = GetPlayerCurrentBounty(source)
    if not currentBounty or not currentBounty.npc or netId~=currentBounty.npc.netId then return end
    if BountyInfo[currentBountyId] then return end
    BountyInfo[currentBountyId] = {
        netId = netId,
        currentVehicle = nil,
        isDetained = false,
        dragger = nil,
    }
    CreateThread(function()
        while BountyRegistry[currentBountyId] and BountyInfo[currentBountyId] do 
            local bounty = BountyRegistry[currentBountyId]
            local bountyInfo = BountyInfo[currentBountyId]
            local netId = bountyInfo.netId
            local entity = NetworkGetEntityFromNetworkId(netId)
            if not DoesEntityExist(entity) then
                if bounty.bountyHunter then
                    ShowNotification(bounty.bountyHunter, _L("bounty_escaped", bounty.targetname))
                end
                CancelBounty(currentBountyId)
                break
            end
            if GetEntityHealth(entity) <= 0 then
                if bounty.bountyHunter then
                    ShowNotification(bounty.bountyHunter, _L("bounty_killed", bounty.targetname))
                end
                CancelBounty(currentBountyId, true)
                break
            end
            Wait(2000)
        end
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            SetTimeout(5000, function()
                if currentBounty.npc and currentBounty.npc.entity==entity and GetEntityModel(entity)==joaat(currentBounty.npc.model) then DeleteEntity(entity) end
            end)
        end
    end)
    BBBroadcast("pickle_bailbounty:setBountyState", currentBountyId, {
        type = "registerBountyTarget",
        netId = netId,
    })
end)

RegisterNetEvent("pickle_bailbounty:bountyInteract", function(identifier, interactType, data)
    local source = source
    local permissions = GetPlayerPermissions(source)
    local bounty = BountyRegistry[identifier]
    local bountyInfo = BountyInfo[identifier]
    if not bounty or not bountyInfo then return end
    local target=BBEntity(bountyInfo)
    if not target or not DoesEntityExist(target) or GetEntityHealth(target)<=0 or bounty.bountyHunter~=source
        or bounty.hunterIdentifier~=GetIdentifier(source) or GetEntityRoutingBucket(target)~=GetPlayerRoutingBucket(source)
        or #(GetEntityCoords(GetPlayerPed(source))-GetEntityCoords(target))>5 then return end
    data={coords=GetEntityCoords(GetPlayerPed(source)),heading=GetEntityHeading(GetPlayerPed(source))}
    if interactType=='drag' and not bountyInfo.isDetained then return end
    if not BountyHunters[source] then return ShowNotification(source, _L("no_permission_bounty")) end
    if interactType == "detain" then
        if not bountyInfo or bountyInfo.isDetained then 
            return ShowNotification(source, _L("bounty_already_detained"))
        end
        bountyInfo.isDetained = true
        -- local ped = NetworkGetEntityFromNetworkId(bountyInfo.netId)
        -- ClearPedTasksImmediately(ped)
        -- TaskPlayAnim(ped, "mp_arrest_paired", "crook_p2_back_left", 8.0, -8.0, 5500, 33, 0, false, false, false)

        BBBroadcast("pickle_bailbounty:setBountyState", identifier, {
            type = "detainBountyTarget",
            source = source,
            coords = data.coords,
            heading = data.heading,
        })
    elseif interactType == "drag" then
        if not bountyInfo or bountyInfo.dragger then 
            return ShowNotification(source, _L("bounty_someone_dragging"))
        end
        if bountyInfo.currentVehicle then
            return ShowNotification(source, _L("bounty_need_out_vehicle"))
        end
        bountyInfo.dragger = source
        BBBroadcast("pickle_bailbounty:setBountyState", identifier, {
            type = "dragBountyTarget",
            source = source,
        })
    elseif interactType == "stopDragging" then
        if not bountyInfo or not bountyInfo.dragger or bountyInfo.dragger ~= source then 
            return ShowNotification(source, _L("bounty_someone_dragging"))
        end
        bountyInfo.dragger = nil
        BBBroadcast("pickle_bailbounty:setBountyState", identifier, {
            type = "releaseBountyTarget",
            source = source,
        })
    elseif interactType == "completeBountyTarget" then
        CompleteBounty(identifier, source, true)
    end
end)

RegisterNetEvent("pickle_bailbounty:vehicleInteract", function(netId)
    local source = source
    local permissions = GetPlayerPermissions(source)
    if not BountyHunters[source] then return ShowNotification(source, _L("no_permission_bounty")) end
    if not BBInt(netId,1,2147483647) then return end
    local vehicle=NetworkGetEntityFromNetworkId(netId)
    if vehicle==0 or GetEntityType(vehicle)~=2 or GetEntityRoutingBucket(vehicle)~=GetPlayerRoutingBucket(source)
        or #(GetEntityCoords(vehicle)-GetEntityCoords(GetPlayerPed(source)))>5 then return end
    local free=GetPedInVehicleSeat(vehicle,2)==0
    local bountyId = nil
    local closestBounty = { id = nil, distance = nil }
    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    for k,v in pairs(BountyInfo) do
        if BountyRegistry[k] and BountyRegistry[k].bountyHunter==source and v.isDetained then
        if v.currentVehicle == netId then
            bountyId = k
        end
        local ped
        if v.netId then
            ped = NetworkGetEntityFromNetworkId(v.netId)
        elseif v.source then
            ped = GetPlayerPed(v.source)
        end
        if DoesEntityExist(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(pedCoords - playerCoords)
            if closestBounty.id == nil or distance < closestBounty.distance then
                closestBounty.id = k
                closestBounty.distance = distance
            end
        end
    end
        end
    if bountyId then -- Take out of current vehicle.
        BountyInfo[bountyId].currentVehicle = nil
        BBBroadcast("pickle_bailbounty:setBountyState", bountyId, {
            type = "removeBountyFromVehicle",
            source = source,
            currentVehicle = netId,
        })
    elseif free and closestBounty.id and closestBounty.distance < 5.0 then -- Put in closest vehicle.
        if BountyInfo[closestBounty.id].dragger then
            local dragger = BountyInfo[closestBounty.id].dragger
            BBBroadcast("pickle_bailbounty:setBountyState", closestBounty.id, {
                type = "releaseBountyTarget",
                source = dragger,
            })
            SetTimeout(100, function()
                BBBroadcast("pickle_bailbounty:setBountyState", closestBounty.id, {
                    type = "putBountyInVehicle",
                    source = dragger,
                    currentVehicle = netId,
                })
            end)
            BountyInfo[closestBounty.id].dragger = nil
        else
            BBBroadcast("pickle_bailbounty:setBountyState", closestBounty.id, {
                type = "putBountyInVehicle",
                source = source,
                currentVehicle = netId,
            })
        end
        BountyInfo[closestBounty.id].currentVehicle = netId

    else
        dprint("FAILED TO PUT IN / OUT VEHICLE")
    end
end)

RegisterNetEvent("pickle_bailbounty:removeBounty", function(target)
    local permissions = GetPlayerPermissions(source)
    if not permissions.bailManage then
        return ShowNotification(source, _L("no_permission_bailmanage"))
    end
    local bounty = BountyRegistry[target]
    if not bounty then return ShowNotification(source, _L("bounty_not_exist")) end
    if string.sub(target, 1, 4) == "npc:" then return ShowNotification(source, _L("bounty_remove_is_npc")) end
    ShowNotification(source, _L("bounty_canceled", bounty.targetname))
    RemoveBountyFromRegistry(target, false, true)
end)

RegisterNetEvent("pickle_bailbounty:acceptBounty", function(target)
    local source = source
    local target = target
    if target == nil then -- TODO: REMOVE THIS WHEN DONE
        for k,v in pairs(BountyRegistry) do
            target = k
            break
        end
        if target == nil then
            return ShowNotification(source, _L("bounty_not_exist"))
        end
    end
    local permissions = GetPlayerPermissions(source)
    if not BountyHunters[source] then
        return ShowNotification(source, _L("no_permission_bounty"))
    end
    local bounty = BountyRegistry[target]
    if not bounty then return ShowNotification(source, _L("bounty_not_exist")) end
    if bounty.bountyHunter or GetPlayerCurrentBounty(source) then return end
    ShowNotification(source, _L("bounty_accepted", bounty.targetname))
    bounty.bountyHunter = source
    bounty.acceptedAt=os.time()
    bounty.hunterIdentifier=GetIdentifier(source)
    if bounty.npc then
        local loc=Config.NPCBounties.locations[math.random(1,#Config.NPCBounties.locations)]
        local entity=CreatePed(4,joaat(bounty.npc.model),loc.coords.x,loc.coords.y,loc.coords.z,loc.heading,true,true)
        if entity==0 then bounty.bountyHunter=nil; return end
        SetEntityRoutingBucket(entity,GetPlayerRoutingBucket(source))
        bounty.npc.netId=NetworkGetNetworkIdFromEntity(entity)
        bounty.npc.location=loc
        bounty.npc.entity=entity
    end
    UpdateBounty(target, bounty)
    if not bounty.npc then
        BountyInfo[target] = {
            source = bounty.source,
            currentVehicle = nil,
            isDetained = false,
            dragger = nil,
        }
        BBBroadcast("pickle_bailbounty:setBountyState", target, {
            type = "registerBountyTarget",
            source = bounty.source,
        })
    end
    TriggerClientEvent("pickle_bailbounty:acceptBounty", source, target)
end)

RegisterNetEvent("pickle_bailbounty:cancelCurrentBounty", function(fail)
    local source = source
    local currentBountyId, currentBounty = GetPlayerCurrentBounty(source)
    if not currentBounty then return ShowNotification(source, _L("no_current_bounty")) end
    if not fail then
        ShowNotification(source, _L("bounty_canceled", currentBounty.targetname))
    end
    CancelBounty(currentBountyId)
end)

RegisterNetEvent("pickle_bailbounty:addPlayerToBounty", function(data)
    local source = source
    local permissions = GetPlayerPermissions(source)
    if not permissions.bailPlacement then
        return ShowNotification(source, _L("no_permission_bailplace"))
    end
    if not BBValidData(source,data,false) then return end
    local target = GetIdentifier(data.source)
    if not target or BountyRegistry[target] then return end
    local bounty = {
        target = target,
        targetname = GetPlayerCharacterName(data.source),
        image = data.image,
        issuer = GetIdentifier(source),
        reward = data.reward or 0,
        description = _L("bounty_wanted"),
        datetime = os.time(),
        risk = 3,
        sentence = data.sentence or 0,
    }
    AddBountyToRegistry(bounty, false, true)
    ShowNotification(source, _L("bail_place_title"))
end)

RegisterNetEvent("pickle_bailbounty:takeCustody", function(identifier) 
    local source = source
    local permissions = GetPlayerPermissions(source)
    if not permissions.bailManage and not permissions.bailPlacement then
        return ShowNotification(source, _L("no_permission_bailmanage"))
    end
    local bounty = BountyRegistry[identifier]
    local bountyInfo = BountyInfo[identifier]
    if not bounty or not bountyInfo then return ShowNotification(source, _L("bounty_not_exist")) end
    if not bounty.bountyHunter then return ShowNotification(source, _L("bounty_not_accepted")) end
    if bounty.npc then return ShowNotification(source, _L("bounty_npc")) end
    if not BBNear(source,bounty.source,5) or not BBAt(source,Config.Bail.paroleOfficers,15) then return end
    if not bountyInfo.isDetained then return ShowNotification(source, _L("bounty_needs_detained")) end
    ShowNotification(source, _L("bounty_released"))
    CompleteBounty(identifier, source, false, true)
end)

RegisterNetEvent("pickle_bailbounty:toggleDuty", function()
    local source = source
    local permissions = GetPlayerPermissions(source)
    if BountyHunters[source] then
        local currentBountyId, currentBounty = GetPlayerCurrentBounty(source)
        if currentBounty then
            CancelBounty(currentBountyId)
        end
        local issuedLoadout=BountyHunters[source].issued
        BountyHunters[source] = nil
        ShowNotification(source, _L("bountyhunter_off"))
        for _,issued in ipairs(issuedLoadout or {}) do
            local fn=issued.kind=='weapon' and Inventory.RemoveWeapon or Inventory.RemoveItem
            fn(source,issued.name,issued.count)
        end
        DeleteResourceKvp('issued:'..GetIdentifier(source))
    else
        if not permissions.bountyHunter then return ShowNotification(source, _L("no_permission_bounty")) end
        if not BBAt(source,Config.BountyHunters.dutyLocations,10) then return end
        BBRecover(source)
        BountyHunters[source] = {
            name = GetPlayerCharacterName(source),
            clockedIn = os.time(),
            identifier=GetIdentifier(source),
            issued={},
        }
        ShowNotification(source, _L("bountyhunter_on"))
        for _,item in ipairs(Config.BountyHunters.loadout) do
            local weapon=item.loadoutType=='weapon'
            local has=weapon and Inventory.HasWeapon(source,item.name) or Inventory.GetItemCount(source,item.name)>0
            if not has then
                local grant=weapon and Inventory.AddWeapon or Inventory.AddItem
                if grant(source,item.name,item.count or 1)==true then
                    table.insert(BountyHunters[source].issued,{name=item.name,count=item.count or 1,kind=item.loadoutType})
                    SetResourceKvp('issued:'..GetIdentifier(source),json.encode(BountyHunters[source].issued))
                end
            end
        end
    end
    TriggerClientEvent("pickle_bailbounty:dutyState", source, BountyHunters[source])
end)

CreateThread(function()
    if not Config.PlayerBounties.blip.enabled then return end
    while true do
        for k,v in pairs(BountyInfo) do 
            if v.source then
                local bounty = BountyRegistry[k]
                if bounty and bounty.bountyHunter then
                    local ped = GetPlayerPed(v.source)
                    TriggerClientEvent("pickle_bailbounty:refreshBountyPosition", bounty.bountyHunter, {
                        id = k,
                        coords = GetEntityCoords(ped),
                    })
                end
            end
        end
        Wait((Config.PlayerBounties.blip.refreshTime or 10) * 1000)
    end
end)

CreateThread(function()
    for i=1, Config.NPCBounties.maxNPCBounties do
        GenerateNPCBounty(false)
    end
end)

AddEventHandler("playerDropped", function()
    local source = source
    local identifier = GetIdentifier(source)
    local currentBountyId, currentBounty = GetPlayerCurrentBounty(source)
    if currentBounty then
        currentBounty.bountyHunter = nil
        UpdateBounty(currentBountyId, currentBounty)
    end
    local bounty = BountyRegistry[identifier]
    if bounty then
        bounty.bountyHunter = nil
        bounty.source = nil
        UpdateBounty(identifier, bounty)
    end
    BountyHunters[source] = nil
end)
CreateThread(function()
    while true do
        Wait(10000)
        for id,b in pairs(BountyRegistry) do
            if b.bountyHunter and (os.time()-(b.acceptedAt or 0)>1800 or b.hunterIdentifier~=GetIdentifier(b.bountyHunter)) then CancelBounty(id) end
        end
    end
end)
