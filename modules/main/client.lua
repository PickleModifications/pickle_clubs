Clubs = {}
LocalClubs = {}
RegisteredEntityTypes = {}
CurrentCamera = nil

function CreateScriptedCamera()
    if CurrentCamera then ExitScriptedCamera() end
    local initialCamSettings = {
        coords = GetGameplayCamCoord(),
        rotation = GetGameplayCamRot(),
        fov = GetGameplayCamFov(),
    }
    CurrentCamera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", 
        initialCamSettings.coords.x, initialCamSettings.coords.y, initialCamSettings.coords.z, 
        initialCamSettings.rotation.x, initialCamSettings.rotation.y, initialCamSettings.rotation.z, initialCamSettings.fov
    )
    SetCamActive(CurrentCamera, true)
    RenderScriptCams(true, false, 0, true, true)
end

function ExitScriptedCamera(durationValue)
    local duration = durationValue
    if duration == nil then duration = 2000 end
    ClearFocus()
	DestroyAllCams()
    RenderScriptCams(false, true, duration, true, false) 
end


function RegisterClub(id, data)
    Clubs[id] = data
    local pcoords = GetEntityCoords(PlayerPedId())
    if #(pcoords - data.coords) < Config.RenderDistance then
        RenderClub(id)
    end
end

function UnregisterClub(id)
    UnrenderClub(id)
    Clubs[id] = nil
end

function RenderClub(id)
    UnrenderClub(id)
    local club = Clubs[id]
    if not club then return end
    LocalClubs[id] = {
        entities = {},
    }
    for k,v in pairs(club.entities) do
        LocalClubs[id].entities[k] = RenderClubEntity(id, k)
    end
end

function UnrenderClub(id)
    if not LocalClubs[id] then return end
    for k,v in pairs(LocalClubs[id].entities) do
        UnrenderClubEntity(id, k)
    end
    LocalClubs[id].entities = nil
    LocalClubs[id] = nil
end

function RenderClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onRender(id, entityId)
    return true
end

function UnrenderClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onUnrender(id, entityId)
end

function RegisterEntityType(entityType, data)
    RegisteredEntityTypes[entityType] = {
        label = data.label or entityType,
        description = data.description or "This is the " .. entityType .. " entity type.",
        data =  data.data or {},
        onRender = function(id, entityId)
            TriggerServerEvent("pickle_clubs:renderEntity", id, entityId)
            if data.onRender then
                data.onRender(id, entityId)
            end
        end,
        onUnrender = function(id, entityId)
            TriggerServerEvent("pickle_clubs:unrenderEntity", id, entityId)
            if data.onUnrender then
                data.onUnrender(id, entityId)
            end
        end,
    }
end

function UnregisterEntityType(entityType)
    RegisteredEntityTypes[entityType] = nil
end

