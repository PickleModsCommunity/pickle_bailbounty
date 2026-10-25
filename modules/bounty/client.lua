local BountyInfo = {}
BountyRegistry = {}
DutyInteractions = {}
LOCAL_ON_DUTY = false
HIDE_INTERACTIONS = false

function BountiesToArray(bounties)
    local bountiesArray = {}

    for k, v in pairs(bounties) do
        table.insert(bountiesArray, {
            id = v.target,
            source = v.source,
            bountyHunter = v.bountyHunter,
            image = v.image,
            risk = v.risk,
            description = v.description,
            name = v.targetname,
            reward = v.reward,
            time = v.time,
            active = v.active,
            date = v.datetime
        })
    end

    return bountiesArray
end

function UpdateBounties(bounties)
    BountyRegistry = bounties
    SendNUIMessage({
        type = "updateBounties",
        bounties = BountiesToArray(bounties)
    })
end

function GetScenarioFromChances(chances)
    local rng = math.random(1, 100)
    local cumulativeChance = 0
    for scenario, chance in pairs(chances) do
        cumulativeChance = cumulativeChance + chance
        if rng <= cumulativeChance * 100 then
            return scenario
        end
    end
    return "fleeFoot" -- default scenario if none matched
end

function GetNPCScenarioFromRisk(risk)
    local riskCfg = Config.NPCBounties.riskLevels[risk]
    local chances = {
        firearmAttack = riskCfg.firearmAttack,
        meleeAttack = riskCfg.meleeAttack,
        fleeVehicle = riskCfg.fleeVehicle,
        fleeFoot = riskCfg.fleeFoot,
    }
    return GetScenarioFromChances(chances)
end

function PerformScenario(scenario)
    local id = CurrentBounty.id
    -- SetTimeout(1500, function()
    --     BountyInteract(id, "detain")
    -- end)
    if scenario == "fleeFoot" or (scenario == "fleeVehicle" and CurrentBounty.vehicle == nil) then
        while CurrentBounty and CurrentBounty.id == id and CurrentBounty.targetNPC do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local targetCoords = GetEntityCoords(CurrentBounty.targetNPC)
            local distance = #(playerCoords - targetCoords)
            if distance < 50.0 then
                RemoveBlip(CurrentBounty.targetBlip)
                CurrentBounty.targetBlip = nil
                RemoveBlip(CurrentBounty.targetRadius)
                CurrentBounty.targetRadius = nil
                TaskSmartFleePed(CurrentBounty.targetNPC, playerPed, 100.0, -1, false, false)
                ShowNotification(_L("bounty_fleeing", CurrentBounty.name))
                break
            end
            Wait(1000)
        end
    elseif scenario == "meleeAttack" then
        RemoveAllPedWeapons(CurrentBounty.targetNPC)
        while CurrentBounty and CurrentBounty.id == id and CurrentBounty.targetNPC do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local targetCoords = GetEntityCoords(CurrentBounty.targetNPC)
            local distance = #(playerCoords - targetCoords)
            if distance < 50.0 then
                RemoveBlip(CurrentBounty.targetBlip)
                CurrentBounty.targetBlip = nil
                RemoveBlip(CurrentBounty.targetRadius)
                CurrentBounty.targetRadius = nil
                TaskCombatPed(CurrentBounty.targetNPC, playerPed, 0, 16)
                break
            end
            Wait(1000)
        end
    elseif scenario == "firearmAttack" then
        RemoveAllPedWeapons(CurrentBounty.targetNPC)
        local weaponHash = Config.NPCBounties.weapons[#Config.NPCBounties.weapons > 1 and math.random(1, #Config.NPCBounties.weapons) or 1]
        GiveWeaponToPed(CurrentBounty.targetNPC, weaponHash, 999, false, true)
        while CurrentBounty and CurrentBounty.id == id and CurrentBounty.targetNPC do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local targetCoords = GetEntityCoords(CurrentBounty.targetNPC)
            local distance = #(playerCoords - targetCoords)
            if distance < 50.0 then
                RemoveBlip(CurrentBounty.targetBlip)
                CurrentBounty.targetBlip = nil
                RemoveBlip(CurrentBounty.targetRadius)
                CurrentBounty.targetRadius = nil
                TaskCombatPed(CurrentBounty.targetNPC, playerPed, 0, 16)
                break
            end
            Wait(1000)
        end
    elseif scenario == "fleeVehicle" then
        local vehicle = CurrentBounty.vehicle
        if vehicle and DoesEntityExist(vehicle) then
            ClearPedTasksImmediately(CurrentBounty.targetNPC)
            TaskEnterVehicle(CurrentBounty.targetNPC, vehicle, -1, -1, 2.0, 8, 0)
            local timeStopped = 0
            local drivingTime = 0
            local driving = false
            local stopped = false
            local leaveVehicle = false
            while CurrentBounty and CurrentBounty.id == id and CurrentBounty.targetNPC do
                if not driving and IsPedInAnyVehicle(CurrentBounty.targetNPC, false) then
                    ShowNotification(_L("bounty_fleeing_vehicle", CurrentBounty.name))
                    driving = true
                end
                if driving then
                    TaskVehicleDriveWander(CurrentBounty.targetNPC, vehicle, 10000.0, 786468)
                    if GetEntitySpeed(vehicle) < 1 then
                        stopped = true
                        timeStopped = timeStopped + 1
                        if timeStopped > Config.NPCBounties.maxStopTime then
                            leaveVehicle = true
                            break
                        end
                    elseif stopped then
                        stopped = false
                        drivingTime = 0
                        timeStopped = 0
                    end
                    drivingTime = drivingTime + 1
                    if drivingTime > Config.NPCBounties.maxDrivingTime then
                        leaveVehicle = true
                        break
                    end
                end
                Wait(1000)
            end
            if leaveVehicle then
                TaskLeaveVehicle(CurrentBounty.targetNPC, vehicle, 0)
                Wait(2000)
                local newScenario = GetScenarioFromChances(Config.NPCBounties.chaseScenarioChances)
                return PerformScenario(newScenario)
            end
        end
    end
end

function GetClosestVehicle()
    local pool = GetGamePool("CVehicle")
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestVehicle = nil
    local closestDistance = 9999.0
    for i=1, #pool do
        local vehicle = pool[i]
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(playerCoords - vehicleCoords)
        if distance < closestDistance then
            closestDistance = distance
            closestVehicle = vehicle
        end
    end
    return closestVehicle, closestDistance
end

function VehicleInteract()
    local vehicle,distance = GetClosestVehicle()
    if not vehicle or distance>5 or GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))<4 then return false end
    local netId = VehToNet(vehicle)
    if not netId then return false end
    if not IsVehicleSeatFree(vehicle, 2) then ShowNotification("no_back_seat") return false end
    TriggerServerEvent("pickle_bailbounty:vehicleInteract", netId)
    return true
