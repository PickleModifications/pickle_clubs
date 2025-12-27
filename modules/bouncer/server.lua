Bouncers = {}

function GetBouncer(id, entityId)
    return Bouncers[id] and Bouncers[id][entityId]
end

function RegisterBouncer(id, entityId)
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
        variables = {}
    }
    if not Bouncers[id] then Bouncers[id] = {} end
    Bouncers[id][entityId] = entry
end

function UnregisterBouncer(id, entityId)
    if not Bouncers[id] or not Bouncers[id][entityId] then return end
    Bouncers[id][entityId] = nil
end

function ThrowOutPlayer(source, id)
    local entry, entityId = GetAnyClubEntry(id)
    if not entry then return end
    if not entityId then return end
    TriggerEntityEvent("pickle_clubs:throwOutPlayer", id, entityId, source)
end

RegisterNetEvent("pickle_clubs:throwOutPlayer", function(id)
    local source = source
    ThrowOutPlayer(source, id)
end)

CreateThread(function()
    RegisterEntityType("bouncer", {
        label = "Bouncer",
        description = "This is the bouncer entity type.",
        onStart = function(id, entityId)
            RegisterBouncer(id, entityId)
        end,
        onRender = function(id, entityId, source)
            SetTimeout(1000, function()
                ThrowOutPlayer(source, id)
            end)
        end,
        onUnrender = function(id, entityId, source)
        end,
        onStop = function(id, entityId)
            UnregisterBouncer(id, entityId)
        end,
    })
end)