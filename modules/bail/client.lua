BailRegistry = {}
local AttachedBailObjects = {}
local BailPlayers = {}

function BailRegistryToArray(bailRegistry)
    local bailRegistryArray = {}
    for k,v in pairs(bailRegistry) do
        table.insert(bailRegistryArray, {
            id = v.identifier,
            image = v.image,
            name = v.name,
            reward = v.reward,
            description = v.description,
            issuer = v.issuer,
            status = v.status,
            startdate = v.startdate,
            completiondate = v.completiondate,
            lastcompliance = v.lastcompliance
        })
    end
    return bailRegistryArray
end

function UpdateBailRegistry(bailRegistry)
    BailRegistry = bailRegistry
    SendNUIMessage({
        type = "updateBailRegistry",
        bailRegistry = BailRegistryToArray(bailRegistry)
    })
end

function PlayersToOptions(players)
    local options = {}
    for k,v in pairs(players) do
        table.insert(options, {label = v.name, value = v.source or v.identifier})
    end
    return options
end

function OpenBailRegistrationMenu(players)
    if #players == 0 then
        ShowNotification(_L("no_player_near"))
        return
    end
    local playerOptions = PlayersToOptions(players)
    local input = lib.inputDialog(_L("bail_place_title"), {
        {type = 'select', label = _L("bail_place_player"), description = 'Some input description', required = true, options = playerOptions, default = players[1].source},
        {type = 'input', label = _L("bail_place_image"), placeholder = _L("bail_place_image_placeholder"), required = true},
        {type = 'slider', label = _L("bail_place_penalty"), min = 0, max = Config.BailOfficers.maximumBailAmount, default = math.floor(Config.BailOfficers.maximumBailAmount / 2), required = true},
        {type = 'slider', label = _L("bail_place_length"), min = 1, max = Config.BailOfficers.maximumBailLength, default = 1, required = true},
        {type = 'input', label = _L("bounty_sentence_nc"), default = "0", required = true},
        {type = 'textarea', label = _L("bail_place_description"), placeholder = _L("bail_place_description_placeholder"), required = true},
    })
    if not input then return end
    TriggerServerEvent("pickle_bailbounty:placeBail", {
        source = input[1],
        image = input[2],
        penalty = input[3],
        length = input[4],
        sentence = tonumber(input[5]) or 0,
        description = input[6],
    })
end

function OpenBailRegistrationMenuQuery()
    ServerCallback("pickle_bailbounty:getPermissions", function(permissions, extraData)
        if permissions.bailPlacement then
            OpenBailRegistrationMenu(extraData.nearbyPlayers or {})
        else
            ShowNotification(_L("no_permission_bailplace"))
        end
    end, {["nearbyPlayers"] = true})
end

local paroleMenuOpen = false
local ParoleMissionState = nil