end

function BountyInteract(identifier, interactType)
    local entity = PlayerPedId()
    local data = nil
    if interactType == "detain" then
        local info=BountyInfo[identifier]
        if not info then return end
        local ped=info.source and GetPlayerPed(GetPlayerFromServerId(info.source)) or (info.netId and NetToPed(info.netId))
        data = {
            coords = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.8, -1.5),
            heading = GetEntityHeading(entity),
        }
    end
    if interactType == "custody" then
        TriggerServerEvent("pickle_bailbounty:takeCustody", identifier)
        return
    end
    TriggerServerEvent("pickle_bailbounty:bountyInteract", identifier, interactType, data)
end

function ShowBountyTargetOptions(identifier)
    if not Config.UseTarget then return end
    local bountyInfo = BountyInfo[identifier]
    if not bountyInfo then return end
    local options = {}
    local enabledOptions = {}

    if not bountyInfo.isDetained then
        options[#options + 1] = { name = "detain", label = _L("bounty_interact_detain"), onSelect = function() BountyInteract(identifier, "detain") end }
        enabledOptions.detain = true
    else
        options[#options + 1] = { name = "drag", label = _L("bounty_interact_drag"), onSelect = function() BountyInteract(identifier, "drag") end }
        enabledOptions.drag = true
    end
    if bountyInfo.source and (LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement) then
        options[#options + 1] = { name = "custody", label = _L("bounty_interact_custody"), onSelect = function() BountyInteract(identifier, "custody") end }
        enabledOptions.custody = true
    end
    if bountyInfo.netId then
        AddTargetNetworkId(bountyInfo.netId, options)
    end
    return enabledOptions
end

function RemoveBountyTargetOptions(identifier)
    if not Config.UseTarget then return end
    local bountyInfo = BountyInfo[identifier]
    if not bountyInfo then return end
    local options = {
        { name = "detain", label = _L("bounty_interact_detain") },
        { name = "drag", label = _L("bounty_interact_drag") },
        { name = "vehicle", label = _L("bounty_interact_vehicle") },
        { name = "custody", label = _L("bounty_interact_custody") },
    }
    if bountyInfo.netId then
        RemoveTargetNetworkId(bountyInfo.netId, options)
    end
end

function ShowBountyTargetMenu(identifier)
    local bounty = BountyRegistry[identifier]
    local bountyInfo = BountyInfo[identifier]
    if not bounty or not bountyInfo then return end
    local options = {}
    HIDE_INTERACTIONS = true
    if not bountyInfo.isDetained then
        options[#options + 1] = { name = "detain", title = _L("bounty_interact_detain"), onSelect = function() HIDE_INTERACTIONS = false; BountyInteract(identifier, "detain") end }
    else
        options[#options + 1] = { name = "drag", title = _L("bounty_interact_drag"), onSelect = function() HIDE_INTERACTIONS = false; BountyInteract(identifier, "drag") end }
        options[#options + 1] = { name = "vehicle", title = _L("bounty_interact_vehicle"), close = false, onSelect = function() 
            if not VehicleInteract() then
                return ShowNotification(_L("bounty_no_vehicle"))
            end
            HIDE_INTERACTIONS = false
            lib.hideContext()
        end}
    end
    if bountyInfo.source and (LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement) then
        options[#options + 1] = { name = "custody", title = _L("bounty_interact_custody"), onSelect = function() HIDE_INTERACTIONS = false; BountyInteract(identifier, "custody") end }
    end
    local menuId = "bounty_target_menu"
    lib.registerContext({
        id = menuId,
        title = _L("bounty_target_menu", bounty.targetname),
        options = options,
        onExit = function()
            HIDE_INTERACTIONS = false
        end
    })
    lib.showContext(menuId)
end

function CancelCurrentBounty()
    if not CurrentBounty then return end
    if CurrentBounty.targetBlip then
        RemoveBlip(CurrentBounty.targetBlip)
    end
    if CurrentBounty.targetRadius then
        RemoveBlip(CurrentBounty.targetRadius)
    end
    if CurrentBounty.targetNPC then 
        -- Handled sv-side
    end
    if CurrentBounty.vehicle then
        local targetVeh = CurrentBounty.vehicle
        SetTimeout(5000, function()
            DeleteEntity(targetVeh)
        end)
    end
    CurrentBounty = nil
    SendNUIMessage({
        type = "updateBounty",
        bounty = CurrentBounty
    })
    SendNUIMessage({
        type = "setSections",
        sections = GetAppSections()
    })
end

function RenderDutyLocations()
    for i=1, #DutyInteractions do
        RemoveBlip(DutyInteractions[i].blip)
        DeleteInteraction(DutyInteractions[i].interact)
        DutyInteractions[i] = nil
    end
    DutyInteractions = {}
    for k,v in pairs(Config.BountyHunters.dutyLocations) do 
        local blip = nil
        if v.blip then 
            local blipCfg = Config.BountyHunters.blip
            blip = CreateBlip({
                coords = v.coords,
                label = blipCfg.label,
                sprite = blipCfg.sprite,
                color = blipCfg.color,
                scale = blipCfg.scale,
            })
        end
        DutyInteractions[#DutyInteractions + 1] = {
            blip = blip,
            interact = CreateInteraction({
                coords = v.coords,
                heading = v.heading,
                model = v.model,
                label = _L("bounty_interact_duty_" .. (LOCAL_ON_DUTY and "off" or "on")),
            }, function()
                TriggerServerEvent("pickle_bailbounty:toggleDuty")
            end)
        }
    end
end

RegisterNetEvent('pickle_bailbounty:addBounty', function(identifier, data)
    BountyRegistry[identifier] = data
    UpdateBounties(BountyRegistry)
end)

RegisterNetEvent("pickle_bailbounty:removeBounty", function(identifier)
    BountyRegistry[identifier] = nil
    UpdateBounties(BountyRegistry)
end)

RegisterNetEvent("pickle_bailbounty:updateBounty", function(identifier, data)
    BountyRegistry[identifier] = data
    UpdateBounties(BountyRegistry)
end)

RegisterNetEvent("pickle_bailbounty:setBountyState", function(identifier, data)
    if data.type == "registerBountyTarget" then
        BountyInfo[identifier] = {
            source = data.source,
            netId = data.netId,
            currentVehicle = nil,
            isDetained = false,
            dragger = data.dragger or nil,
        }
        if LOCAL_ON_DUTY then
            ShowBountyTargetOptions(identifier)
        end
        if LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement then
            ShowBountyTargetOptions(identifier, true)
        end
    elseif data.type == "removeBountyTarget" then
        if BountyInfo[identifier] then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                DetachEntity(ped, true, true)
                ClearPedTasks(ped)
                PlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, 0, 0, 0)
            end
            if BountyInfo[identifier].dragger and BountyInfo[identifier].dragger == GetPlayerServerId(PlayerId()) then
                ClearPedTasks(PlayerPedId())
            end
            if BountyInfo[identifier].source == GetPlayerServerId(PlayerId()) then
                DetachEntity(PlayerPedId(), true, true)
                ClearPedTasks(PlayerPedId())
            end
        end
        RemoveBountyTargetOptions(identifier)
        BountyInfo[identifier] = nil
        if CurrentBounty and CurrentBounty.id == identifier then
            CancelCurrentBounty()
        end
    elseif data.type == "detainBountyTarget" then
        BountyInfo[identifier].isDetained = true
        if data.source == GetPlayerServerId(PlayerId()) then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                if not NetworkHasControlOfEntity(ped) then
                    NetworkRequestControlOfEntity(ped)
                    local timeout = 500
                    while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                        Wait(100)
                        timeout = timeout - 100
                    end
                end
            end
            SetEntityHeading(PlayerPedId(), data.heading)
            FreezeEntityPosition(PlayerPedId(), true)
            PlayAnim(PlayerPedId(), "mp_arrest_paired", "cop_p2_back_left", 8.0, -8.0, 5500, 33, 0, false, false, false)
            SetTimeout(5000, function()
                FreezeEntityPosition(PlayerPedId(), false)
                ShowNotification(_L("bounty_detained"))
            end)
        end
        if BountyInfo[identifier].netId then
            local ped = NetToPed(BountyInfo[identifier].netId)
            if not NetworkHasControlOfEntity(ped) then
                NetworkRequestControlOfEntity(ped)
                local timeout = 500
                while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                    Wait(100)
                    timeout = timeout - 100
                end
            end
            if ped then
                ClearPedTasksImmediately(ped)
                PlayAnim(ped, "mp_arrest_paired", "crook_p2_back_left", 8.0, -8.0, 5500, 33, 0, false, false, false)
                SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z + 0.5)
                SetEntityHeading(ped, data.heading)

                SetEnableHandcuffs(ped, true)
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true) -- unarm player
                SetPedCanPlayGestureAnims(ped, false)
                FreezeEntityPosition(ped, true)
            end
            SetTimeout(5000, function()
                FreezeEntityPosition(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                CreateThread(function()
                    while ped and DoesEntityExist(ped) and BountyInfo[identifier] and BountyInfo[identifier].isDetained do
                        if not IsEntityPlayingAnim(ped, "mp_arresting", "idle", 3) then
                            ClearPedTasks(ped)
                            PlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, 0, 0, 0)
                            Wait(100)
                        end
                        Wait(1000)
                    end
                end)
            end)
        elseif BountyInfo[identifier].source == GetPlayerServerId(PlayerId()) then
            local ped = PlayerPedId()
            SetEntityCoords(ped, data.coords.x, data.coords.y, data.coords.z + 0.5)
            SetEntityHeading(ped, data.heading)
            SetEnableHandcuffs(ped, true)
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true) -- unarm player
            PlayAnim(ped, "mp_arrest_paired", "crook_p2_back_left", 8.0, -8.0, 5500, 33, 1.0, false, false, false)
            SetTimeout(5000, function()
                CreateThread(function()
                    while BountyInfo[identifier] and BountyInfo[identifier].isDetained do
                        local ped = PlayerPedId()
                        if not IsEntityPlayingAnim(ped, "mp_arresting", "idle", 3) then
                            ClearPedTasks(ped)
                            PlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, 0, 0, 0)
                        end
                        DisableControlAction(0, 22, true) 
                        DisableControlAction(0, 23, true) 
                        DisableControlAction(0, 24, true)
                        DisableControlAction(0, 25, true) 
                        DisableControlAction(0, 30, true) 
                        DisableControlAction(0, 31, true) 
                        DisableControlAction(0, 32, true) 
                        DisableControlAction(0, 34, true) 
                        DisableControlAction(0, 36, true) 
                        DisableControlAction(0, 44, true) 
                        DisableControlAction(0, 45, true) 
                        DisableControlAction(0, 47, true) 
                        DisableControlAction(0, 75, true)  
                        DisableControlAction(0, 140, true) 
                        DisableControlAction(0, 141, true) 
                        DisableControlAction(0, 142, true) 
                        DisableControlAction(0, 143, true) 
                        DisableControlAction(0, 257, true) 
                        DisableControlAction(0, 263, true) 
                        DisableControlAction(0, 264, true) 
                        DisableControlAction(0, 289, true) 
                        Wait(0)
                    end
                    ClearPedTasksImmediately(PlayerPedId())
                    SetEnableHandcuffs(PlayerPedId(), false)
                end)
            end)
        end
        if LOCAL_ON_DUTY then
            ShowBountyTargetOptions(identifier)
        end
    elseif data.type == "dragBountyTarget" then
        BountyInfo[identifier].dragger = data.source
        local playerPed = PlayerPedId()
        local serverId = GetPlayerServerId(PlayerId())
        if data.source == serverId then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                if not NetworkHasControlOfEntity(ped) then
                    NetworkRequestControlOfEntity(ped)
                    local timeout = 500
                    while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                        Wait(100)
                        timeout = timeout - 100
                    end
                end
                if ped and NetworkHasControlOfEntity(ped) then
                    CreateThread(function()
                        local sourcePed = PlayerPedId()
                        local boneIndex = GetPedBoneIndex(sourcePed, 0x60F2)
                        local coords, rot = vector3(-0.25, 0.24, -0.5), vector3(0.0, 90.0, 0.0)
                        AttachEntityToEntity(ped, sourcePed, boneIndex, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, 0, 0, 0, 1, 2, 1)
                        local moving = false
                        while ped and DoesEntityExist(ped) and BountyInfo[identifier] and BountyInfo[identifier].dragger and BountyInfo[identifier].dragger == serverId do
                            sourcePed = PlayerPedId()
                            if IsPedWalking(sourcePed) then
                                if not IsEntityPlayingAnim(ped, 'move_action@generic@core', 'walk', 3) then 
                                    moving = true
                                    PlayAnim(ped, 'move_action@generic@core', 'walk', 8.0, -8.0, -1, 1, 0, false, false, false)
                                end
                            elseif IsPedSprinting(sourcePed) or IsPedRunning(sourcePed) then
                                if not IsEntityPlayingAnim(ped, 'move_action@generic@core', 'run', 3) then 
                                    moving = true
                                    PlayAnim(ped, 'move_action@generic@core', 'run', 8.0, -8.0, -1, 1, 0, false, false, false)
                                end
                            elseif moving then
                                moving = false
                                ClearPedTasks(ped)
                                PlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, 0, 0, 0)
                            end
                            Wait(0)
                        end
                    end)
                end
            end
            CreateThread(function()
                local animLoop = true
                local bounty = BountyRegistry[identifier]
                HIDE_INTERACTIONS = true
                while BountyRegistry[identifier] and BountyInfo[identifier] and BountyInfo[identifier].dragger and BountyInfo[identifier].dragger == serverId  do
                    local playerPed = PlayerPedId()
                    local playerCoords = GetEntityCoords(playerPed)
                    if animLoop and not IsEntityPlayingAnim(playerPed, 'missfbi4prepp1', 'idle', 3) then 
                        PlayAnim(playerPed, 'missfbi4prepp1', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
                        animLoop = false
                        SetTimeout(1000, function()
                            animLoop = true
                        end)
                    end
                    local nearestCell = {}
                    for i=1, #Config.BountyHunters.cellLocations do 
                        local cellCoords = Config.BountyHunters.cellLocations[i].coords
                        local distance = #(playerCoords - cellCoords)
                        if distance < Config.RenderDistance and (not nearestCell.distance or distance < nearestCell.distance) then
                            nearestCell = {
                                coords = cellCoords,
                                distance = distance,
                                inside = (distance < 3.0),
                            }
                        end
                    end
                    if nearestCell.inside then
                        ShowInteractText("[E] - " .. _L("release_bounty", NumberWithCommas(bounty.reward)))
                        if IsControlJustPressed(0, 51) then
                            BountyInteract(identifier, "completeBountyTarget")
                            break
                        end
                    else
                        ShowInteractText("[E] - " .. _L("stop_dragging"))
                        if IsControlJustPressed(0, 51) then
                            BountyInteract(identifier, "stopDragging")
                            break
                        end
                    end
                    Wait(0)
                end
                HIDE_INTERACTIONS = false
            end)
        end
        if BountyInfo[identifier].source == serverId then
            CreateThread(function()
                local ped = PlayerPedId()
                local sourcePed = GetPlayerPed(GetPlayerFromServerId(data.source))
                local boneIndex = GetPedBoneIndex(sourcePed, 0x60F2)
                local coords, rot = vector3(-0.25, 0.24, -0.5), vector3(0.0, 90.0, 0.0)
                AttachEntityToEntity(ped, sourcePed, boneIndex, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, 0, 0, 0, 1, 2, 1)
                local moving = false
                while BountyInfo[identifier] and BountyInfo[identifier].dragger and BountyInfo[identifier].dragger == data.source do
                    sourcePed = GetPlayerPed(GetPlayerFromServerId(data.source))
                    ped = PlayerPedId()
                    if IsPedWalking(sourcePed) then
                        if not IsEntityPlayingAnim(ped, 'move_action@generic@core', 'walk', 3) then 
                            moving = true
                            PlayAnim(ped, 'move_action@generic@core', 'walk', 8.0, -8.0, -1, 1, 0, false, false, false)
                        end
                    elseif IsPedSprinting(sourcePed) or IsPedRunning(sourcePed) then
                        if not IsEntityPlayingAnim(ped, 'move_action@generic@core', 'run', 3) then 
                            moving = true
                            PlayAnim(ped, 'move_action@generic@core', 'run', 8.0, -8.0, -1, 1, 0, false, false, false)
                        end
                    elseif moving then
                        moving = false
                        ClearPedTasks(ped)
                        PlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, 0, 0, 0)
                    end
                    Wait(0)
                end
                ClearPedTasksImmediately(PlayerPedId())
            end)
        end
    elseif data.type == "releaseBountyTarget" then
        BountyInfo[identifier].dragger = nil
        local playerPed = PlayerPedId()
        local serverId = GetPlayerServerId(PlayerId())
        if data.source == serverId then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                if not NetworkHasControlOfEntity(ped) then
                    NetworkRequestControlOfEntity(ped)
                    local timeout = 500
                    while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                        Wait(100)
                        timeout = timeout - 100
                    end
                end
                if ped and NetworkHasControlOfEntity(ped) then
                    DetachEntity(ped, true, true)
                    ClearPedTasks(ped)
                    FreezeEntityPosition(ped, true)
                end
            end
            ClearPedTasks(playerPed)
        end
        if BountyInfo[identifier].source == serverId then
            local ped = PlayerPedId()
            ClearPedTasks(ped)
            DetachEntity(ped, true, true)
        end
    elseif data.type == "putBountyInVehicle" then
        local playerPed = PlayerPedId()
        local serverId = GetPlayerServerId(PlayerId())
        if data.source == serverId then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                if not NetworkHasControlOfEntity(ped) then
                    NetworkRequestControlOfEntity(ped)
                    local timeout = 500
                    while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                        Wait(100)
                        timeout = timeout - 100
                    end
                end
                if ped and NetworkHasControlOfEntity(ped) then
                    local vehicle = NetToVeh(data.currentVehicle)
                    if vehicle then
                        FreezeEntityPosition(ped, false)
                        TaskWarpPedIntoVehicle(ped, vehicle, 2)
                    end
                end
            end
        end
        if BountyInfo[identifier].source == serverId then
            local ped = PlayerPedId()
            local vehicle = NetToVeh(data.currentVehicle)
            if vehicle then
                FreezeEntityPosition(ped, false)
                TaskWarpPedIntoVehicle(ped, vehicle, 2)
            end
        end
    elseif data.type == "removeBountyFromVehicle" then
        local playerPed = PlayerPedId()
        local serverId = GetPlayerServerId(PlayerId())
        if data.source == serverId then
            if BountyInfo[identifier].netId then
                local ped = NetToPed(BountyInfo[identifier].netId)
                if not NetworkHasControlOfEntity(ped) then
                    NetworkRequestControlOfEntity(ped)
                    local timeout = 500
                    while timeout > 0 and not NetworkHasControlOfEntity(ped) do
                        Wait(100)
                        timeout = timeout - 100
                    end
                end
                if ped then
                    ClearPedTasks(ped)
                    TaskLeaveVehicle(ped, NetToVeh(data.currentVehicle), 16)
                end
            end
        end
        if BountyInfo[identifier].source == serverId then
            local ped = PlayerPedId()
            ClearPedTasksImmediately(ped)
            TaskLeaveVehicle(ped, NetToVeh(data.currentVehicle), 16)
        end
    end
end)

