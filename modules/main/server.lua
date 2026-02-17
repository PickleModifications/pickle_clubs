Clubs = {}
RegisteredEntityTypes = {}
EntityPlayers = {}

local function IsVectorTable(value)
    if type(value) ~= "table" then return false end
    if type(value.x) ~= "number" or type(value.y) ~= "number" or type(value.z) ~= "number" then
        return false
    end
    for k, _ in pairs(value) do
        if k ~= "x" and k ~= "y" and k ~= "z" then
            return false
        end
    end
    return true
end

local function NormalizeForDb(value)
    local valueType = type(value)
    if valueType == "vector3" then
        return { x = value.x, y = value.y, z = value.z }
    end
    if valueType ~= "table" then
        return value
    end
    local output = {}
    for k, v in pairs(value) do
        output[k] = NormalizeForDb(v)
    end
    return output
end

local function NormalizeFromDb(value)
    if type(value) ~= "table" then return value end
    if IsVectorTable(value) then
        return vector3(value.x, value.y, value.z)
    end
    local output = {}
    for k, v in pairs(value) do
        output[k] = NormalizeFromDb(v)
    end
    return output
end

local function BuildClubPacket(data)
    return {
        label = data.label,
        description = data.description,
        coords = data.coords,
        entities = data.entities or {},
    }
end

local function GenerateEntityId()
    return ("club-%d-%d"):format(os.time(), math.random(100000, 999999))
end

local function IsVectorLike(value)
    if type(value) == "vector3" then return true end
    if type(value) ~= "table" then return false end
    local x = value.x or value[1]
    local y = value.y or value[2]
    local z = value.z or value[3]
    return type(x) == "number" and type(y) == "number" and type(z) == "number"
end

local function ValidateEntityData(entityType, entityData)
    if type(entityData) ~= "table" then
        return false, "Invalid entity payload"
    end

    if entityType == "bartender" then
        local bartender = entityData.bartender
        if type(bartender) ~= "table" then
            return false, "Missing bartender settings"
        end
        if not IsVectorLike(bartender.coords) then
            return false, "Bartender coords are required"
        end
        if type(bartender.heading) ~= "number" then
            return false, "Bartender heading is required"
        end
        if bartender.society_percentage ~= nil then
            bartender.society_percentage = math.max(0, math.min(100, tonumber(bartender.society_percentage) or 0))
        end
        return true
    end

    if entityType == "bouncer" then
        local bouncer = entityData.bouncer
        if type(bouncer) ~= "table" then
            return false, "Missing bouncer settings"
        end
        if not IsVectorLike(bouncer.coords) then
            return false, "Bouncer coords are required"
        end
        if type(bouncer.heading) ~= "number" then
            return false, "Bouncer heading is required"
        end
        if type(bouncer.ped) ~= "string" or bouncer.ped == "" then
            return false, "Bouncer ped id is required"
        end
        return true
    end

    if entityType == "club_entry" then
        local bouncer = entityData.bouncer
        local line = entityData.line
        if type(bouncer) ~= "table" or type(line) ~= "table" then
            return false, "Club entry requires bouncer and line settings"
        end
        if not IsVectorLike(bouncer.coords) or type(bouncer.heading) ~= "number" then
            return false, "Club entry bouncer coords/heading are required"
        end
        if type(bouncer.ped) ~= "string" or bouncer.ped == "" then
            return false, "Club entry bouncer ped id is required"
        end
        if not IsVectorLike(line.coords) or type(line.heading) ~= "number" then
            return false, "Club entry line coords/heading are required"
        end
        if line.direction ~= "forward" and line.direction ~= "backward" then
            line.direction = "forward"
        end
        return true
    end

    return true
end

local function SyncAllClubs(target)
    TriggerClientEvent("pickle_clubs:syncClubs", target or -1, Clubs)
end

function RegisterClub(data, skipSync)
    Clubs[data.id] = BuildClubPacket(data)
    for entityId, _ in pairs(Clubs[data.id].entities) do
        StartClubEntity(data.id, entityId)
    end
    if not skipSync then
        SyncAllClubs(-1)
    end
end

function StartClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onStart(id, entityId)
end

function StopClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onStop(id, entityId)
end

function RegisterEntityType(entityType, data)
    RegisteredEntityTypes[entityType] = {
        label = data.label or entityType,
        description = data.description or ("This is the " .. entityType .. " entity type."),
        data = data.data or {},
        onStart = data.onStart or function()
            print("ERROR: No onStart callback for entity type: " .. entityType)
        end,
        onRender = data.onRender or function()
            print("ERROR: No onRender callback for entity type: " .. entityType)
        end,
        onUnrender = data.onUnrender or function()
            print("ERROR: No onUnrender callback for entity type: " .. entityType)
        end,
        onStop = data.onStop or function()
            print("ERROR: No onStop callback for entity type: " .. entityType)
        end,
    }

    for clubId, club in pairs(Clubs) do
        for entityId, entity in pairs(club.entities or {}) do
            if entity.type == entityType then
                StartClubEntity(clubId, entityId)
            end
        end
    end
end

function UnregisterEntityType(entityType)
    RegisteredEntityTypes[entityType] = nil
end

function TriggerEntityEvent(event, id, entityId, ...)
    if not EntityPlayers[id] or not EntityPlayers[id][entityId] then return end
    for i = 1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        TriggerClientEvent(event, player, id, entityId, ...)
    end
end

function GetClub(id)
    return Clubs[id]
end

function CreateClub(data, cb)
    local payloadCoords = NormalizeForDb(data.coords)
    MySQL.Async.insert(
        "INSERT INTO pickle_clubs (label, description, coords) VALUES (@label, @description, @coords)",
        {
            ["@label"] = data.label,
            ["@description"] = data.description or "",
            ["@coords"] = json.encode(payloadCoords),
        },
        function(insertId)
            if not insertId then
                if cb then cb(false, "Failed to create club") end
                return
            end
            RegisterClub({
                id = insertId,
                label = data.label,
                description = data.description or "",
                coords = data.coords,
                entities = {},
            }, false)
            if cb then cb(true, insertId) end
        end
    )
end

function UpdateClub(id, data, cb)
    local club = Clubs[id]
    if not club then
        if cb then cb(false, "Club not found") end
        return
    end
    local updateData = {
        label = data.label or club.label,
        description = data.description or club.description,
        coords = data.coords or club.coords,
    }
    MySQL.Async.execute(
        "UPDATE pickle_clubs SET label = @label, description = @description, coords = @coords WHERE id = @id",
        {
            ["@id"] = id,
            ["@label"] = updateData.label,
            ["@description"] = updateData.description or "",
            ["@coords"] = json.encode(NormalizeForDb(updateData.coords)),
        },
        function(affectedRows)
            if affectedRows and affectedRows > 0 then
                club.label = updateData.label
                club.description = updateData.description
                club.coords = updateData.coords
                SyncAllClubs(-1)
                if cb then cb(true) end
            else
                if cb then cb(false, "Failed to update club") end
            end
        end
    )
end

function DeleteClub(id, cb)
    local club = Clubs[id]
    if not club then
        if cb then cb(false, "Club not found") end
        return
    end
    for entityId, _ in pairs(club.entities or {}) do
        StopClubEntity(id, entityId)
    end
    Clubs[id] = nil
    EntityPlayers[id] = nil
    SyncAllClubs(-1)
    MySQL.Async.execute("DELETE FROM pickle_clubs WHERE id = @id", {
        ["@id"] = id,
    }, function(affectedRows)
        if cb then cb((affectedRows or 0) > 0) end
    end)
end

function CreateClubEntity(clubId, entityType, entityData, entityId, cb)
    local club = Clubs[clubId]
    if not club then
        if cb then cb(false, "Club not found") end
        return
    end
    local key = entityId or GenerateEntityId()
    local valid, validationMessage = ValidateEntityData(entityType, entityData)
    if not valid then
        if cb then cb(false, validationMessage or "Invalid entity payload") end
        return
    end
    local payload = NormalizeForDb(entityData or {})
    MySQL.Async.insert(
        "INSERT INTO pickle_club_entities (club_id, entity_key, entity_type, entity_data) VALUES (@club_id, @entity_key, @entity_type, @entity_data)",
        {
            ["@club_id"] = clubId,
            ["@entity_key"] = key,
            ["@entity_type"] = entityType,
            ["@entity_data"] = json.encode(payload),
        },
        function(insertId)
            if not insertId then
                if cb then cb(false, "Failed to create entity") end
                return
            end
            club.entities[key] = entityData or {}
            club.entities[key].type = entityType
            StartClubEntity(clubId, key)
            SyncAllClubs(-1)
            if cb then cb(true, key) end
        end
    )
