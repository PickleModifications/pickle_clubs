local Bouncers = {}
local ClosestBouncer = nil
local ThrowOutScenes = {}
local PLAYING_BOUNCER_SCENE = false
function ThrowOutPlayerScene(clubId, entityId, id)
    if ThrowOutScenes[id] then 
        for i=1, #ThrowOutScenes[id].entities do
            DeleteEntity(ThrowOutScenes[id].entities[i])
        end
        ThrowOutScenes[id] = nil
    end
    local clubEntry = GetClubEntry(clubId, entityId)
    if not clubEntry then return end
    ThrowOutScenes[id] = {
        clubId = clubId,
        entityId = entityId,
        entities = {},
    }
    local heading = clubEntry.line.heading - 90.0
    local baseY = 0.5
    local ped = CreateClubNPC("bouncer_1", clubEntry.line.coords + (clubEntry.line.forward * baseY) + (clubEntry.line.right * -0.3), heading + 290.0)
    FreezeEntityPosition(ped, false)
    table.insert(ThrowOutScenes[id].entities, ped)
    PlayAnim(ThrowOutScenes[id].entities[1], "mini@strip_club@throwout_d@", "throwout_d_bouncer_a", 8.0, -1.0, -1, 1, 0, true, true, true)
    if id == GetPlayerServerId(PlayerId()) then
        PLAYING_BOUNCER_SCENE = true
        local camCoords = clubEntry.line.coords + (clubEntry.line.right * 6.0)
        CreateScriptedCamera()
        SetCamParams(CurrentCamera, camCoords.x, camCoords.y, camCoords.z + 0.5,
            0.0, 0.0, heading + 180.0, 45.0, 
            0, 0, 0, 2
        )
        SetEntityNoCollisionEntity(PlayerPedId(), ped)
        SetEntityCoords(PlayerPedId(), clubEntry.line.coords + (clubEntry.line.right * -0.2))
        SetEntityRotation(PlayerPedId(), 0.0, 0.0, heading - 10.0, 2, true)
        PlayAnim(PlayerPedId(), "mini@strip_club@throwout_d@", "throwout_d_victim", 8.0, -1.0, -1, 0, 0, true, true, true)
        SetTimeout(4000, function()
            ExitScriptedCamera()
        end)
        SetTimeout(6000, function()
            ClearPedTasks(PlayerPedId())
            PLAYING_BOUNCER_SCENE = false
        end)
    end
    SetTimeout(4000, function()
        local opacity = 255 
        while opacity > 0 do
            opacity = opacity - 5
            if opacity <= 0 then
                opacity = 0
            end
            SetEntityAlpha(ThrowOutScenes[id].entities[1], opacity, false)
            Wait(0)
        end
        DeleteEntity(ThrowOutScenes[id].entities[1])
        ThrowOutScenes[id] = nil
    end)
end

function RenderBouncer(id, entityId)
    if not Bouncers[id] then Bouncers[id] = {} end
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    local entry = {
        bouncer = {
            ped = nil,
            coords = entity.bouncer.coords,
            heading = entity.bouncer.heading,
        },
    }
    -- TODO entry.doors
    -- TODO entry.bouncer
    -- TODO entry.line
    entry.interact = CreateInteraction({
        label = _L("enter_line"),
        coords = entity.bouncer.coords + vector3(0.0, 0.0, 1.0), 
        heading = entity.bouncer.heading,
    }, function()
        PromptCEL(id, entityId)
    end)
    entry.bouncer.ped = CreateClubNPC(entity.bouncer.ped, entity.bouncer.coords, entity.bouncer.heading)
    Bouncers[id][entityId] = entry
end

function DoesBouncerExist(id, entityId)
    return Bouncers[id] and Bouncers[id][entityId]
end

function UnrenderBouncer(id, entityId)
    if not DoesBouncerExist(id, entityId) then return end
    local entry = Bouncers[id][entityId]
    if DoesEntityExist(entry.bouncer.ped) then
        DeleteEntity(entry.bouncer.ped)
    end
    Bouncers[id][entityId] = nil
    print("Unregistered Bouncer: " .. entityId .. " for club: " .. id)
end

function GetBouncer(id, entityId)
    return Bouncers[id] and Bouncers[id][entityId]
end