RegisterNetEvent("pickle_bailbounty:acceptBounty", function(target)
    local bounty = BountyRegistry[target]

    CurrentBounty = {
        id = target,
        npc = bounty.npc,
        name = bounty.targetname,
        image = bounty.image,
        reward = bounty.reward,
        description = bounty.description,
        date = bounty.datetime or 0,
        risk = bounty.risk or (bounty.npc and bounty.npc.risk or 3),
    }
    SendNUIMessage({
        type = "updateBounty",
        bounty = CurrentBounty
    })
    SendNUIMessage({
        type = "setSections",
        sections = GetAppSections()
    })
    if CurrentBounty.npc then
        local locations = Config.NPCBounties.locations
        local location = CurrentBounty.npc.location
        local blipCfg = Config.NPCBounties.blip
        local rngOffset = {1, 100}
        local rngScale = (math.random(rngOffset[1], rngOffset[2]) / rngOffset[2]) * (blipCfg.radius.size / 2)
        local rngCoords = location.coords + vector3(
            (math.random(1, 2) == 1 and 1 or -1) * rngScale,
            (math.random(1, 2) == 1 and 1 or -1) * rngScale,
            0
        )
        local targetBlip, targetRadius = CreateBlip({
            coords = rngCoords,
            label = blipCfg.labelPrefix .." ".. CurrentBounty.name,
            category = 1,
            sprite = blipCfg.sprite,
            color = blipCfg.color,
            scale = blipCfg.scale,
            radius = blipCfg.radius,
        })
        CurrentBounty.targetBlip = targetBlip
        CurrentBounty.targetRadius = targetRadius
        local id = CurrentBounty.id
        local risk = CurrentBounty.risk
        local scenario = GetNPCScenarioFromRisk(risk)
        CurrentBounty.targetNPC = nil
        CreateThread(function()
            while CurrentBounty and CurrentBounty.id == id and not CurrentBounty.targetNPC do 
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)
                local distance = #(playerCoords - location.coords)
                if distance < 100.0 then
                    local missionNet=CurrentBounty.npc.netId
                    if not missionNet or not NetworkDoesNetworkIdExist(missionNet) then Wait(100); goto continueSpawn end
                    CurrentBounty.targetNPC=NetToPed(missionNet)
                    local netId = PedToNet(CurrentBounty.targetNPC)
                    if NetworkDoesNetworkIdExist(netId) then
                        SetTimeout(1000, function()
                            TriggerServerEvent("pickle_bailbounty:setCurrentBountyNPC", netId)
                        end)
                    end
                    if scenario == "fleeVehicle" then
                        local vehicleModel = Config.NPCBounties.vehicles[#Config.NPCBounties.vehicles > 1 and math.random(1, #Config.NPCBounties.vehicles) or 1]
                        local roadFound, roadCoords, roadHeading = GetClosestVehicleNodeWithHeading(location.coords.x, location.coords.y, location.coords.z, 0, 100.0, 100.0)
                        if roadFound and #(roadCoords - location.coords) < 100.0 then
                            CurrentBounty.vehicle = CreateVeh(vehicleModel, roadCoords.x, roadCoords.y, roadCoords.z, roadHeading, true, true)
                            SetVehicleEngineHealth(CurrentBounty.vehicle, 500.0)
                        end
                    end
                    break
                end
                ::continueSpawn::
                Wait(1000)
            end
            if not CurrentBounty or CurrentBounty.id ~= id or not CurrentBounty.targetNPC then
                CancelCurrentBounty()
                return
            end
            PerformScenario(scenario)                
        end)
    end
end)