end

function UpdateClubEntity(clubId, entityId, entityData, cb)
    local club = Clubs[clubId]
    if not club then
        if cb then cb(false, "Club not found") end
        return
    end
    local entity = club.entities[entityId]
    if not entity then
        if cb then cb(false, "Entity not found") end
        return
    end
    local nextType = entityData.type or entity.type
    local valid, validationMessage = ValidateEntityData(nextType, entityData)
    if not valid then
        if cb then cb(false, validationMessage or "Invalid entity payload") end
        return
    end
    local payload = NormalizeForDb(entityData)
    payload.type = nil
    MySQL.Async.execute(
        "UPDATE pickle_club_entities SET entity_type = @entity_type, entity_data = @entity_data WHERE club_id = @club_id AND entity_key = @entity_key",
        {
            ["@club_id"] = clubId,
            ["@entity_key"] = entityId,
            ["@entity_type"] = nextType,
            ["@entity_data"] = json.encode(payload),
        },
        function(affectedRows)
            if affectedRows and affectedRows > 0 then
                StopClubEntity(clubId, entityId)
                club.entities[entityId] = entityData
                club.entities[entityId].type = nextType
                StartClubEntity(clubId, entityId)
                SyncAllClubs(-1)
                if cb then cb(true) end
            else
                if cb then cb(false, "Failed to update entity") end
            end
        end
    )
end

function DeleteClubEntity(clubId, entityId, cb)
    local club = Clubs[clubId]
    if not club or not club.entities[entityId] then
        if cb then cb(false, "Entity not found") end
        return
    end
    StopClubEntity(clubId, entityId)
    club.entities[entityId] = nil
    if EntityPlayers[clubId] then
        EntityPlayers[clubId][entityId] = nil
    end
    SyncAllClubs(-1)
    MySQL.Async.execute(
        "DELETE FROM pickle_club_entities WHERE club_id = @club_id AND entity_key = @entity_key",
        {
            ["@club_id"] = clubId,
            ["@entity_key"] = entityId,
        },
        function(affectedRows)
            if cb then cb((affectedRows or 0) > 0) end
        end
    )
end

