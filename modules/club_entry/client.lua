local ClubEntries = {}
local CurrentLine = nil
local IsYeeted = false
local ClubPasses = {}
local CurrentClub = nil

function DEBUG_RAYCAST_DOOR()
    CreateThread(function()
        while true do
        -- Draw a debug raycast to the entity the camera is pointing at, draw a line and display the model above it
            local camCoords = GetGameplayCamCoord()
            local hit, hitCoords, entityHit = GetDirectionCoords(nil, nil, 16)
            if hit and entityHit and DoesEntityExist(entityHit) then
                local model = GetEntityModel(entityHit)
                -- Draw line from camera to hit coords
                DrawLine(camCoords.x, camCoords.y, camCoords.z, hitCoords.x, hitCoords.y, hitCoords.z, 255, 0, 0, 255)
                -- Get position above entity for text
                local entCoords = GetEntityCoords(entityHit)
                local success, screenX, screenY = World3dToScreen2d(entCoords.x, entCoords.y, entCoords.z + 1.0)
                if success then
                    local modelStr = tostring(model) .. " ("..GetEntityType(entityHit)..")"
                    SetTextFont(0)
                    SetTextScale(0.35, 0.35)
                    SetTextColour(255, 0, 0, 255)
                    SetTextOutline()
                    SetTextEntry("STRING")
                    AddTextComponentString("Model: " .. tostring(model))
                    DrawText(screenX, screenY)
                end
            end

            Wait(0) -- short interval for good rendering
        end
    end)
end