RegisterNetEvent("pickle_bailbounty:dutyState", function(state)
    if LOCAL_ON_DUTY == state then return end
    LOCAL_ON_DUTY = state
    RenderDutyLocations()
    UpdatePermissions(LOCAL_PERMISSIONS)
    if not LOCAL_ON_DUTY then 
        ToggleOutfit(false)
        for k,v in pairs(BountyInfo) do 
            RemoveBountyTargetOptions(k)
        end
        if Config.UseTarget then
            RemoveTargetGlobalVehicle({{ name = "vehicle" }})
        end
        return
    else
        ToggleOutfit(true)
        for k,v in pairs(BountyInfo) do 
            ShowBountyTargetOptions(k)
        end
        if Config.UseTarget then
            AddTargetGlobalVehicle({{ name = "vehicle", label = _L("bounty_interact_vehicle"), onSelect = function() VehicleInteract() end }})
        end
    end
    CreateThread(function()
        local inVehicle = false
        local brakeTime = -1
        local showInteract = false
        while LOCAL_ON_DUTY do
            local wait = 1000
            if displayingText or (not inVehicle and IsPedInAnyVehicle(PlayerPedId(), false)) then
                inVehicle = true
            elseif inVehicle then
                local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                if not DoesEntityExist(vehicle) then
                    inVehicle = false
                    displayingText = false
                    brakeTime = -1
                else
                    wait = 0
                    if GetEntitySpeed(vehicle) < 1.0 and IsControlPressed(0, 22) then
                        brakeTime = brakeTime + 1
                    elseif brakeTime > 0 or brakeTime == -1 then
                        if brakeTime < 20 and brakeTime > 0 then
                            ExecuteCommand("bounties")
                        elseif brakeTime == -1 then
                            showInteract = true
                            SetTimeout(3000, function()
                                showInteract = false
                            end)
                        end
                        brakeTime = 0
                    end
                end
                if showInteract then
                    wait = 0
                    ShowInteractText(_L("bounty_vehicle_info"))
                end
            end
            Wait(wait)
        end
    end)
end)