function LoadAllClubs()
    MySQL.Async.fetchAll("SELECT * FROM pickle_clubs", {}, function(clubRows)
        MySQL.Async.fetchAll("SELECT * FROM pickle_club_entities", {}, function(entityRows)
            local loaded = {}
            for i = 1, #(clubRows or {}) do
                local row = clubRows[i]
                local coords = json.decode(row.coords or "{}") or {}
                loaded[row.id] = {
                    id = row.id,
                    label = row.label,
                    description = row.description or "",
                    coords = NormalizeFromDb(coords),
                    entities = {},
                }
            end
            for i = 1, #(entityRows or {}) do
                local row = entityRows[i]
                local club = loaded[row.club_id]
                if club then
                    local decodedData = json.decode(row.entity_data or "{}") or {}
                    local entityData = NormalizeFromDb(decodedData)
                    entityData.type = row.entity_type
                    club.entities[row.entity_key] = entityData
                end
            end
            Clubs = {}
            for id, clubData in pairs(loaded) do
                RegisterClub(clubData, true)
            end
            SyncAllClubs(-1)
            print(("^2[pickle_clubs]^0 Loaded %s clubs from SQL."):format(#(clubRows or {})))
        end)
    end)
end

RegisterNetEvent("pickle_clubs:renderEntity", function(id, entityId, ...)
    local source = source
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onRender(id, entityId, source, ...)
    if not EntityPlayers[id] then EntityPlayers[id] = {} end
    if not EntityPlayers[id][entityId] then EntityPlayers[id][entityId] = {} end
    for i = 1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        if player == source then
            table.remove(EntityPlayers[id][entityId], i)
            break
        end
    end
    table.insert(EntityPlayers[id][entityId], source)
end)

RegisterNetEvent("pickle_clubs:unrenderEntity", function(id, entityId, ...)
    local source = source
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onUnrender(id, entityId, source, ...)
    if not EntityPlayers[id] then EntityPlayers[id] = {} end
    if not EntityPlayers[id][entityId] then EntityPlayers[id][entityId] = {} end
    for i = 1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        if player == source then
            table.remove(EntityPlayers[id][entityId], i)
            break
        end
    end
end)

RegisterNetEvent("pickle_clubs:createClub", function(payload)
    local src = source
    if not IsPlayerAdmin(src) then return end
    CreateClub(payload, function(success, result)
        if success then
            ShowNotification(src, "Created club #" .. tostring(result))
        else
            ShowNotification(src, result or "Failed to create club")
        end
    end)
end)

RegisterNetEvent("pickle_clubs:updateClub", function(id, payload)
    local src = source
    if not IsPlayerAdmin(src) then return end
    UpdateClub(id, payload, function(success, result)
        if success then
            ShowNotification(src, "Club updated")
        else
            ShowNotification(src, result or "Failed to update club")
        end
    end)
end)

RegisterNetEvent("pickle_clubs:deleteClub", function(id)
    local src = source
    if not IsPlayerAdmin(src) then return end
    DeleteClub(id, function(success)
        if success then
            ShowNotification(src, "Club deleted")
        else
            ShowNotification(src, "Failed to delete club")
        end
    end)
end)

RegisterNetEvent("pickle_clubs:createClubEntity", function(clubId, entityType, entityData)
    local src = source
    if not IsPlayerAdmin(src) then return end
    CreateClubEntity(clubId, entityType, entityData, nil, function(success, result)
        if success then
            ShowNotification(src, ("Added %s entity (%s)"):format(entityType, result))
        else
            ShowNotification(src, result or "Failed to create entity")
        end
    end)
end)

RegisterNetEvent("pickle_clubs:updateClubEntity", function(clubId, entityId, entityData)
    local src = source
    if not IsPlayerAdmin(src) then return end
    UpdateClubEntity(clubId, entityId, entityData, function(success, result)
        if success then
            ShowNotification(src, "Entity updated")
        else
            ShowNotification(src, result or "Failed to update entity")
        end
    end)
end)

RegisterNetEvent("pickle_clubs:deleteClubEntity", function(clubId, entityId)
    local src = source
    if not IsPlayerAdmin(src) then return end
    DeleteClubEntity(clubId, entityId, function(success)
        if success then
            ShowNotification(src, "Entity deleted")
        else
            ShowNotification(src, "Failed to delete entity")
        end
    end)
end)

lib.callback.register("pickle_clubs:checkIsAdmin", function(source)
    return IsPlayerAdmin(source)
end)

AddEventHandler("playerDropped", function()
    local src = source
    for _, entityMap in pairs(EntityPlayers) do
        for _, players in pairs(entityMap) do
            for i = 1, #players do
                if players[i] == src then
                    table.remove(players, i)
                    break
                end
            end
        end
    end
end)

RegisterNetEvent("pickle_clubs:initializePlayer", function()
    local src = source
    SyncAllClubs(src)
end)

RegisterCommand("managebar", function(source)
    if source == 0 then return end
    if not IsPlayerAdmin(source) then
        ShowNotification(source, "You don't have permission to use this command")
        return
    end
    TriggerClientEvent("pickle_clubs:openClubManagement", source)
end, false)

MySQL.ready(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS pickle_clubs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(255) NOT NULL,
            description TEXT NULL,
            coords JSON NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]], {}, function()
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS pickle_club_entities (
                id INT AUTO_INCREMENT PRIMARY KEY,
                club_id INT NOT NULL,
                entity_key VARCHAR(255) NOT NULL,
                entity_type VARCHAR(100) NOT NULL,
                entity_data LONGTEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_club_entity (club_id, entity_key),
                INDEX idx_club_id (club_id)
            )
        ]], {}, function()
            LoadAllClubs()
        end)
    end)
end)