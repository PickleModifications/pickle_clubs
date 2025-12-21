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

function RegisterClubEntry(id, entityId)
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

function UnregisterClubEntry(id, entityId)
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
        ShowInteractText(_L("enter_line_wait"))
        if IsControlJustPressed(1, 51) then
            CurrentLine = nil
            FreezeEntityPosition(PlayerPedId(), false)
            table.remove(entry.players, #entry.players)
        end
    else
        local lineStart = line.coords - (line.forward * playerCount)
        local dist = #(GetEntityCoords(PlayerPedId()) - lineStart)
        DrawMarker(1, lineStart.x, lineStart.y, lineStart.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 0, 0, 255, false, true)
        if dist < 1.25 then
            ShowInteractText("[E] - " .. _L("enter_line"))
            if IsControlJustPressed(1, 51) then
                CurrentLine = {
                    id = id,
                    entityId = entityId,
                }
                table.insert(entry.players, {
                    identifier = "example",
                })
                SetEntityCoords(PlayerPedId(), lineStart.x, lineStart.y, lineStart.z)
                SetEntityRotation(PlayerPedId(), 0.0, 0.0, line.heading, 2, true)
                FreezeEntityPosition(PlayerPedId(), true)
                ClearPedTasksImmediately(PlayerPedId())
            end
        end
    end
end

CreateThread(function()
    -- DEBUG_RAYCAST_DOOR()
    RegisterEntityType("club_entry", {
        label = "Club Entry",
        description = "This is the club entry entity type.",
        onRender = function(id, entityId)
            RegisterClubEntry(id, entityId)
            print("Registered Club Entry: " .. entityId .. " for club: " .. id)
        end,
        onUnrender = function(id, entityId)
            UnregisterClubEntry(id, entityId)
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