RegisterNetEvent("pickle_bailbounty:refreshBountyPosition", function(data)
    local coords = data.coords
    if CurrentBounty and CurrentBounty.id == data.id then
        if BountyInfo[data.id] and BountyInfo[data.id].isDetained then
            if CurrentBounty.targetBlip or CurrentBounty.targetRadius then
                RemoveBlip(CurrentBounty.targetBlip)
                RemoveBlip(CurrentBounty.targetRadius)
                CurrentBounty.targetBlip = nil
                CurrentBounty.targetRadius = nil
            end
        else
            local blipCfg = Config.PlayerBounties.blip
            local rngOffset = {1, 100}
            local rngScale = (math.random(rngOffset[1], rngOffset[2]) / rngOffset[2]) * (blipCfg.radius.size / 2)
            local rngCoords = coords + vector3(
                (math.random(1, 2) == 1 and 1 or -1) * rngScale,
                (math.random(1, 2) == 1 and 1 or -1) * rngScale,
                0
            )
            if CurrentBounty.targetBlip and CurrentBounty.targetRadius then
                SetBlipCoords(CurrentBounty.targetBlip, rngCoords)
                SetBlipCoords(CurrentBounty.targetRadius, rngCoords)
            else
                RemoveBlip(CurrentBounty.targetBlip)
                RemoveBlip(CurrentBounty.targetRadius)
                local targetBlip, targetRadius = CreateBlip({
                    coords = rngCoords,
                    label = blipCfg.labelPrefix .." ".. CurrentBounty.name,
                    category = 1,
                    sprite = blipCfg.sprite,
                    color = blipCfg.color,
                    scale = blipCfg.scale,
                    radius = blipCfg.radius,
                })
                CurrentBounty.targetBlip = targetBlip
                CurrentBounty.targetRadius = targetRadius
            end
        end
    end
end)