function RenderClubEntry(id, entityId)
    if not ClubEntries[id] then ClubEntries[id] = {} end
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    local entry = {
        bouncer = {},
        line = {},
        players = {},
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
    local temp = CreateTennisBall(entity.line.coords.x, entity.line.coords.y, entity.line.coords.z)
    SetEntityRotation(temp, 0.0, 0.0, entity.line.heading, 2, true)
    entry.line.coords = entity.line.coords
    entry.line.heading = entity.line.heading
    local forwardVector, rightVector, upVector, position = GetEntityMatrix(temp)
    entry.line.forward = forwardVector
    entry.line.right = rightVector
    entry.line.barriers = {}
    if entity.line.direction == "forward" then
        local instances = {
            {
                coords = vector3(1.0, -0.5, 0.0),
                heading = 0.0
            },
            {
                coords = vector3(-1.0, -0.5, 0.0),
                heading = 0.0
            },
            {
                coords = vector3(1.0, -2.5, 0.0),
                heading = 0.0
            },
            {
                coords = vector3(-1.0, -2.5, 0.0),
                heading = 0.0
            },
            {
                coords = vector3(2.0, 0.5, 0.0),
                heading = 90.0
            },
        }
        for i=1, #instances do
            local coords = entity.line.coords + (entry.line.forward * instances[i].coords.y) + (entry.line.forward * -1) + (entry.line.right * instances[i].coords.x)
            local barrier = CreateProp(`ba_prop_battle_barrier_02a`, coords.x, coords.y, coords.z + instances[i].coords.z)
            FreezeEntityPosition(barrier, true)
            SetEntityRotation(barrier, 0.0, 0.0, entity.line.heading + 90.0 + instances[i].heading, 2, true)
            SetCanClimbOnEntity(barrier, false)
            table.insert(entry.line.barriers, barrier)
        end
    end
    DeleteScriptObject(temp)
    ClubEntries[id][entityId] = entry
end

function DoesClubEntryExist(id, entityId)
    return ClubEntries[id] and ClubEntries[id][entityId]
end

function UnrenderClubEntry(id, entityId)
    if not DoesClubEntryExist(id, entityId) then return end
    local entry = ClubEntries[id][entityId]
    if DoesEntityExist(entry.bouncer.ped) then
        DeleteEntity(entry.bouncer.ped)
    end
    for i=1, #entry.line.barriers do
        if DoesEntityExist(entry.line.barriers[i]) then
            DeleteEntity(entry.line.barriers[i])
        end
    end
    ClubEntries[id][entityId] = nil
    print("Unregistered Club Entry: " .. entityId .. " for club: " .. id)
end

function GetClubEntry(id, entityId)
    return ClubEntries[id] and ClubEntries[id][entityId]
end

function ClubEntryThread(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    if not CanEnterClub(id) and not IsYeeted then
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local doorCoords = entry.line.coords + (entry.line.forward * 2)
        local dist = #(pcoords - (doorCoords + vector3(0.0, 0.0, 1.0)))
        if dist < (0.5 * (IsPedInAnyVehicle(ped, false) and 2.0 or 1.0)) then
            ShowNotification(_L("club_entry_no_pass"))
            IsYeeted = true
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                DeleteEntity(vehicle)
            end
            local forward = -entry.line.forward
            local force = 15
            SetEntityVelocity(ped, forward.x * force, forward.y * force,  3.0)
            SetTimeout(100, function()
                SetPedToRagdoll(ped, 3000, 3000, 0, false, false, false)
            end)
            SetTimeout(1000, function()
                IsYeeted = false
            end)
        end
        
        -- DrawMarker(1, doorCoords.x, doorCoords.y, doorCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 0, 0, 255, false, true)
    end
end

function RefreshCEL(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    local inLine = false
    local playerCount = 0 
    local source = GetPlayerServerId(PlayerId())
    for i=1, #entry.players do
        local player = entry.players[i]
        if player.source ~= source then
            playerCount = playerCount + 1
        else 
            inLine = true
            if CurrentLine then 
                CurrentLine.position = playerCount + 1
            end
            break
        end
    end
    if not inLine then return end
    local line = entry.line
    local lineStart = line.coords - (line.forward * playerCount)
    SetEntityCoords(PlayerPedId(), lineStart.x, lineStart.y, lineStart.z)
    SetEntityRotation(PlayerPedId(), 0.0, 0.0, line.heading, 2, true)
    FreezeEntityPosition(PlayerPedId(), true)
    ClearPedTasksImmediately(PlayerPedId())
end

function PromptCEL(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    local ped = entry.bouncer.ped
    local pedCoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local heading = GetEntityHeading(ped)
    local coords = pedCoords + (forward * 0.5)
    StartClubPrompt(coords, heading, {
        dialog = {
            speech = "Welcome to the club! It'll cost you $1000 to get in.",
            options = {
                {
                    label = "Freak you man, I'm not paying that shit.",
                    description = "You will be forcibly escorted out of the club.",
                    dialog = {
                        speech = "Sorry, gotta pay up to get in.",
                    }
                },
                {
                    label = "I'll pay it - gotta get the party started.",
                    description = "This will deduct $1000 from your bank account.",
                    dialog = {
                        speech = "ERROR: No speech selected for this.",
                        finish = true,
                        speechSelect = function()
                            if lib.callback.await("pickle_clubs:payEntry", false, id, entityId) then
                                return "Thanks for your business! Enjoy the club!"
                            else
                                return "Sorry, you don't have enough money."
                            end
                        end,
                        onStart = function()
                            print("PAY THE MAN!")
                        end,
                    }
                },
            }
        }
    })
end

function CanEnterClub(id)
    return ClubPasses[id]
end

RegisterNetEvent("pickle_clubs:updateClubEntry", function(id, entityId, entry)
    if not entry then return end
    local localEntry = GetClubEntry(id, entityId)
    if not localEntry then return end
    localEntry.players = entry.players
end)

RegisterNetEvent("pickle_clubs:promptCEL", function(id, entityId)
    PromptCEL(id, entityId)
end)

RegisterNetEvent("pickle_clubs:updateClubPass", function(id, pass)
    ClubPasses[id] = pass
end)

CreateThread(function()
    -- DEBUG_RAYCAST_DOOR()
    RegisterEntityType("club_entry", {
        label = "Club Entry",
        description = "This is the club entry entity type.",
        onRender = function(id, entityId)
            RenderClubEntry(id, entityId)
            print("Registered Club Entry: " .. entityId .. " for club: " .. id)
        end,
        onUnrender = function(id, entityId)
            if CurrentClub and CurrentClub == id then
                CurrentClub = nil
            end
            UnrenderClubEntry(id, entityId)
            print("Unregistered Club Entry: " .. entityId .. " for club: " .. id)
        end,
    })
    while true do
        local wait = 1500
        local pcoords = GetEntityCoords(PlayerPedId())
        local closest = nil
        for k,v in pairs(ClubEntries) do
            for entityId, entity in pairs(v) do
                local dist = #(pcoords - entity.line.coords)
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
            ClubEntryThread(closest.clubId, closest.entityId)
        end
        Wait(wait)
    end
end)