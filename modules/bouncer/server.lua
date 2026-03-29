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

-- Escort: attach victim to bouncer
RegisterNetEvent("pickle_clubs:startEscort", function(targetSource, bouncerSource)
    targetSource = tonumber(targetSource)
    bouncerSource = tonumber(bouncerSource)
    if not targetSource or not bouncerSource then return end
    ShowNotification(targetSource, "You are being escorted by a bouncer")
    TriggerClientEvent("pickle_clubs:escortAttach", targetSource, bouncerSource)
end)

-- Escort: fling victim
RegisterNetEvent("pickle_clubs:flingEscort", function(targetSource, forwardX, forwardY)
    targetSource = tonumber(targetSource)
    if not targetSource then return end
    TriggerClientEvent("pickle_clubs:escortFling", targetSource, forwardX, forwardY)
end)

-- Escort: release victim
RegisterNetEvent("pickle_clubs:stopEscort", function(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource then return end
    TriggerClientEvent("pickle_clubs:escortDetach", targetSource)
end)

-- Revoke all club passes for a player
RegisterNetEvent("pickle_clubs:revokeAllPasses", function(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource then return end
    for clubId, passes in pairs(ClubPasses or {}) do
        if passes[targetSource] then
            SetClubPass(targetSource, clubId, false)
        end
    end
end)

-- Get a player's inventory for search
lib.callback.register("pickle_clubs:getPlayerInventory", function(source, targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource or not Inventory or not Inventory.GetInventory then return {}, "Unknown" end
    local items = Inventory.GetInventory(targetSource)
    for i = 1, #items do
        local item = items[i]
        if Inventory.Items and Inventory.Items[item.name] then
            item.label = Inventory.Items[item.name].label or item.label or item.name
            item.description = Inventory.Items[item.name].description
        end
    end
    local charName = GetPlayerCharacterName and GetPlayerCharacterName(targetSource) or ("Player " .. targetSource)
    return items, charName
end)

CreateThread(function()
    RegisterEntityType("bouncer", {
        label = "Bouncer",
        description = "This is the bouncer entity type.",
        onStart = function(id, entityId)
            RegisterBouncer(id, entityId)
        end,
        onRender = function(id, entityId, source)
            -- SetTimeout(1000, function()
            --     ThrowOutPlayer(source, id)
            -- end)
        end,
        onUnrender = function(id, entityId, source)
        end,
        onStop = function(id, entityId)
            UnregisterBouncer(id, entityId)
        end,
    })
end)