function GenerateRandomParoleMission(index)
    local mission = Config.Bail.paroleMissions[index]
    return {
        label = mission.label,
        blip = mission.blip,
        description = mission.description,
        pointAction  = mission.pointAction,
        pointsRequired = (mission.pointsRequired > #mission.points and #mission.points or mission.pointsRequired),
        points = mission.points,
        interactions = {},
        progress = 0,
    }
end

function StartParoleMission()
    local issued=promise.new()
    ServerCallback('pickle_bailbounty:beginParole',function(index) issued:resolve(index) end)
    local index=Citizen.Await(issued)
    if not index then return end
    ParoleMissionState = GenerateRandomParoleMission(index)
    for i=1, #ParoleMissionState.points do 
        ParoleMissionState.interactions[#ParoleMissionState.interactions + 1] = CreateInteraction({
            coords = ParoleMissionState.points[i].coords,
            zOffset = ParoleMissionState.points[i].zOffset or 0,
            heading = ParoleMissionState.points[i].heading,
            label = ParoleMissionState.points[i].label or (ParoleMissionState.pointLabel or "Parole Mission Point"),
            model = ParoleMissionState.points[i].model,
        }, function()
            local state=ParoleMissionState
            if not state then return end
            if state.pointAction(state.points[i]) and ParoleMissionState==state then
                TriggerServerEvent('pickle_bailbounty:parolePoint',i)
                ParoleMissionState.progress = ParoleMissionState.progress + 1
                DeleteInteraction(ParoleMissionState.interactions[i])
                ParoleMissionState.interactions[i] = nil
                if ParoleMissionState.progress == ParoleMissionState.pointsRequired then
                    if ParoleMissionState.blip then
                        RemoveBlip(ParoleMissionState.blip)
                    end                    
                    if ParoleMissionState.radiusBlip then
                        RemoveBlip(ParoleMissionState.radiusBlip)
                    end
                    for _,interaction in pairs(ParoleMissionState.interactions) do DeleteInteraction(interaction) end
                    ParoleMissionState = nil
                    ShowNotification(_L("parole_officer_checkedin"))
                    ShowNotification(_L("parole_officer_checkedin_desc"))
                    TriggerServerEvent("pickle_bailbounty:completeParoleCheckin")
                end
            end
        end)
    end
    if ParoleMissionState.blip then
        local blip, radiusBlip = CreateBlip(ParoleMissionState.blip)
        ParoleMissionState.blip = blip
        ParoleMissionState.radiusBlip = radiusBlip
    end
    CreateThread(function()
        while ParoleMissionState do
            SetTextFont(0)
            SetTextProportional(1)
            SetTextCentre(1)
            SetTextScale(0.0, 0.5)
            SetTextColour(255, 255, 255, 255)
            SetTextDropshadow(0, 0, 0, 0, 255)
            SetTextEdge(1, 0, 0, 0, 255)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString("~y~".. ParoleMissionState.label..":~w~ " .. string.format(ParoleMissionState.description, ParoleMissionState.progress, ParoleMissionState.pointsRequired))
            DrawText(0.5, 0.95)
            Wait(0)
        end
    end)
end

function ParoleOfficerMenu(bailInfo)
    local bail = BailRegistry[LOCAL_IDENTIFIER]
    if not bail then
        return ShowNotification(_L("not_on_bail"))
    end
    if paroleMenuOpen then
        return
    end
    paroleMenuOpen = true
    local options = {
        {
          title = _L("bail_registry_startdate"),
          description = bailInfo.startdate,
          icon = 'hand',
        },
        {
          title = _L("bail_registry_completiondate"),
          description = bailInfo.completiondate,
          icon = 'hand',
        },
    }
    if bailInfo.checkIn then
        table.insert(options, {
            title = _L("parole_officer_checkin"),
            description = _L("parole_officer_checkin_desc"),
            icon = 'hand',
            onSelect = function()
                paroleMenuOpen = false
                if ParoleMissionState then
                    return ShowNotification(_L("parole_officer_mission_active"))
                end
                StartParoleMission()
            end
        })
    else
        table.insert(options, {
            title = _L("parole_officer_checkedin"),
            description = _L("parole_officer_checkedin_desc"),
            icon = 'hand',
            disabled = true,
        })
    end
    lib.registerContext({
        id = 'parole_officer_main',
        title = _L("parole_officer_interact"),
        onExit = function()
            paroleMenuOpen = false
        end,
        options = options
    })
    lib.showContext('parole_officer_main')
end

function ParoleOfficerMenuQuery()
    ServerCallback("pickle_bailbounty:getBailInfo", function(bailInfo)
        if not bailInfo then
            return ShowNotification(_L("not_on_bail"))
        end
        ParoleOfficerMenu(bailInfo)
    end)
end

function EnsureBailObjectAttached(source)
    local player = GetPlayerFromServerId(source)
    local ped = GetPlayerPed(player)
    if AttachedBailObjects[source] then
        if not DoesEntityExist(ped) or not DoesEntityExist(AttachedBailObjects[source]) or not IsEntityAttachedToAnyPed(AttachedBailObjects[source]) then
            DeleteEntity(AttachedBailObjects[source])
            AttachedBailObjects[source] = nil
            return EnsureBailObjectAttached(source)
        end
    elseif IsPlayerInRange(source, true) then
        local coords = GetEntityCoords(ped)
        AttachedBailObjects[source] = CreateProp(Config.Bail.tracker.prop.model, coords.x, coords.y, coords.z, false, false, false)
        AttachEntityToEntity(AttachedBailObjects[source], ped, GetPedBoneIndex(ped, Config.Bail.tracker.prop.boneId), Config.Bail.tracker.prop.offset.x, Config.Bail.tracker.prop.offset.y, Config.Bail.tracker.prop.offset.z, Config.Bail.tracker.prop.rotation.x, Config.Bail.tracker.prop.rotation.y, Config.Bail.tracker.prop.rotation.z, false, false, false, false, 2, true)
    end
