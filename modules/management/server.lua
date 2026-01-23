-- Bartending Station Management Server
Stations = {} -- In-memory cache: stationId -> station data
StationControllers = {} -- Track active controllers: stationId -> {source = playerId, type = "interaction"|"service"}

-- Load all stations from database
function LoadAllStations()
    MySQL.Async.fetchAll("SELECT * FROM pickle_bartender_stations", {}, function(results)
        Stations = {}
        if results then
            for i = 1, #results do
                local station = results[i]
                local coordsData = json.decode(station.coords)
                Stations[station.id] = {
                    id = station.id,
                    coords = vector3(coordsData.x, coordsData.y, coordsData.z),
                    heading = station.heading,
                    blip = {
                        name = station.blip_name,
                        color = station.blip_color,
                        sprite = station.blip_sprite,
                        scale = station.blip_scale,
                        visible = station.blip_visible == 1,
                    },
                }
            end
        end
        -- Sync to all clients
        TriggerClientEvent("pickle_clubs:syncStations", -1, Stations)
        print("^2Loaded " .. (#results or 0) .. " bartending stations")
        
        -- Set register visibility based on current controller state
        for stationId, _ in pairs(Stations) do
            if IsStationControlled(stationId, "interaction") then
                -- Hide register if station is being used
                TriggerClientEvent("pickle_clubs:hideStationRegister", -1, stationId)
            else
                -- Show register if station is not being used
                TriggerClientEvent("pickle_clubs:showStationRegister", -1, stationId)
            end
        end
    end)
end

-- Create a new station
function CreateStation(coords, heading, blipData)
    local blip = blipData or Config.Bartender.Stations.defaultBlip
    local coordsJson = json.encode({x = coords.x, y = coords.y, z = coords.z})
    
    MySQL.Async.insert("INSERT INTO pickle_bartender_stations (coords, heading, blip_name, blip_color, blip_sprite, blip_scale, blip_visible) VALUES (@coords, @heading, @blip_name, @blip_color, @blip_sprite, @blip_scale, @blip_visible)", {
        ['@coords'] = coordsJson,
        ['@heading'] = heading,
        ['@blip_name'] = blip.name,
        ['@blip_color'] = blip.color,
        ['@blip_sprite'] = blip.sprite,
        ['@blip_scale'] = blip.scale,
        ['@blip_visible'] = blip.visible and 1 or 0,
    }, function(insertId)
        if insertId then
            Stations[insertId] = {
                id = insertId,
                coords = coords,
                heading = heading,
                blip = blip,
            }
            -- Sync to all clients
            TriggerClientEvent("pickle_clubs:syncStations", -1, Stations)
            -- Show register for new station
            TriggerClientEvent("pickle_clubs:showStationRegister", -1, insertId)
            return insertId
        end
    end)
end

-- Update station position and/or blip settings
function UpdateStation(stationId, coords, heading, blipData)
    if not Stations[stationId] then return false end
    
    local updateFields = {}
    local updateValues = {}
    
    if coords then
        local coordsJson = json.encode({x = coords.x, y = coords.y, z = coords.z})
        table.insert(updateFields, "coords = @coords")
        updateValues['@coords'] = coordsJson
        Stations[stationId].coords = coords
    end
    
    if heading then
        table.insert(updateFields, "heading = @heading")
        updateValues['@heading'] = heading
        Stations[stationId].heading = heading
    end
    
    if blipData then
        if blipData.name then
            table.insert(updateFields, "blip_name = @blip_name")
            updateValues['@blip_name'] = blipData.name
            Stations[stationId].blip.name = blipData.name
        end
        if blipData.color then
            table.insert(updateFields, "blip_color = @blip_color")
            updateValues['@blip_color'] = blipData.color
            Stations[stationId].blip.color = blipData.color
        end
        if blipData.sprite then
            table.insert(updateFields, "blip_sprite = @blip_sprite")
            updateValues['@blip_sprite'] = blipData.sprite
            Stations[stationId].blip.sprite = blipData.sprite
        end
        if blipData.scale then
            table.insert(updateFields, "blip_scale = @blip_scale")
            updateValues['@blip_scale'] = blipData.scale
            Stations[stationId].blip.scale = blipData.scale
        end
        if blipData.visible ~= nil then
            table.insert(updateFields, "blip_visible = @blip_visible")
            updateValues['@blip_visible'] = blipData.visible and 1 or 0
            Stations[stationId].blip.visible = blipData.visible
        end
    end
    
    if #updateFields == 0 then return false end
    
    updateValues['@id'] = stationId
    local query = "UPDATE pickle_bartender_stations SET " .. table.concat(updateFields, ", ") .. " WHERE id = @id"
    
    MySQL.Async.execute(query, updateValues, function(affectedRows)
        if affectedRows > 0 then
            -- Sync to all clients
            TriggerClientEvent("pickle_clubs:syncStations", -1, Stations)
            -- Ensure register is visible after update (unless someone is using it)
            if not IsStationControlled(stationId, "interaction") then
                TriggerClientEvent("pickle_clubs:showStationRegister", -1, stationId)
            end
            return true
        end
    end)
end

-- Delete station
function DeleteStation(stationId)
    if not Stations[stationId] then return false, "Station not found" end
    
    -- Check if station has active controllers
    if IsStationControlled(stationId) then
        return false, "Station is currently in use"
    end
    
    -- Notify other modules that station is being deleted
    TriggerEvent("pickle_clubs:stationDeleted", stationId)
    
    -- Show register before deletion (cleanup)
    TriggerClientEvent("pickle_clubs:showStationRegister", -1, stationId)
    
    MySQL.Async.execute("DELETE FROM pickle_bartender_stations WHERE id = @id", {
        ['@id'] = stationId,
    }, function(affectedRows)
        if affectedRows > 0 then
            Stations[stationId] = nil
            StationControllers[stationId] = nil
            -- Sync to all clients
            TriggerClientEvent("pickle_clubs:syncStations", -1, Stations)
            TriggerClientEvent("pickle_clubs:removeStation", -1, stationId)
            return true
        end
    end)
end

-- Get station data
function GetStation(stationId)
    return Stations[stationId]
end

-- Get all stations
function GetAllStations()
    return Stations
end

-- Check if station is controlled
function IsStationControlled(stationId, controlType)
    if not StationControllers[stationId] then return false end
    local controllers = StationControllers[stationId]
    if controlType then
        return controllers[controlType] ~= nil
    end
    -- Check if any controller exists
    for k, v in pairs(controllers) do
        if v then return true end
    end
    return false
end

-- Set station controller
function SetStationController(stationId, source, controlType)
    if not Stations[stationId] then return false, "Station not found" end
    
    -- Check if already controlled
    if IsStationControlled(stationId, controlType) then
        return false, "Station is already controlled"
    end
    
    if not StationControllers[stationId] then
        StationControllers[stationId] = {}
    end
    
    StationControllers[stationId][controlType] = {
        source = source,
        type = controlType,
    }
    
    return true
end

-- Clear station controller
function ClearStationController(stationId, controlType)
    if not StationControllers[stationId] then return end
    
    if controlType then
        StationControllers[stationId][controlType] = nil
        -- Clean up if no controllers left
        local hasAny = false
        for k, v in pairs(StationControllers[stationId]) do
            hasAny = true
            break
        end
        if not hasAny then
            StationControllers[stationId] = nil
        end
    else
        -- Clear all controllers
        StationControllers[stationId] = nil
    end
end

-- Events
RegisterNetEvent("pickle_clubs:createStation", function(coords, heading, blipData)
    local source = source
    if not IsPlayerAdmin(source) then
        ShowNotification(source, "^1You don't have permission to create stations")
        return
    end
    
    CreateStation(coords, heading, blipData)
    ShowNotification(source, "^2Station created successfully")
end)

RegisterNetEvent("pickle_clubs:updateStation", function(stationId, coords, heading, blipData)
    local source = source
    if not IsPlayerAdmin(source) then
        ShowNotification(source, "^1You don't have permission to update stations")
        return
    end
    
    UpdateStation(stationId, coords, heading, blipData)
    ShowNotification(source, "^2Station updated successfully")
end)

RegisterNetEvent("pickle_clubs:deleteStation", function(stationId)
    local source = source
    if not IsPlayerAdmin(source) then
        ShowNotification(source, "^1You don't have permission to delete stations")
        return
    end
    
    local success, message = DeleteStation(stationId)
    if success then
        ShowNotification(source, "^2Station deleted successfully")
    else
        ShowNotification(source, "^1" .. (message or "Failed to delete station"))
    end
end)

RegisterNetEvent("pickle_clubs:requestStations", function()
    local source = source
    TriggerClientEvent("pickle_clubs:syncStations", source, Stations)
    
    -- Sync register visibility state for newly connected player
    for stationId, _ in pairs(Stations) do
        if IsStationControlled(stationId, "interaction") then
            TriggerClientEvent("pickle_clubs:hideStationRegister", source, stationId)
        else
            TriggerClientEvent("pickle_clubs:showStationRegister", source, stationId)
        end
    end
end)

RegisterNetEvent("pickle_clubs:requestStationControllerStates", function()
    local source = source
    -- Send current controller states to sync register visibility
    for stationId, _ in pairs(Stations) do
        if IsStationControlled(stationId, "interaction") then
            TriggerClientEvent("pickle_clubs:hideStationRegister", source, stationId)
        else
            TriggerClientEvent("pickle_clubs:showStationRegister", source, stationId)
        end
    end
end)

-- Check if player is admin (using ox_lib callback)
lib.callback.register("pickle_clubs:checkIsAdmin", function(source)
    return IsPlayerAdmin(source)
end)

RegisterNetEvent("pickle_clubs:setStationController", function(stationId, controlType)
    local source = source
    local success, message = SetStationController(stationId, source, controlType)
    if not success then
        TriggerClientEvent("pickle_clubs:stationControlDenied", source, message)
    else
        -- If interaction control was set, hide register for all clients
        if controlType == "interaction" then
            TriggerClientEvent("pickle_clubs:hideStationRegister", -1, stationId)
        end
    end
end)

RegisterNetEvent("pickle_clubs:clearStationController", function(stationId, controlType)
    local source = source
    ClearStationController(stationId, controlType)
    -- If interaction control was cleared, show register for all clients
    if controlType == "interaction" then
        TriggerClientEvent("pickle_clubs:showStationRegister", -1, stationId)
    end
end)

-- Create database table and load stations on resource start
MySQL.ready(function()
    -- Create table if it doesn't exist
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS pickle_bartender_stations (
            id INT AUTO_INCREMENT PRIMARY KEY,
            coords JSON NOT NULL,
            heading FLOAT NOT NULL,
            blip_name VARCHAR(255) DEFAULT 'Bartending Station',
            blip_color INT DEFAULT 5,
            blip_sprite INT DEFAULT 52,
            blip_scale FLOAT DEFAULT 0.8,
            blip_visible BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {}, function(result)
        if result then
            print("^2Bartending stations table created/verified")
        end
        -- Load all stations after table is ready
        LoadAllStations()
    end)
end)

-- Cleanup controllers on player disconnect
AddEventHandler("playerDropped", function()
    local source = source
    for stationId, controllers in pairs(StationControllers) do
        if type(controllers) == "table" then
            for controlType, controller in pairs(controllers) do
                if controller and controller.source == source then
                    ClearStationController(stationId, controlType)
                    -- If interaction control was cleared, show register for all clients
                    if controlType == "interaction" then
                        TriggerClientEvent("pickle_clubs:showStationRegister", -1, stationId)
                    end
                end
            end
        end
    end
end)

-- Exports
exports("GetStationControllers", function()
    return StationControllers
end)

exports("GetStation", GetStation)
exports("IsStationControlled", IsStationControlled)
exports("SetStationController", SetStationController)
exports("ClearStationController", ClearStationController)

-- Command handler
RegisterCommand("managebar", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        ShowNotification(source, "^1You don't have permission to use this command")
        return
    end
    
    TriggerClientEvent("pickle_clubs:openStationManagement", source)
end, false)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        -- Clear all station controllers
        StationControllers = {}
        
        -- Stations will be cleared automatically, but we can also clear them here
        -- Note: Don't clear Stations as they may be needed by other modules
    end
end)
