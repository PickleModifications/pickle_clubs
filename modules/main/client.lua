Clubs = {}
LocalClubs = {}
RegisteredEntityTypes = {}

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
        onUnrender = function(...)
            -- TriggerServerEvent("pickle_clubs:unrenderEntity", entityType, ...)
            if data.onUnrender then
                data.onUnrender(...)
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