RegisterNUICallback("addPlayerToBounty", function(data, cb)
    TriggerServerEvent("pickle_bailbounty:addPlayerToBounty", {
        source = data.player.source,
        identifier = data.player.identifier, 
        image = data.player.image, 
        reward = data.player.reward, 
        sentence = data.player.sentence,
    })
    cb(true)
end)

RegisterNUICallback("acceptBounty", function(data, cb)
    TriggerServerEvent("pickle_bailbounty:acceptBounty", data.bounty.id)
    cb(true)
end)

RegisterNUICallback("declineBounty", function(data, cb)
    TriggerServerEvent("pickle_bailbounty:removeBounty", data.bounty.id)
    cb(true)
end)

RegisterNUICallback("cancelCurrentBounty", function(data, cb)
    SendNUIMessage({
        type = "updateBounty",
        bounty = CurrentBounty
    })
    SendNUIMessage({
        type = "setSections",
        sections = GetAppSections()
    })
    TriggerServerEvent("pickle_bailbounty:cancelCurrentBounty")
    cb(true)
end)

CreateThread(function()
    if Config.UseTarget then return end
    while true do 
        local wait = 1000
        if LOCAL_ON_DUTY or (LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement) then
            local closestBounty = {}
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            for k,v in pairs(BountyInfo) do 
                local ped
                if v.netId and NetworkDoesNetworkIdExist(v.netId) then
                    ped = NetToPed(v.netId)
                    if not DoesEntityExist(ped) then
                        ped = nil
                    end
                elseif string.sub(k, 1, 4) ~= "npc:" then
                    local bounty = BountyRegistry[k]
                    if bounty and bounty.source and IsPlayerInRange(bounty.source, false) then
                        ped = GetPlayerPed(GetPlayerFromServerId(bounty.source))
                    end
                end
                if ped then
                    local coords = GetEntityCoords(ped)
                    local distance = #(playerCoords - coords)
                    if distance < 2 and (not closestBounty.distance or distance < closestBounty.distance) then
                        closestBounty = {
                            id = k,
                            distance = distance,
                            coords = coords,
                        }
                    end
                end
            end
            if closestBounty.id and not IsPedInAnyVehicle(playerPed, false) and not HIDE_INTERACTIONS then
                ShowInteractText("[E] - " .. _L("bounty_interact_target"))
                if IsControlJustPressed(0, 51) then
                    ShowBountyTargetMenu(closestBounty.id)
                end
                wait = 0
            end
        end
        Wait(wait)
    end    
end)

