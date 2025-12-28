local TEMP_ENTITIES = {}
ENTITIES = {}
InteractiveEntityTypes = {}
CURRENT_ENTITY = nil

function CreateBottle(coords, heading, progress)
    local bottle = CreateProp(`ng_proc_brkbottle_02a`, coords.x, coords.y, coords.z + 0.3, false, false, false)
    SetEntityCollision(bottle, true, true)
    SetEntityHeading(bottle, heading)
    TEMP_ENTITIES[bottle] = {
        progress = progress or 0.0,
    }
    local radius = 0.08
    local maxHeight = 0.1575
    local surfaceHeight = 0.01
    -- SetEntityVelocity(bottle, 0.0, 0.0, 1.0)
    local color = {255, 0, 0, 55}
    CreateThread(function()
        while true do
            local height = TEMP_ENTITIES[bottle].progress * maxHeight
            local rotation = GetEntityRotation(bottle)
            local rx, ry, rz = rotation.x, rotation.y, rotation.z
            local forwardVector, rightVector, upVector, position = GetEntityMatrix(bottle)
            local renderCoords = position + (upVector * surfaceHeight)
            local surfaceCoords = renderCoords + (upVector * height)
            if TEMP_ENTITIES[bottle].progress > 0.0 then
                DrawMarker(1, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 90.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(28, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(1, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(28, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], color[4], false, false, 2)
            end
            Wait(0)
        end
    end)
    return bottle
end

function CreateDrink(coords, heading, progress)
    local drink = CreateProp(`prop_tall_glass`, coords.x, coords.y, coords.z + 0.3, false, false, false)
    SetEntityCollision(drink, true, true)
    SetEntityHeading(drink, heading)
    TEMP_ENTITIES[drink] = {
        progress = 1.0,
    }
    local radius = 0.08
    local maxHeight = 0.1875
    local surfaceHeight = 0.01
    -- SetEntityVelocity(bottle, 0.0, 0.0, 1.0)
    local color = {255, 0, 0, 55}
    CreateThread(function()
        while true do
            local height = TEMP_ENTITIES[drink].progress * maxHeight
            local rotation = GetEntityRotation(drink)
            local rx, ry, rz = rotation.x, rotation.y, rotation.z
            local forwardVector, rightVector, upVector, position = GetEntityMatrix(drink)
            local renderCoords = position + (upVector * surfaceHeight)
            local surfaceCoords = renderCoords + (upVector * height)
            if TEMP_ENTITIES[drink].progress > 0.0 then
                DrawMarker(1, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 90.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(28, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(1, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], color[4], false, false, 2)
                DrawMarker(28, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], color[4], false, false, 2)
            end
            Wait(0)
        end
    end)
    return drink
end

function lerp(a, b, t)
    return a + (b - a) * t
end

function SelectedInteractiveEntityThread(entity, data)
    local currentEntity = ENTITIES[entity]
    if not currentEntity then return end
    local entType = InteractiveEntityTypes[currentEntity.type]
    if not entType then return end
    if entType.selectedThread then
        entType.selectedThread(entity, data)
    end
end

function UnselectedInteractiveEntity(entity, data)
    print("P1")
    local currentEntity = ENTITIES[entity]
    if not currentEntity then return end
    print("P2")
    local entType = InteractiveEntityTypes[currentEntity.type]
    if not entType then return end
    print("P3")
    if entType.unSelected then
        print("P4")
        entType.unSelected(entity, data)
    end
end

function RegisterInteractiveEntity(entType, data)
    InteractiveEntityTypes[entType] = data
end

CreateThread(function()
    local coords = vector3(128.0734, -1283.1941, 29.2905)
    local heading = 119.4825
    local temp = CreateTennisBall(coords.x, coords.y, coords.z)
    SetEntityRotation(temp, 0.0, 0.0, heading, 2, true)
    local forwardVector, rightVector, upVector, position = GetEntityMatrix(temp)
    DeleteEntity(temp)
    CreateScriptedCamera()
    local camCoords = coords + (forwardVector * -0.5) + vector3(0.0, 0.0, 0.4)
    SetCamParams(CurrentCamera, camCoords.x, camCoords.y, camCoords.z,
        0.0, 0.0, heading, 90.0, 
        0, 0, 0, 2
    )
    RegisterInteractiveEntity("bottle", {
        selectedThread = function(entity, data)
            local pitch = data.pitch
            local currentEntity = ENTITIES[entity]
            local minimum, maximum = data.minimum, data.maximum
            if math.abs(pitch) > 90.0 and math.abs(pitch) < 270.0 then
                local closestChild = nil
                for k,v in pairs(ENTITIES) do
                    if k ~= CURRENT_ENTITY then
                        local forwardVector, rightVector, upVector, position = GetEntityMatrix(CURRENT_ENTITY)
                        local currentCoords = GetEntityCoords(CURRENT_ENTITY) + (upVector * 0.25)
                        local childCoords = GetEntityCoords(k)
                        -- DrawMarker(28, currentCoords.x, currentCoords.y, currentCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.05, 0.05, 255, 0, 0, 255, false, false, 2)
                        local distance = #(vector3(currentCoords.x, currentCoords.y, 0.0) - vector3(childCoords.x, childCoords.y, 0.0))
                        if (not closestChild and distance < 0.05) or (closestChild and distance < closestChild.distance) then
                            if currentCoords.z > (childCoords.z + ((maximum.z - minimum.z))) then
                                closestChild = {
                                    entity = k,
                                    distance = distance,
                                }
                            end
                        end
                    end
                end
                local childEntity = closestChild and ENTITIES[closestChild.entity] or nil
                if closestChild and currentEntity.progress > 0.0 and childEntity.progress < 1.0 then
                    if currentEntity.progress > 0.0 then
                        currentEntity.progress = currentEntity.progress - 0.005
                    end
                    if not currentEntity.ptfx then
                        RequestNamedPtfxAsset("cut_family1")
                        while not HasNamedPtfxAssetLoaded("cut_family1") do
                            Wait(0)
                        end
                        UseParticleFxAssetNextCall("cut_family1")
                        currentEntity.ptfx = StartParticleFxLoopedOnEntity("cs_fam1_bourbon_pour", CURRENT_ENTITY, 0.0, 0.0, 0.285, 0.0, 0.0, 0.0, 0.5, false, false, false)
                        SetParticleFxLoopedColour(currentEntity.ptfx, 255, 0, 0, 255)
                    end
                    TEMP_ENTITIES[CURRENT_ENTITY].progress = currentEntity.progress
                    if childEntity.type == "bottle" and childEntity.progress < 1.0 then
                        childEntity.progress = childEntity.progress + 0.005
                        TEMP_ENTITIES[closestChild.entity].progress = childEntity.progress
                    end
                else
                    if currentEntity.ptfx then
                        StopParticleFxLooped(currentEntity.ptfx, false)
                        RemoveParticleFx(currentEntity.ptfx, true)
                        currentEntity.ptfx = nil
                    end
                end
            end
        end,
        unSelected = function(entity, data)
            local currentEntity = ENTITIES[entity]
            if not currentEntity then return end
            if currentEntity.ptfx then
                StopParticleFxLooped(currentEntity.ptfx, false)
                RemoveParticleFx(currentEntity.ptfx, true)
                currentEntity.ptfx = nil
            end
        end,
    })
    ENTITIES[CreateDrink(coords + (rightVector * -0.5), heading)] = {
        type = "drink",
        progress = 0.0,
        zOffset = 0.01,
        ptfx = nil,
    }
    ENTITIES[CreateBottle(coords + (rightVector * -0.25), heading)] = {
        type = "bottle",
        progress = 0.0,
        zOffset = 0.01,
        ptfx = nil,
    }
    ENTITIES[CreateBottle(coords, heading, 1.0)] = {
        type = "bottle",
        progress = 1.0,
        zOffset = 0.01,
        ptfx = nil,
    }
    CreateThread(function()
        local pitch = 0.0
        local lastX, lastY = -1, -1
        while true do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 51, true)
            local screenX, screenY = GetNuiCursorPosition()
            local x, y = GetActualScreenResolution()
            screenX = screenX / x
            screenY = screenY / y
            if not CURRENT_ENTITY then
                local dragCoords = coords + (rightVector * lerp(-0.85, 0.85, screenX)) - (upVector * (screenY - 1)) + (forwardVector * -0.5)
                local hit, dragCoords, entityHit = GetCursorRaycast(camCoords, vector3(0.0, 0.0, heading))
                DrawMarker(1, dragCoords.x, dragCoords.y, dragCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 0, 0, 255, false, false, 2)
                if IsDisabledControlJustPressed(0, 24)  then
                    if hit and DoesEntityExist(entityHit) and ENTITIES[entityHit] then
                        CURRENT_ENTITY = entityHit
                        pitch = GetEntityRotation(CURRENT_ENTITY).x
                    end
                end
                SetMouseCursorThisFrame()
            else
                local currentEntity = ENTITIES[CURRENT_ENTITY]
                local minimum, maximum = GetModelDimensions(GetEntityModel(CURRENT_ENTITY))
                local dragCoords = coords + (rightVector * lerp(-0.85, 0.85, screenX)) - (upVector * (screenY - 1))
                SelectedInteractiveEntityThread(CURRENT_ENTITY, {
                    coords = coords,
                    heading = heading,
                    minimum = minimum,
                    maximum = maximum,
                    dragCoords = dragCoords,
                    pitch = pitch,
                })
                if IsDisabledControlPressed(0, 51) then
                    local normal = GetDisabledControlNormal(0, 1) * 60.0
                    pitch = pitch + normal
                    pitch = (pitch % 360 + 360) % 360
                    SetEntityRotation(CURRENT_ENTITY, 0.0, pitch, heading, 2, true)
                    if lastX == -1 then
                        lastX = screenX
                        lastY = screenY
                    end
                else
                    SetMouseCursorThisFrame()
                    if lastX ~= -1 then
                        screenX = lastX
                        screenY = lastY
                        SetCursorLocation(lastX, lastY)
                        lastX = -1
                        lastY = -1
                    else
                        local forwardVector, rightVector, upVector, position = GetEntityMatrix(CURRENT_ENTITY)
                        local propCoords = dragCoords
                        currentEntity.zOffset = GetEntityCoords(CURRENT_ENTITY).z - coords.z
                        SetEntityCoordsNoOffset(CURRENT_ENTITY, propCoords.x, propCoords.y, propCoords.z - (maximum.z - minimum.z) * 0.5)
                        if not IsDisabledControlPressed(0, 24) then
                            UnselectedInteractiveEntity(CURRENT_ENTITY)
                            CURRENT_ENTITY = nil
                        end
                    end
                end
            end
            for k,v in pairs(ENTITIES) do
                if CURRENT_ENTITY ~= k and (v.zOffset > 0.0 or v.zOffset < 0.0) then
                    v.zOffset = v.zOffset - 0.030
                    if v.zOffset <= 0.0 then
                        v.zOffset = 0.0
                        SetEntityRotation(k, 0.0, 0.0, heading, 2, true)
                    end
                    SetEntityCoordsNoOffset(k, GetEntityCoords(k).x, GetEntityCoords(k).y, coords.z + v.zOffset)
                end
            end
            Wait(0)
        end
    end)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        for k,v in pairs(TEMP_ENTITIES) do
            DeleteEntity(k)
        end
        TEMP_ENTITIES = {}
    end
end)