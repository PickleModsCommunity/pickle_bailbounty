local display = false
LOCAL_IDENTIFIER = "NULL"
LOCAL_PERMISSIONS = {}

function SetAppDisplay(bool)
    display = bool
    if display then
        TriggerScreenblurFadeIn(200)
        SetNuiFocus(true, true)
    else
        TriggerScreenblurFadeOut(200)
        SetNuiFocus(false, false)
    end
    SendNUIMessage({
        type = "setAppDisplay",
        data = display
    })
end

RegisterNetEvent("pickle_bailbounty:onRestart", function()
    TriggerServerEvent("pickle_bailbounty:initializePlayer")
end)

RegisterNUICallback("requestConfig", function(data, cb)
    cb({
        type = "setConfig",
        locale = Language[Config.Language],
        currency = {
            name = "USD",
            locale = "en-US"
        },
        permissions = LOCAL_PERMISSIONS,
        bailOfficers = Config.BailOfficers,
        defaultPlayerImage = "https://www.shutterstock.com/image-vector/silhouette-people-unknown-male-person-260nw-1372192277.jpg",
    })
end)

function GetAppSections()
    local sections = {}
    if CurrentBounty then
        table.insert(sections, {
            name = "current_bounty",
            label = _L("header_current_bounty"),
            show = true,
        })
    else
        if LOCAL_PERMISSIONS.bailManage or LOCAL_ON_DUTY then
            table.insert(sections, {
                name = "bounty",
                label = _L("header_bounty"),
                show = CurrentBounty and true or false,
            })
        end
        if LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement then
            table.insert(sections, {
                name = "bail",
                label = _L("header_bail"),
                show = true,
            })
        end
    end
    return sections
end

function UpdatePermissions(permissions)
    LOCAL_PERMISSIONS = permissions
    SendNUIMessage({
        type = "updatePermissions",
        permissions = {
            bountyHunter = permissions.bountyHunter or false,
            bailManage = permissions.bailManage or false,
            bailPlacement = permissions.bailPlacement or false,
        }
    })
    SendNUIMessage({
        type = "setSections",
        sections = GetAppSections()
    })
end

RegisterNetEvent("pickle_bailbounty:initializePlayer", function(data)
    -- Resynchronize identity and permissions on every character initialization.
    initializedPlayer = true
    LOCAL_IDENTIFIER = data.identifier
    LOCAL_PERMISSIONS = data.permissions
    UpdatePermissions(data.permissions)
    UpdateBounties(data.bounties)
    UpdateBailRegistry(data.bailRegistry)
end)

RegisterNetEvent("pickle_bailbounty:resyncPermissions", function(permissions)
    LOCAL_PERMISSIONS = permissions
    UpdatePermissions(permissions)
end)

RegisterNUICallback("getPlayers", function(data, cb)
    ServerCallback("pickle_bailbounty:getPlayers", function(players)
        cb({players = players})
    end, true)
end)

RegisterNUICallback("closeApp", function(data, cb)
    SetAppDisplay(false)
    cb("ok")
end)

RegisterCommand("bounties", function()
    if display then return end
    if LOCAL_ON_DUTY or LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement then
        SetAppDisplay(true)
    else
        ShowNotification(_L("no_permission_access"))
    end
end)

RegisterCommand("bail", function()
    if display then return end
    if LOCAL_ON_DUTY or LOCAL_PERMISSIONS.bailManage or LOCAL_PERMISSIONS.bailPlacement then
        SetAppDisplay(true)
    else
        ShowNotification(_L("no_permission_access"))
    end
end)