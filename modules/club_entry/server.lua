ClubEntries = {}

function GetClubEntry(id, entityId)
    return ClubEntries[id] and ClubEntries[id][entityId]
end

function RegisterClubEntry(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    local entry = {
        lineThread = false,
        players = {
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
            -- {source = nil},
        },
    }
    if not ClubEntries[id] then ClubEntries[id] = {} end
    ClubEntries[id][entityId] = entry
end

function UnregisterClubEntry(id, entityId)
    if not ClubEntries[id] or not ClubEntries[id][entityId] then return end
    ClubEntries[id][entityId] = nil
end

function IsPlayerInCEL(id, entityId, source)
    local entry = GetClubEntry(id, entityId)
    if not entry then return false end
    for i=1, #entry.players do
        if entry.players[i].source == source then
            return true
        end
    end
    return false
end

function PromptCEL(id, entityId, source)
    TriggerClientEvent("pickle_clubs:promptCEL", source, id, entityId)
    local timeout = 10
    while timeout > 0 do
        timeout = timeout - 1
        if timeout <= 0 or not IsPlayerInCEL(id, entityId, source) then
            break
        end
        Wait(1000)
    end
    print("Player left CEL: " .. id .. " " .. entityId .. " " .. source)
    LeaveCEL(id, entityId, source)
end

function EnsureCELThread(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    if entry.lineThread then return end
    entry.lineThread = true
    CreateThread(function()
        while entry.lineThread do
            local players = entry.players
            if #players <= 0 then
                entry.lineThread = false
                return
            end
            local source = players[1].source
            if not source then 
                LeaveCEL(id, entityId, nil)
            else
                PromptCEL(id, entityId, source)
            end
            Wait(1000)
        end
    end)
end

function CELToTargets(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    local targets = {}
    for i=1, #entry.players do
        table.insert(targets, entry.players[i].source)
    end
    return targets
end

function LeaveCEL(id, entityId, source)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    for i=1, #entry.players do
        if entry.players[i].source == source then
            table.remove(entry.players, i)
            break
        end
    end
    TriggerEntityEvent("pickle_clubs:leaveLine", id, entityId, source, entry.players)
end

lib.callback.register("pickle_clubs:payEntry", function(source)
    return false
end)

RegisterNetEvent("pickle_clubs:enterLine", function(id, entityId)
    local src = source
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    table.insert(entry.players, {
        source = src,
        name = GetPlayerCharacterName(src),
    })
    TriggerEntityEvent("pickle_clubs:enterLine", id, entityId, src, entry.players)
    EnsureCELThread(id, entityId)
end)

RegisterNetEvent("pickle_clubs:leaveLine", function(id, entityId)
    local src = source
    LeaveCEL(id, entityId, src)
end)

CreateThread(function()
    RegisterEntityType("club_entry", {
        label = "Club Entry",
        description = "This is the club entry entity type.",
        onStart = function(id, entityId)
            RegisterClubEntry(id, entityId)
        end,
        onRender = function(id, entityId, source)
            TriggerClientEvent("pickle_clubs:updateClubEntry", source, id, entityId, GetClubEntry(id, entityId))
        end,
        onStop = function(id, entityId)
            UnregisterClubEntry(id, entityId)
        end,
    })
end)