end

function IsPlayerInRange(source, allowSelf)
    local player = GetPlayerFromServerId(source)
    if (not allowSelf and player == PlayerId()) or not NetworkIsPlayerActive(player) then
        return false
    end
    return DoesEntityExist(GetPlayerPed(player))
end

function CreateRangedBlip(source, inRange)
    local bailPlayer = BailPlayers[source]
    local player = GetPlayerFromServerId(source)
    local ped = GetPlayerPed(player)
    local blip = (inRange and AddBlipForEntity(ped) or AddBlipForCoord(bailPlayer.coords.x, bailPlayer.coords.y, bailPlayer.coords.z))
    local blipCfg = Config.Bail.tracker.blip
    SetBlipSprite(blip, blipCfg.sprite or 1)
    SetBlipColour(blip, blipCfg.color or 1)
    SetBlipScale(blip, blipCfg.scale or 0.8)
    SetBlipCategory(blip, 1)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(blipCfg.label)
    EndTextCommandSetBlipName(blip)
    return blip
end

function AddBailPlayer(source, data)
    BailPlayers[source] = {coords = data.coords, name = data.name, entity = nil, inRange = false, blip = nil, paroleBlips = {}}
    if source == GetPlayerServerId(PlayerId()) then
        for i=1, #Config.Bail.paroleOfficers do 
            local paroleOfficer = Config.Bail.paroleOfficers[i]
            if paroleOfficer.blip.enabled then
                BailPlayers[source].paroleBlips[#BailPlayers[source].paroleBlips + 1] = CreateBlip({
                    coords = paroleOfficer.coords,
                    label = paroleOfficer.blip.label,
                    sprite = paroleOfficer.blip.sprite,
                    color = paroleOfficer.blip.color,
                    scale = paroleOfficer.blip.scale,
                })
            end
        end
    end
    if source ~= GetPlayerServerId(PlayerId()) and LOCAL_PERMISSIONS.bailPlacement then
        BailPlayers[source].inRange = IsPlayerInRange(source)
        BailPlayers[source].blip = CreateRangedBlip(source, BailPlayers[source].inRange)
        if BailPlayers[source].inRange then
            BailPlayers[source].entity = GetPlayerPed(GetPlayerFromServerId(source))
        end
    end
end

function RemoveBailPlayer(source)
    if not BailPlayers[source] then return end
    if BailPlayers[source].blip then
        RemoveBlip(BailPlayers[source].blip)
    end
    for i=1, #(BailPlayers[source].paroleBlips or {}) do 
        RemoveBlip(BailPlayers[source].paroleBlips[i])
    end
    BailPlayers[source] = nil
end

function UpdateBailPlayer(source, data)
    BailPlayers[source].coords = data.coords
    BailPlayers[source].name = data.name
    local inRange = IsPlayerInRange(source)
    if source ~= GetPlayerServerId(PlayerId()) and LOCAL_PERMISSIONS.bailPlacement then
        if (BailPlayers[source].inRange and not inRange) or (not BailPlayers[source].inRange and inRange) then
            RemoveBlip(BailPlayers[source].blip)
            BailPlayers[source].blip = nil
            BailPlayers[source].entity = nil
            BailPlayers[source].inRange = inRange
        elseif BailPlayers[source].blip then
            if BailPlayers[source].inRange then
                if not DoesEntityExist(BailPlayers[source].entity) then
                    RemoveBlip(BailPlayers[source].blip)
                    BailPlayers[source].blip = nil
                    BailPlayers[source].entity = nil
                end
            else
                SetBlipCoords(BailPlayers[source].blip, data.coords.x, data.coords.y, data.coords.z)
            end
        end
        if not BailPlayers[source].blip then
            BailPlayers[source].blip = CreateRangedBlip(source, BailPlayers[source].inRange)
            if BailPlayers[source].inRange then
                BailPlayers[source].entity = GetPlayerPed(GetPlayerFromServerId(source))
            end
        end
    end
    BailPlayers[source].inRange = inRange