CreateThread(function()
    if Config.UseTarget then
        local onSelect = function(interactType, source)
            for k,v in pairs(BountyInfo) do
                if v.source == source then
                    local enabledOptions = ShowBountyTargetOptions(k)
                    if enabledOptions[interactType] then
                        BountyInteract(k, interactType)
                    end
                end
            end
        end
        local canInteract = function(interactType, source)
            for k,v in pairs(BountyInfo) do
                if v.source == source then
                    local enabledOptions = ShowBountyTargetOptions(k)
                    return (enabledOptions[interactType] or false)
                end
            end
        end
        AddTargetGlobalPlayer({
            { name = "detain", label = _L("bounty_interact_detain"), interactCheck = function(...) return canInteract("detain", ...) end, onSelected = function(...) onSelect("detain", ...) end },
            { name = "drag", label = _L("bounty_interact_drag"), interactCheck = function(...) return canInteract("drag", ...) end, onSelected = function(...) onSelect("drag", ...) end },
            { name = "custody", label = _L("bounty_interact_custody"), interactCheck = function(...) return canInteract("custody", ...) end, onSelected = function(...) onSelect("custody", ...) end }        
        })
    end
    local modifiers = {
        ["weapon_stungun"] = {},
        ["weapon_stungun_mp"] = {}
    }
    for k,v in pairs(modifiers) do
        v.default = GetWeaponDamageModifier(k)
        SetWeaponDamageModifier(k, 0.0)
    end
end)

CreateThread(function()
    local addBlip = function(coords)
        local blipCfg = Config.BountyHunters.blip
        local blip = CreateBlip({
            coords = coords,
            label = blipCfg.label,
            sprite = blipCfg.sprite,
            color = blipCfg.color,
            scale = blipCfg.scale,
        })
    end
    for k,v in pairs(Config.BountyHunters.cellLocations) do 
        if v.blip then addBlip(v.coords) end
    end
    RenderDutyLocations()
end)
