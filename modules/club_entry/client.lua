local ClubEntries = {}
local CurrentLine = nil

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

function GetClubDoorHash(id, entityId, doorIndex)
    return GetHashKey(('pickle_clubs_%s_%s_%s'):format(id, entityId, doorIndex))
end

function GetLocalClubDoor(id, entityId, doorIndex)
    if not Clubs[id] then return end
    if not Clubs[id].entities[entityId] then return end
    local doorCfg = Clubs[id].entities[entityId].doors[doorIndex]
    if not doorCfg then return end
    local pool = GetGamePool("CObject")
    local closest
    for i=1, #pool do
        local obj = pool[i]
        if GetEntityModel(obj) == doorCfg.model then
            local dist = #(GetEntityCoords(obj) - doorCfg.coords)
            if not closest or dist < closest.dist then
                closest = {
                    obj = obj,
                    dist = dist
                }
            end
        end
    end
    return closest.obj
end

function RenderClubEntry(id, entityId)
    if not ClubEntries[id] then ClubEntries[id] = {} end
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    local entry = {
        doors = {},
        bouncer = {},
        line = {},
        players = {},
    }
    -- TODO entry.doors
    -- TODO entry.bouncer
    -- TODO entry.line
    entry.bouncer.ped = CreateClubNPC(entity.bouncer.ped, entity.bouncer.coords, entity.bouncer.heading)
    for i=1, #entity.doors do
        local doorHash = GetClubDoorHash(id, entityId, i)
        local localDoor = GetLocalClubDoor(id, entityId, i)
        if not localDoor then return end
        local coords = GetEntityCoords(localDoor)
        print("Adding door to system for: " .. doorHash .. " with model: " .. entity.doors[i].model .. " at coords: " .. coords.x .. ", " .. coords.y .. ", " .. coords.z)
        AddDoorToSystem(
            doorHash, 
            entity.doors[i].model, 
            coords.x, 
            coords.y, 
            coords.z, 
            false, 
            false, 
            false
        )
        entry.doors[i] = { locked = false, heading = GetEntityHeading(localDoor) }
        SetTimeout(1000, function()
            SetClubDoorState(id, entityId, i, true)
        end)
    end
    local temp = CreateTennisBall(entity.line.coords.x, entity.line.coords.y, entity.line.coords.z)
    SetEntityRotation(temp, 0.0, 0.0, entity.line.heading, 2, true)
    entry.line.coords = entity.line.coords
    entry.line.heading = entity.line.heading
    entry.line.forward = GetEntityForwardVector(temp)
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
    ClubEntries[id][entityId] = nil
    print("Unregistered Club Entry: " .. entityId .. " for club: " .. id)
end

function GetClubDoorState(id, entityId, doorIndex)
    if not DoesClubEntryExist(id, entityId) then return end
    local entry = ClubEntries[id][entityId]
    if not entry.doors[doorIndex] then return end
    return entry.doors[doorIndex].locked
end

function SetClubDoorState(id, entityId, doorIndex, state)
    if not DoesClubEntryExist(id, entityId) then return end
    local entry = ClubEntries[id][entityId]
    if not entry.doors[doorIndex] then return end
    entry.doors[doorIndex].locked = state
    local doorHash = GetClubDoorHash(id, entityId, doorIndex)
    DoorSystemSetDoorState(doorHash, state and 1 or 0, false, false)
    DoorSystemSetHoldOpen(doorHash, false)
    if state then
        local localDoor = GetLocalClubDoor(id, entityId, doorIndex)
        DoorSystemSetOpenRatio(doorHash, 0.0, true)
        SetEntityRotation(localDoor, 0.0, 0.0, entry.doors[doorIndex].heading, 2, true)
    end
end

function GetClubEntry(id, entityId)
    return ClubEntries[id] and ClubEntries[id][entityId]
end

function ClubEntryThread(id, entityId)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    local playerCount = #entry.players or 0
    local line = entry.line
    if not line then return end
    if CurrentLine then
        if CurrentLine.id ~= id or CurrentLine.entityId ~= entityId then return end
        -- Disable walking
        DisableControlAction(0, 21, true)   -- sprint
        DisableControlAction(0, 22, true)   -- jump
        DisableControlAction(0, 24, true)   -- attack (left mouse)
        DisableControlAction(0, 25, true)   -- aim (right mouse)
        DisableControlAction(0, 68, true)   -- attack 2
        DisableControlAction(0, 37, true)   -- select weapon
        DisableControlAction(0, 44, true)   -- cover
        DisableControlAction(0, 140, true)  -- melee attack alt
        DisableControlAction(0, 141, true)  -- melee attack alt
        DisableControlAction(0, 142, true)  -- melee attack alt
        DisableControlAction(0, 257, true)  -- melee attack alternate
        DisableControlAction(0, 143, true)  -- melee duck
        DisableControlAction(0, 30, true)   -- move left/right
        DisableControlAction(0, 31, true)   -- move up/down
        ShowInteractText(_L("enter_line_wait", CurrentLine.position, #entry.players))
        if IsControlJustPressed(1, 51) then
            TriggerServerEvent("pickle_clubs:leaveLine", id, entityId)
        end
    else
        local lineStart = line.coords - (line.forward * playerCount)
        local dist = #(GetEntityCoords(PlayerPedId()) - lineStart)
        DrawMarker(1, lineStart.x, lineStart.y, lineStart.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 0, 0, 255, false, true)
        if dist < 1.25 then
            ShowInteractText("[E] - " .. _L("enter_line"))
            if IsControlJustPressed(1, 51) then
                TriggerServerEvent("pickle_clubs:enterLine", id, entityId)
            end
        end
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
    if not CurrentLine then return end
    if CurrentLine.id ~= id or CurrentLine.entityId ~= entityId then return end    
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
                            if lib.callback.await("pickle_clubs:payEntry", false, 1000) then
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

RegisterNetEvent("pickle_clubs:enterLine", function(id, entityId, target, newPlayers)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    entry.players = newPlayers
    local source = GetPlayerServerId(PlayerId())
    if source == target then
        CurrentLine = {
            id = id,
            entityId = entityId,
            position = -1,
        }
    end
    RefreshCEL(id, entityId)
end)

RegisterNetEvent("pickle_clubs:leaveLine", function(id, entityId, target, newPlayers)
    local entry = GetClubEntry(id, entityId)
    if not entry then return end
    entry.players = newPlayers
    local source = GetPlayerServerId(PlayerId())
    if source == target then
        CurrentLine = nil
        FreezeEntityPosition(PlayerPedId(), false)
        ClearPedTasksImmediately(PlayerPedId())
        ExitScriptedCamera()
    end
    RefreshCEL(id, entityId)
end)

RegisterNetEvent("pickle_clubs:updateClubEntry", function(id, entityId, entry)
    print("RECIEVED UPDATE FOR CLUB ENTRY: " .. id .. " " .. entityId)
    if not entry then return end
    local localEntry = GetClubEntry(id, entityId)
    if not localEntry then return end
    localEntry.players = entry.players
end)

RegisterNetEvent("pickle_clubs:promptCEL", function(id, entityId)
    PromptCEL(id, entityId)
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
                for i=1, #entity.doors do
                    local dist = #(pcoords - GetEntityCoords(entity.doors[i].obj))
                    if not closest or dist < closest.dist then
                        closest = {
                            clubId = k,
                            entityId = entityId,
                            doorIndex = i,
                        }
                    end
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