function CreateClubNPC(pedId, coords, heading)
    local pedCfg = Config.Peds[pedId]
    local modelHash = `mp_m_freemode_01`
    if not pedCfg then 
        print("^1ERROR: No ped configuration found for: " .. pedId) 
    else 
        modelHash = pedCfg.model
    end
    local npc = CreateNPC(modelHash, coords.x, coords.y, coords.z, heading, false, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    FreezeEntityPosition(npc, true)
    return npc
end

local DialogContextCounter = 0

function StartClubPrompt(coords, heading, data)
    if not data or not data.dialog then return end
    -- Reset context counter for new prompt
    DialogContextCounter = 0
    CreateScriptedCamera()
    SetCamParams(CurrentCamera, coords.x, coords.y, coords.z + 0.5,
        0.0, 0.0, heading + 180.0, 90.0, 
        2000, 0, 0, 2
    )
    ShowDialogMenu(data.dialog)
end

function StopClubPrompt()
    ExitScriptedCamera()
    lib.hideContext()
end

function ShowDialogMenu(dialog, menuId)
    if not dialog then return end
    
    -- Call onStart callback if it exists
    if dialog.onStart then
        dialog.onStart()
    end
    
    DialogContextCounter = DialogContextCounter + 1
    local contextId = ('pickle_clubs_dialog_%s'):format(DialogContextCounter)
    local menuOptions = {}
    
    dialog.options = dialog.options or {}
    for i=1, #dialog.options do
        local option = dialog.options[i]
        local menuOption = {
            title = option.label,
            description = option.description or "",
            icon = option.icon,
        }
        
        -- If option has a nested dialog, create a submenu
        if option.dialog then
            menuOption.onSelect = function()
                -- Call option's onSelect callback if it exists before showing nested dialog
                if option.onSelect then
                    option.onSelect()
                end
                ShowDialogMenu(option.dialog, contextId)
            end
        else
            -- Leaf option - handle selection
            menuOption.onSelect = function()
                if option.onSelect then
                    option.onSelect()
                end
                -- If dialog should finish, close camera
                if dialog.finish then

                end
            end
        end
        
        table.insert(menuOptions, menuOption)
    end
    
    -- If dialog has finish=true and no options, add a default close option
    if dialog.finish then
        SetTimeout(2000, function()
            ExitScriptedCamera()
            lib.hideContext(contextId)
        end)
    end
    if dialog.speechSelect then
        dialog.speech = dialog.speechSelect()
    end
    -- Register and show context menu
    lib.registerContext({
        id = contextId,
        menu = menuId,
        title = dialog.speech or dialog.title or "Dialog",
        options = menuOptions
    })
    
    lib.showContext(contextId)
end

local function ToVector3(value, fallback)
    if type(value) == "vector3" then return value end
    if type(value) == "table" then
        local x = value.x or value[1]
        local y = value.y or value[2]
        local z = value.z or value[3]
        if x and y and z then
            return vector3(x, y, z)
        end
    end
    return fallback
end

local function CoordsDescription(coords)
    local v = ToVector3(coords, vector3(0.0, 0.0, 0.0))
    return ("%d, %d, %d"):format(math.floor(v.x), math.floor(v.y), math.floor(v.z))
end

local function GetEntityAnchor(entity, fallback)
    if not entity then return fallback end
    if entity.type == "bartender" and entity.bartender then
        return ToVector3(entity.bartender.coords, fallback)
    end
    if entity.bouncer then
        return ToVector3(entity.bouncer.coords, fallback)
    end
    if entity.line then
        return ToVector3(entity.line.coords, fallback)
    end
    return fallback
end

local function PlaceWithGizmo(initialCoords, initialHeading)
    local gizmo = StartGizmoEditor({
        model = Config.Bartender.registerModel or `vw_prop_casino_till`,
        coords = initialCoords,
        rotation = vector3(0.0, 0.0, initialHeading or 0.0),
        enableCancel = true,
    })
    if not gizmo or not gizmo.position then return nil, nil end
    return gizmo.position, (gizmo.rotation and gizmo.rotation.z) or (initialHeading or 0.0)
end

local function BuildBartenderEntityFromInput(baseEntity, defaultCoords, defaultHeading)
    local current = (baseEntity and baseEntity.bartender) or {}
    local startCoords = ToVector3(current.coords, defaultCoords)
    local startHeading = current.heading or defaultHeading or 0.0
    local coords, heading = PlaceWithGizmo(startCoords, startHeading)
    if not coords then return nil end

    local input = lib.inputDialog("Bartender Settings", {
        { type = "input", label = "Blip Name", default = (current.blip and current.blip.name) or "Bartending Station", required = true },
        { type = "input", label = "Blip Color", default = tostring((current.blip and current.blip.color) or 5), required = true },
        { type = "input", label = "Blip Sprite", default = tostring((current.blip and current.blip.sprite) or 52), required = true },
        { type = "input", label = "Blip Scale", default = tostring((current.blip and current.blip.scale) or 0.8), required = true },
        { type = "checkbox", label = "Blip Visible", checked = (current.blip and current.blip.visible) ~= false },
        { type = "input", label = "Society Name (optional)", default = current.society_name or "", required = false },
        { type = "input", label = "Society Percentage (0-100)", default = tostring(current.society_percentage or 0), required = true },
    })
    if not input then return nil end

    local societyName = input[6] and string.gsub(input[6], "^%s*(.-)%s*$", "%1") or ""
    if societyName == "" then societyName = nil end
    local societyPercentage = tonumber(input[7]) or 0
    if societyPercentage < 0 then societyPercentage = 0 end
    if societyPercentage > 100 then societyPercentage = 100 end

    return {
        type = "bartender",
        bartender = {
            coords = coords,
            heading = heading,
            blip = {
                name = input[1],
                color = tonumber(input[2]) or 5,
                sprite = tonumber(input[3]) or 52,
                scale = tonumber(input[4]) or 0.8,
                visible = input[5] ~= false,
            },
            society_name = societyName,
            society_percentage = societyPercentage,
        },
    }
end

local function BuildBouncerEntityFromInput(baseEntity, defaultCoords, defaultHeading)
    local current = (baseEntity and baseEntity.bouncer) or {}
    local startCoords = ToVector3(current.coords, defaultCoords)
    local startHeading = current.heading or defaultHeading or 0.0
    local coords, heading = PlaceWithGizmo(startCoords, startHeading)
    if not coords then return nil end

    local input = lib.inputDialog("Bouncer Settings", {
        { type = "input", label = "Ped Config Id", description = "Config.Peds key (example: bouncer_1)", default = current.ped or "bouncer_1", required = true },
    })
    if not input then return nil end

    return {
        type = "bouncer",
        bouncer = {
            ped = input[1],
            coords = coords,
            heading = heading,
        },
    }
end

local function BuildClubEntryEntityFromInput(baseEntity, defaultCoords, defaultHeading)
    local currentBouncer = (baseEntity and baseEntity.bouncer) or {}
    local currentLine = (baseEntity and baseEntity.line) or {}

    local initialBouncerCoords = ToVector3(currentBouncer.coords, defaultCoords)
    local initialBouncerHeading = currentBouncer.heading or defaultHeading or 0.0
    local bouncerCoords, bouncerHeading = PlaceWithGizmo(initialBouncerCoords, initialBouncerHeading)
    if not bouncerCoords then return nil end

    local initialLineCoords = ToVector3(currentLine.coords, bouncerCoords + vector3(0.0, -2.0, 0.0))
    local initialLineHeading = currentLine.heading or bouncerHeading
    local lineCoords, lineHeading = PlaceWithGizmo(initialLineCoords, initialLineHeading)
    if not lineCoords then return nil end

    local input = lib.inputDialog("Club Entry Settings", {
        { type = "input", label = "Bouncer Ped Config Id", description = "Config.Peds key (example: bouncer_1)", default = currentBouncer.ped or "bouncer_1", required = true },
        { type = "select", label = "Line Direction", default = currentLine.direction or "forward", required = true, options = {
            { value = "forward", label = "Forward" },
            { value = "backward", label = "Backward" },
        } },
    })
    if not input then return nil end

    return {
        type = "club_entry",
        bouncer = {
            ped = input[1],
            coords = bouncerCoords,
            heading = bouncerHeading,
        },
        line = {
            direction = input[2] or "forward",
            coords = lineCoords,
            heading = lineHeading,
        },
    }
end

local function BuildEntityPayload(entityType, baseEntity, club)
    local clubCoords = ToVector3(club and club.coords, GetEntityCoords(PlayerPedId()))
    local anchor = GetEntityAnchor(baseEntity, clubCoords)
    local defaultHeading = 0.0
    if baseEntity and baseEntity.bartender then defaultHeading = baseEntity.bartender.heading or defaultHeading end
    if baseEntity and baseEntity.bouncer then defaultHeading = baseEntity.bouncer.heading or defaultHeading end
    if baseEntity and baseEntity.line then defaultHeading = baseEntity.line.heading or defaultHeading end

    if entityType == "bartender" then
        return BuildBartenderEntityFromInput(baseEntity, anchor, defaultHeading)
    elseif entityType == "bouncer" then
        return BuildBouncerEntityFromInput(baseEntity, anchor, defaultHeading)
    elseif entityType == "club_entry" then
        return BuildClubEntryEntityFromInput(baseEntity, anchor, defaultHeading)
    end
    return nil
end

local function EntityTitle(entityType)
    if entityType == "bartender" then return "Bartender" end
    if entityType == "bouncer" then return "Bouncer" end
    if entityType == "club_entry" then return "Club Entry" end
    return entityType
end

local function OpenClubEntityMenu(clubId, entityId)
    local club = Clubs[clubId]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end

    local options = {}
    table.insert(options, {
        title = ("Edit %s"):format(EntityTitle(entity.type)),
        description = "Update this entity configuration",
        onSelect = function()
            local payload = BuildEntityPayload(entity.type, entity, club)
            if payload then
                TriggerServerEvent("pickle_clubs:updateClubEntity", clubId, entityId, payload)
            end
        end,
    })

    table.insert(options, {
        title = "Delete Entity",
        description = "Remove this entity from the club",
        onSelect = function()
            lib.registerContext({
                id = ("club_entity_delete_%s_%s"):format(clubId, entityId),
                title = "Confirm Entity Delete",
                options = {
                    {
                        title = "Yes, Delete",
                        description = "This cannot be undone",
                        onSelect = function()
                            TriggerServerEvent("pickle_clubs:deleteClubEntity", clubId, entityId)
                        end
                    },
                    {
                        title = "Cancel",
                        onSelect = function() end
                    }
                },
            })
            lib.showContext(("club_entity_delete_%s_%s"):format(clubId, entityId))
        end,
    })

    lib.registerContext({
        id = ("club_entity_manage_%s_%s"):format(clubId, entityId),
        title = ("Entity %s (%s)"):format(entityId, entity.type),
        options = options,
    })
    lib.showContext(("club_entity_manage_%s_%s"):format(clubId, entityId))
end

local function OpenClubManageMenu(clubId)
    local club = Clubs[clubId]
    if not club then return end

    local options = {
        {
            title = "Edit Club Details",
            description = "Update club label/description",
            onSelect = function()
                local input = lib.inputDialog("Edit Club", {
                    { type = "input", label = "Label", default = club.label, required = true },
                    { type = "textarea", label = "Description", default = club.description or "", required = false },
                })
                if not input then return end
                TriggerServerEvent("pickle_clubs:updateClub", clubId, {
                    label = input[1],
                    description = input[2] or "",
                })
            end,
        },
        {
            title = "Move Club Center",
            description = "Set the club center used for render distance",
            onSelect = function()
                local gizmo = StartGizmoEditor({
                    model = Config.Bartender.registerModel or `vw_prop_casino_till`,
                    coords = club.coords,
                    rotation = vector3(0.0, 0.0, GetEntityHeading(PlayerPedId())),
                    enableCancel = true,
                })
                if gizmo and gizmo.position then
                    TriggerServerEvent("pickle_clubs:updateClub", clubId, { coords = gizmo.position })
                end
            end,
        },
        {
            title = "Add Entity",
            description = "Create bartender, bouncer, or club entry entities",
            onSelect = function()
                local createOptions = {
                    {
                        title = "Add Bartender",
                        description = "Create a bartender station entity",
                        onSelect = function()
                            local payload = BuildEntityPayload("bartender", nil, club)
                            if payload then
                                TriggerServerEvent("pickle_clubs:createClubEntity", clubId, "bartender", payload)
                            end
                        end,
                    },
                    {
                        title = "Add Bouncer",
                        description = "Create a bouncer patrol entity",
                        onSelect = function()
                            local payload = BuildEntityPayload("bouncer", nil, club)
                            if payload then
                                TriggerServerEvent("pickle_clubs:createClubEntity", clubId, "bouncer", payload)
                            end
                        end,
                    },
                    {
                        title = "Add Club Entry",
                        description = "Create a queue+entry bouncer entity",
                        onSelect = function()
                            local payload = BuildEntityPayload("club_entry", nil, club)
                            if payload then
                                TriggerServerEvent("pickle_clubs:createClubEntity", clubId, "club_entry", payload)
                            end
                        end,
                    },
                }
                lib.registerContext({
                    id = ("club_add_entity_%s"):format(clubId),
                    title = ("Add Entity To Club #%s"):format(clubId),
                    options = createOptions,
                })
                lib.showContext(("club_add_entity_%s"):format(clubId))
            end,
        },
    }

    local entityOptions = {}
    local grouped = {
        bartender = {},
        bouncer = {},
        club_entry = {},
        other = {},
    }
    for listedEntityId, listedEntity in pairs(club.entities or {}) do
        local key = grouped[listedEntity.type] and listedEntity.type or "other"
        table.insert(grouped[key], {
            id = listedEntityId,
            data = listedEntity,
        })
    end
    local orderedTypes = {"bartender", "bouncer", "club_entry", "other"}
    for i = 1, #orderedTypes do
        local entityType = orderedTypes[i]
        if #grouped[entityType] > 0 then
            table.sort(grouped[entityType], function(a, b) return tostring(a.id) < tostring(b.id) end)
            table.insert(entityOptions, {
                title = EntityTitle(entityType),
                description = "--------------------",
                disabled = true,
            })
            for j = 1, #grouped[entityType] do
                local item = grouped[entityType][j]
                table.insert(entityOptions, {
                    title = tostring(item.id),
                    description = ("Type: %s | Coords: %s"):format(EntityTitle(item.data.type), CoordsDescription(GetEntityAnchor(item.data, club.coords))),
                    onSelect = function()
                        OpenClubEntityMenu(clubId, item.id)
                    end,
                })
            end
        end
    end
    if #entityOptions > 0 then
        table.insert(options, {
            title = "Manage Entities",
            description = "Edit or remove existing entities",
            onSelect = function()
                lib.registerContext({
                    id = ("club_entities_%s"):format(clubId),
                    title = ("Club %s Entities"):format(clubId),
                    options = entityOptions,
                })
                lib.showContext(("club_entities_%s"):format(clubId))
            end,
        })
    end

    table.insert(options, {
        title = "Delete Club",
        description = "Delete club and all entities",
        onSelect = function()
            lib.registerContext({
                id = ("club_delete_confirm_%s"):format(clubId),
                title = "Confirm Club Delete",
                options = {
                    {
                        title = "Yes, Delete Club",
                        description = "Deletes all entities inside this club",
                        onSelect = function()
                            TriggerServerEvent("pickle_clubs:deleteClub", clubId)
                        end,
                    },
                    {
                        title = "Cancel",
                        onSelect = function() end,
                    }
                },
            })
            lib.showContext(("club_delete_confirm_%s"):format(clubId))
        end,
    })

    lib.registerContext({
        id = ("club_manage_%s"):format(clubId),
        title = ("Manage Club #%s"):format(clubId),
        options = options,
    })
    lib.showContext(("club_manage_%s"):format(clubId))
end

function OpenClubManagement()
    lib.callback("pickle_clubs:checkIsAdmin", false, function(isAdmin)
        if not isAdmin then
            ShowNotification("You do not have permission to manage clubs.")
            return
        end

        local options = {
            {
                title = "Create New Club",
                description = "Create a club and set its center with gizmo",
                onSelect = function()
                    local input = lib.inputDialog("Create Club", {
                        { type = "input", label = "Label", required = true },
                        { type = "textarea", label = "Description", required = false },
                    })
                    if not input then return end
                    local gizmo = StartGizmoEditor({
                        model = Config.Bartender.registerModel or `vw_prop_casino_till`,
                        coords = GetEntityCoords(PlayerPedId()) + GetEntityForwardVector(PlayerPedId()) * 2.0,
                        rotation = vector3(0.0, 0.0, GetEntityHeading(PlayerPedId())),
                        enableCancel = true,
                    })
                    if not gizmo or not gizmo.position then return end
                    TriggerServerEvent("pickle_clubs:createClub", {
                        label = input[1],
                        description = input[2] or "",
                        coords = gizmo.position,
                    })
                end,
            }
        }

        local clubOptions = {}
        for clubId, club in pairs(Clubs) do
            table.insert(clubOptions, {
                title = ("#%s %s"):format(clubId, club.label),
                description = club.description or "",
                onSelect = function()
                    OpenClubManageMenu(clubId)
                end,
            })
        end

        if #clubOptions > 0 then
            table.insert(options, {
                title = "Manage Existing Clubs",
                description = "Open a club to edit entities and settings",
                onSelect = function()
                    lib.registerContext({
                        id = "club_manage_list",
                        title = "Clubs",
                        options = clubOptions,
                    })
                    lib.showContext("club_manage_list")
                end,
            })
        end

        lib.registerContext({
            id = "club_management_root",
            title = "Club Management",
            options = options,
        })
        lib.showContext("club_management_root")
    end)
end

CreateThread(function()
    while true do
        for k,v in pairs(Clubs) do
            local pcoords = GetEntityCoords(PlayerPedId())
            local dist = #(pcoords - v.coords)
            if dist <= Config.RenderDistance and not LocalClubs[k] then
                RenderClub(k)
            elseif LocalClubs[k] and dist > Config.RenderDistance then
                UnrenderClub(k)
            end
        end
        Wait(1500)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    Wait(1000)
    if resource == GetCurrentResourceName() then
        TriggerServerEvent("pickle_clubs:initializePlayer")
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for k,v in pairs(Clubs) do
            UnregisterClub(k)
        end
    end
end)

RegisterNetEvent("pickle_clubs:syncClubs", function(id, data)
    if type(id) == "number" then
        if not data then return UnregisterClub(id) end
        RegisterClub(id, data)
    else 
        local data = id
        for k,v in pairs(Clubs) do
            UnregisterClub(k)
        end
        for k,v in pairs(data) do
            RegisterClub(k, v)
        end
    end
end)

RegisterNetEvent("pickle_clubs:openClubManagement", function()
    OpenClubManagement()
end)

AddEventHandler("pickle_clubs:openClubManagement", function()
    OpenClubManagement()
end)