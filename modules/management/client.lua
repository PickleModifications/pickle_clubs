-- Bartending Station Management Client
Stations = {} -- stationId -> station data
StationBlips = {} -- stationId -> blip handle
StationEntities = {} -- stationId -> {register = entity, ...}
local inManagementMode = false

-- Create blip for station
function CreateStationBlip(station)
    if not station.blip.visible then return end
    
    if StationBlips[station.id] then
        RemoveBlip(StationBlips[station.id])
    end
    
    -- Ensure coords is vector3
    local coords = station.coords
    if type(coords) == "table" then
        coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    end
    
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, station.blip.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, station.blip.scale)
    SetBlipColour(blip, station.blip.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(station.blip.name)
    EndTextCommandSetBlipName(blip)
    
    StationBlips[station.id] = blip
end

-- Remove blip for station
function RemoveStationBlip(stationId)
    if StationBlips[stationId] then
        RemoveBlip(StationBlips[stationId])
        StationBlips[stationId] = nil
    end
end

-- Create station entities (register and interaction zone)
function CreateStationEntities(station)
    if StationEntities[station.id] then
        -- Cleanup existing entities
        if DoesEntityExist(StationEntities[station.id].register) then
            DeleteEntity(StationEntities[station.id].register)
        end
    end
    
    -- Ensure coords is vector3
    local coords = station.coords
    if type(coords) == "table" then
        coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    end
    
    -- Create register entity
    local register = CreateProp(Config.Bartender.Stations.registerModel, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(register, true, true)
    SetEntityHeading(register, station.heading or 0.0)
    SetEntityAsMissionEntity(register, true, true)
    -- Start visible (will be hidden when someone starts bartending)
    SetEntityAlpha(register, 255, false)
    
    StationEntities[station.id] = {
        register = register,
        coords = coords,
        heading = station.heading or 0.0,
    }
end

-- Remove station entities
function RemoveStationEntities(stationId)
    if StationEntities[stationId] then
        if DoesEntityExist(StationEntities[stationId].register) then
            DeleteEntity(StationEntities[stationId].register)
        end
        StationEntities[stationId] = nil
    end
end

-- Load stations (create blips and entities)
function LoadStations(stations)
    Stations = stations or {}
    
    -- Cleanup existing stations
    for stationId, _ in pairs(StationBlips) do
        RemoveStationBlip(stationId)
    end
    for stationId, _ in pairs(StationEntities) do
        RemoveStationEntities(stationId)
    end
    
    -- Create new stations
    for stationId, station in pairs(Stations) do
        -- Ensure coords is vector3
        if station.coords and type(station.coords) == "table" then
            station.coords = vector3(station.coords.x or station.coords[1], station.coords.y or station.coords[2], station.coords.z or station.coords[3])
        end
        
        CreateStationBlip(station)
        CreateStationEntities(station)
    end
end

-- Update station on client
function UpdateStationOnClient(stationId, stationData)
    if not Stations[stationId] then return end
    
    -- Ensure coords is vector3
    if stationData.coords and type(stationData.coords) == "table" then
        stationData.coords = vector3(stationData.coords.x or stationData.coords[1], stationData.coords.y or stationData.coords[2], stationData.coords.z or stationData.coords[3])
    end
    
    Stations[stationId] = stationData
    
    -- Hide station during update (remove blip and entities temporarily)
    RemoveStationBlip(stationId)
    RemoveStationEntities(stationId)
    
    -- Recreate with new data
    CreateStationBlip(stationData)
    CreateStationEntities(stationData)
end

-- Remove station on client
function RemoveStationOnClient(stationId)
    RemoveStationBlip(stationId)
    RemoveStationEntities(stationId)
    Stations[stationId] = nil
end

-- Place station with gizmo
function PlaceStationWithGizmo(existingStationId)
    local existingStation = existingStationId and Stations[existingStationId]
    local coords = existingStation and existingStation.coords or (GetEntityCoords(PlayerPedId()) + GetEntityForwardVector(PlayerPedId()) * 3)
    local heading = existingStation and existingStation.heading or GetEntityHeading(PlayerPedId())
    
    -- Hide existing station if updating
    local hiddenEntity = nil
    if existingStationId and StationEntities[existingStationId] then
        local register = StationEntities[existingStationId].register
        if DoesEntityExist(register) then
            hiddenEntity = register
            SetEntityAlpha(register, 0, false)
        end
    end
    
    local result = StartGizmoEditor({
        model = Config.Bartender.Stations.registerModel,
        coords = coords,
        rotation = vector3(0.0, 0.0, heading),
        enableCancel = true,
        deleteEntity = not existingStationId, -- Delete entity if creating new, keep if updating
    })
    
    -- Restore visibility if updating
    if hiddenEntity and DoesEntityExist(hiddenEntity) then
        SetEntityAlpha(hiddenEntity, 255, false)
    end
    
    if result and result.position then
        local newCoords = result.position
        local newHeading = result.rotation.z
        
        if existingStationId then
            -- Update existing station
            TriggerServerEvent("pickle_clubs:updateStation", existingStationId, newCoords, newHeading, nil)
        else
            -- Create new station
            TriggerServerEvent("pickle_clubs:createStation", newCoords, newHeading, nil)
        end
    end
end

-- Configure blip for station
function ConfigureStationBlip(stationId)
    local station = Stations[stationId]
    if not station then return end
    
    local input = lib.inputDialog("Configure Blip", {
        {
            type = "input",
            label = "Blip Name",
            default = station.blip.name,
            required = true,
        },
        {
            type = "input",
            label = "Blip Color (0-85)",
            default = tostring(station.blip.color),
            required = true,
        },
        {
            type = "input",
            label = "Blip Sprite (0-826)",
            default = tostring(station.blip.sprite),
            required = true,
        },
        {
            type = "input",
            label = "Blip Scale (0.1-2.0)",
            default = tostring(station.blip.scale),
            required = true,
        },
        {
            type = "checkbox",
            label = "Visible",
            checked = station.blip.visible,
        },
    })
    
    if input then
        local blipData = {
            name = input[1],
            color = tonumber(input[2]) or station.blip.color,
            sprite = tonumber(input[3]) or station.blip.sprite,
            scale = tonumber(input[4]) or station.blip.scale,
            visible = input[5] ~= nil and input[5] or station.blip.visible,
        }
        
        TriggerServerEvent("pickle_clubs:updateStation", stationId, nil, nil, blipData)
    end
end

-- Open management menu for a specific station
function OpenStationManagementMenu(stationId)
    local station = Stations[stationId]
    if not station then return end
    
    lib.registerContext({
        id = "station_manage_" .. stationId,
        title = "Station #" .. stationId,
        options = {
            {
                title = "Edit Position",
                description = "Move this station",
                onSelect = function()
                    PlaceStationWithGizmo(stationId)
                end,
            },
            {
                title = "Configure Blip",
                description = "Change blip settings",
                onSelect = function()
                    ConfigureStationBlip(stationId)
                end,
            },
            {
                title = "Delete Station",
                description = "Remove this station",
                onSelect = function()
                    lib.registerContext({
                        id = "station_delete_confirm_" .. stationId,
                        title = "Confirm Delete",
                        options = {
                            {
                                title = "Yes, Delete",
                                description = "This cannot be undone",
                                onSelect = function()
                                    TriggerServerEvent("pickle_clubs:deleteStation", stationId)
                                end,
                            },
                            {
                                title = "Cancel",
                                onSelect = function() end,
                            },
                        },
                    })
                    lib.showContext("station_delete_confirm_" .. stationId)
                end,
            },
        },
    })
    lib.showContext("station_manage_" .. stationId)
end

-- Start station management UI
function StartStationManagement()
    if inManagementMode then return end
    
    local options = {
        {
            title = "Create New Station",
            description = "Place a new bartending station",
            onSelect = function()
                PlaceStationWithGizmo(nil)
            end,
        },
    }
    
    -- Add existing stations to menu
    local stationList = {}
    for stationId, station in pairs(Stations) do
        table.insert(stationList, {
            id = stationId,
            station = station,
        })
    end
    
    if #stationList > 0 then
        table.insert(options, {
            title = "Manage Stations",
            description = "Edit or delete existing stations",
            onSelect = function()
                local stationOptions = {}
                for i = 1, #stationList do
                    local item = stationList[i]
                    table.insert(stationOptions, {
                        title = "Station #" .. item.id,
                        description = "Coords: " .. math.floor(item.station.coords.x) .. ", " .. math.floor(item.station.coords.y) .. ", " .. math.floor(item.station.coords.z),
                        onSelect = function()
                            OpenStationManagementMenu(item.id)
                        end,
                    })
                end
                lib.registerContext({
                    id = "station_list",
                    title = "Stations",
                    options = stationOptions,
                })
                lib.showContext("station_list")
            end,
        })
    end
    
    lib.registerContext({
        id = "bartender_management",
        title = "Bartender Station Management",
        options = options,
    })
    lib.showContext("bartender_management")
end

-- Events
RegisterNetEvent("pickle_clubs:syncStations", function(stations)
    LoadStations(stations)
end)

RegisterNetEvent("pickle_clubs:removeStation", function(stationId)
    RemoveStationOnClient(stationId)
end)

RegisterNetEvent("pickle_clubs:stationControlDenied", function(message)
    ShowNotification("^1" .. (message or "Station is already in use"))
end)

-- Request stations on resource start
CreateThread(function()
    Wait(1000)
    TriggerServerEvent("pickle_clubs:requestStations")
end)

-- Export function for command handler
exports("StartStationManagement", StartStationManagement)
exports("OpenStationManagementMenu", OpenStationManagementMenu)

function GetStationEntity(stationId)
    if StationEntities[stationId] and StationEntities[stationId].register then
        local register = StationEntities[stationId].register
        if DoesEntityExist(register) then
            return register
        end
    end
    return nil
end

exports("GetStationEntity", GetStationEntity)

-- Cleanup station entities when out of render distance
CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        
        for stationId, stationData in pairs(StationEntities) do
            local station = Stations[stationId]
            if station and station.coords then
                local coords = station.coords
                if type(coords) == "table" then
                    coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
                end
                
                local distance = #(pedCoords - coords)
                -- If station is out of render distance, cleanup entities
                if distance > Config.RenderDistance then
                    if stationData.register and DoesEntityExist(stationData.register) then
                        DeleteEntity(stationData.register)
                        StationEntities[stationId].register = nil
                    end
                elseif distance <= Config.RenderDistance then
                    -- Ensure entity exists when in range (but respect visibility state)
                    if not stationData.register or not DoesEntityExist(stationData.register) then
                        CreateStationEntities(station)
                        -- Check if register should be hidden (someone is bartending)
                        -- This will be synced via server events, but we ensure it's created first
                    end
                end
            end
        end
    end
end)

-- Handle register visibility sync events
RegisterNetEvent("pickle_clubs:hideStationRegister", function(stationId)
    HideStationRegister(stationId)
end)

RegisterNetEvent("pickle_clubs:showStationRegister", function(stationId)
    ShowStationRegister(stationId)
end)

-- Helper functions for register visibility
function HideStationRegister(stationId)
    if StationEntities[stationId] and StationEntities[stationId].register then
        local register = StationEntities[stationId].register
        if DoesEntityExist(register) then
            SetEntityAlpha(register, 0, false)
            SetEntityCollision(register, false, false)
        end
    end
end

function ShowStationRegister(stationId)
    if StationEntities[stationId] and StationEntities[stationId].register then
        local register = StationEntities[stationId].register
        if DoesEntityExist(register) then
            SetEntityAlpha(register, 255, false)
            SetEntityCollision(register, true, true)
        end
    end
end

-- Cleanup all stations on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        -- Cleanup all blips
        for stationId, blip in pairs(StationBlips) do
            RemoveBlip(blip)
        end
        StationBlips = {}
        
        -- Cleanup all entities
        for stationId, stationData in pairs(StationEntities) do
            RemoveStationEntities(stationId)
        end
        StationEntities = {}
        
        -- Clear station data
        Stations = {}
    end
end)

-- Command event
RegisterNetEvent("pickle_clubs:openStationManagement", function()
    StartStationManagement()
end)