end

RegisterNetEvent("pickle_bailbounty:resyncPermissions", function(permissions)
    if not permissions.bailPlacement then
        for k,v in pairs(BailPlayers) do
            if v.blip then
                RemoveBlip(v.blip)
            end
        end
    else
        for k,v in pairs(BailPlayers) do
            if not v.blip then
                v.blip = CreateRangedBlip(k, v.inRange)
            end
        end
    end
end)

RegisterNetEvent("pickle_bailbounty:addbail", function(identifier, bail)
    BailRegistry[identifier] = bail
    UpdateBailRegistry(BailRegistry)
end)

RegisterNetEvent("pickle_bailbounty:removebail", function(identifier, source)
    BailRegistry[identifier] = nil
    UpdateBailRegistry(BailRegistry)
    if source and AttachedBailObjects[source] then
        DeleteEntity(AttachedBailObjects[source])
        AttachedBailObjects[source] = nil
    end
end)

RegisterNetEvent("pickle_bailbounty:updatebail", function(identifier, bail)
    BailRegistry[identifier] = bail
    UpdateBailRegistry(BailRegistry)
end)

RegisterNetEvent("pickle_bailbounty:updateBailPlayers", function(players)
    for k,v in pairs(BailPlayers) do
        if not players[k] then
            RemoveBailPlayer(k)
        end
    end
    for k,v in pairs(players) do
        if not BailPlayers[k] then
            AddBailPlayer(k, v)
        else 
            UpdateBailPlayer(k, v)
        end
    end
end)

RegisterNetEvent("pickle_bailbounty:openRegisterBail", function()
    OpenBailRegistrationMenuQuery()
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        for k,v in pairs(AttachedBailObjects) do
            DeleteEntity(v)
        end
    end
end)

RegisterNUICallback("clearBail", function(data, cb)
    TriggerServerEvent("pickle_bailbounty:clearBail", data.bounty.id)
    cb(true)
end)

RegisterNUICallback("revokeBail", function(data, cb)
    TriggerServerEvent("pickle_bailbounty:revokeBail", data.bounty.id)
    cb(true)
end)

CreateThread(function()
    for k,v in pairs(Config.Bail.paroleOfficers) do 
        CreateInteraction({
            coords = vector3(v.coords.x, v.coords.y, v.coords.z),
            heading = v.heading,
            label = _L("parole_officer_interact"),
            model = v.model,
        }, function()
            ParoleOfficerMenuQuery()
        end)
    end
    while true do
        for k,v in pairs(BailRegistry) do
            if v.source then
                EnsureBailObjectAttached(v.source)
            end
        end
        Wait(1000)
    end
end)

if Config.Bail.tracker.removal.enabled then
    RegisterCommand(Config.Bail.tracker.removal.command, function()
        local bail = BailRegistry[LOCAL_IDENTIFIER]
        if not bail then
            return ShowNotification(_L("not_on_bail"))
        end
        local _, weapon = GetCurrentPedWeapon(PlayerPedId(), true)
        for i=1, #Config.Bail.tracker.removal.weapons do
            if GetHashKey(Config.Bail.tracker.removal.weapons[i]) == weapon then
                local ped = PlayerPedId()
                PlayAnim(ped, "random@domestic", "pickup_low", 8.0, -8.0, -1, 1, 0, 0, 0, 0)
                Wait(700)
                TriggerServerEvent("pickle_bailbounty:revokeBail", nil, true)
                SetTimeout(700, function()
                    ClearPedTasks(ped)
                end)
                return
            end
        end
        ShowNotification(_L("tracker_removal_fail_weapon"))
    end)
    RegisterNetEvent("pickle_bailbounty:trackerRemoved", function(data)
        Config.Bail.tracker.onTrackerRemoval.client(data)
    end)
end