function BouncerThread(id, entityId)
    local progressPerTick = 0.5
    local data = GetBouncer(id, entityId)
    if CanEnterClub(id) or PLAYING_BOUNCER_SCENE then return end
    if not data then return end
    if not ClosestBouncer or ClosestBouncer.clubId ~= id or ClosestBouncer.entityId ~= entityId then
        ClosestBouncer = {
            visible = false,
            clubId = id,
            entityId = entityId,
            progress = 0,
            ticks = 0
        }
    end
    if ClosestBouncer.ticks <= 0 then
        ClosestBouncer.visible = HasEntityClearLosToEntityInFront(data.bouncer.ped, PlayerPedId())
        ClosestBouncer.ticks = 100
    end
    ClosestBouncer.ticks = ClosestBouncer.ticks - 1
    if ClosestBouncer.visible then
        ClosestBouncer.progress = ClosestBouncer.progress + progressPerTick
    else
        ClosestBouncer.progress = ClosestBouncer.progress - progressPerTick
    end
    if ClosestBouncer.progress >= 100 and not ClosestBouncer.detected then  
        ClosestBouncer.progress = 100
        ClosestBouncer.detected = true
        SetTimeout(1000, function()
            ClosestBouncer = nil
            TriggerServerEvent("pickle_clubs:throwOutPlayer", id)
        end)
    end
    if ClosestBouncer.progress <= 0 then
        ClosestBouncer.progress = 0
    end
    local progress = ClosestBouncer.progress or 0
    if progress > 0 or ClosestBouncer.detected then
        local onScreen, screenX, screenY = GetHudScreenPositionFromWorldPosition(data.bouncer.coords.x, data.bouncer.coords.y, data.bouncer.coords.z + 2.25)
        local icon_scale = 1.5
        local text_scale = 1.0
        local r, g, b = 255, 255, 255
        -- Progress bar color: white to yellow to red depending on progress
        if ClosestBouncer.detected or progress >= 100 then
            r = 255
            g = 0
            b = 0
        elseif progress < 50 then
            -- White to Yellow
            local t = progress / 50
            r = math.floor(255)
            g = math.floor(255 * t + 255 * (1 - t)) -- 255
            b = math.floor(255 * (1 - t))
        else
            -- Yellow to Red
            local t = (progress - 50) / 50
            r = 255
            g = math.floor(255 * (1 - t))
            b = 0
        end
        -- Icon
        -- RequestStreamedTextureDict("assassinations", false)
        -- DrawSprite("assassinations", "targetquestion", screenX, screenY - 0.015, 0.015 * icon_scale, 0.025 * icon_scale, 0.0, r, g, b, 255)
        -- Text
        SetTextFont(0)
        SetTextOutline()
        SetTextColour(r, g, b, 255)
        SetTextCentre(true)
        SetTextScale(0.0, text_scale)
        SetTextEntry("STRING")
        AddTextComponentString((progress >= 100 or ClosestBouncer.detected) and "!" or "?")
        DrawText(screenX, screenY)
    end
end

RegisterNetEvent("pickle_clubs:throwOutPlayer", function(clubId, entityId, serverId)
    ThrowOutPlayerScene(clubId, entityId, serverId)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        for k,v in pairs(ThrowOutScenes) do
            for i=1, #v.entities do
                DeleteEntity(v.entities[i])
            end
        end
        ThrowOutScenes = {}

    end
end)

CreateThread(function()
    -- DEBUG_RAYCAST_DOOR()
    RegisterEntityType("bouncer", {
        label = "Bouncer",
        description = "This is the bouncer entity type.",
        onRender = function(id, entityId)
            RenderBouncer(id, entityId)
            print("Registered Bouncer: " .. entityId .. " for club: " .. id)
        end,
        onUnrender = function(id, entityId)
            if CurrentClub and CurrentClub == id then
                CurrentClub = nil
            end
            UnrenderBouncer(id, entityId)
            print("Unregistered Bouncer: " .. entityId .. " for club: " .. id)
        end,
    })
    while true do
        local wait = 1500
        local pcoords = GetEntityCoords(PlayerPedId())
        local closest = nil
        for k,v in pairs(Bouncers) do
            for entityId, entity in pairs(v) do
                local dist = #(pcoords - entity.bouncer.coords)
                if not closest or dist < closest.dist then
                    closest = {
                        clubId = k,
                        entityId = entityId,
                    }
                end
            end
        end
        if closest then
            wait = 0
            BouncerThread(closest.clubId, closest.entityId)
        else
            ClosestBouncer = nil
        end
        Wait(wait)
    end
end)