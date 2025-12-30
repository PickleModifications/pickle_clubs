local ENTITIES = {}
local InteractiveEntityTypes = {}
local CURRENT_ENTITY = nil

function lerp(a, b, t)
    return a + (b - a) * t
end

-- Calculate pour rate based on pitch (tilt angle)
-- Returns a multiplier from 0.0 to 1.0 based on how much the entity is tilted
function CalculatePourRate(pitch)
    -- Pitch is in degrees, where:
    -- 0-90: upright to slightly tilted
    -- 90-180: tilted, pouring starts
    -- 180: fully inverted (maximum pour)
    -- 180-270: tilted back
    -- 270-360: back to upright
    
    -- Normalize pitch to 0-360 range
    pitch = (pitch % 360 + 360) % 360
    
    -- Check if entity is tilted enough to pour (between 90 and 270 degrees)
    if pitch > 90.0 and pitch < 270.0 then
        -- Calculate how far from 90/270 we are
        -- Closer to 180 = more tilt = faster pour
        local normalizedPitch = 0.0
        if pitch <= 180.0 then
            -- Between 90 and 180: normalize from 0 to 1
            normalizedPitch = (pitch - 90.0) / 90.0
        else
            -- Between 180 and 270: normalize from 1 to 0 (mirrored)
            normalizedPitch = (270.0 - pitch) / 90.0
        end
        
        -- Apply a curve to make it feel more natural (ease-in)
        -- At 90/270: rate = 0.0 (barely pouring)
        -- At 180: rate = 1.0 (maximum pour)
        local rate = normalizedPitch * normalizedPitch -- Quadratic curve for smoother feel
        
        -- Ensure minimum pour rate when tilted (so it still pours a little)
        return math.max(0.1, rate)
    end
    
    -- Not tilted enough to pour
    return 0.0
end

-- Draw 3D text at a world position
function DrawText3D(x, y, z, text)
    local success, screenX, screenY = World3dToScreen2d(x, y, z)
    if success then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 255)
        SetTextOutline()
        SetTextEntry("STRING")
        AddTextComponentString(text)
        DrawText(screenX, screenY)
    end
end

-- Calculate the final color from ALL flavor weights in the drink
-- flavorWeights format: {1 = 0.01, 2 = 0.02, 3 = 0.03} where keys are flavor indexes
function CalculateColorFromFlavors(flavorWeights)
    if not flavorWeights or next(flavorWeights) == nil then
        return nil -- No flavors = no color
    end
    
    local totalWeight = 0
    local totalR, totalG, totalB = 0, 0, 0
    
    -- Iterate through ALL flavor indexes that have been poured into the drink
    -- Calculate weighted average of ALL flavors based on their proportions
    for flavorIndex, weight in pairs(flavorWeights) do
        local flavor = Config.Bartender.flavors[flavorIndex]
        if flavor and flavor.color then
            -- Add this flavor's contribution to the total color
            totalWeight = totalWeight + weight
            totalR = totalR + flavor.color[1] * weight
            totalG = totalG + flavor.color[2] * weight
            totalB = totalB + flavor.color[3] * weight
        end
    end
    
    if totalWeight <= 0 then
        return nil
    end
    
    -- Normalize by total weight to get the final color from ALL flavors
    local r = math.floor(totalR / totalWeight)
    local g = math.floor(totalG / totalWeight)
    local b = math.floor(totalB / totalWeight)
    
    -- Check if the weighted average results in white (all three RGB components are high)
    -- This works with any number of flavors and any combination that produces white
    -- For example: red+green+blue, or yellow+blue, or cyan+red, etc.
    local allComponentsHigh = r > 180 and g > 180 and b > 180
    
    if allComponentsHigh then
        -- If all three components are high, produce bright white
        -- Use the average brightness to determine how white it should be
        local avgBrightness = (r + g + b) / 3
        local brightness = math.max(250, math.min(255, avgBrightness))
        return {math.floor(brightness), math.floor(brightness), math.floor(brightness)}
    end
    
    -- Return the weighted average color from ALL flavors
    return {r, g, b}
end

-- Convert RGB (0-255) to HSL (0-360, 0-1, 0-1)
function RGBToHSL(r, g, b)
    r = r / 255.0
    g = g / 255.0
    b = b / 255.0
    
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, l = 0, 0, (max + min) / 2.0
    
    if max ~= min then
        local d = max - min
        s = l > 0.5 and d / (2.0 - max - min) or d / (max + min)
        
        if max == r then
            h = ((g - b) / d + (g < b and 6 or 0)) / 6.0
        elseif max == g then
            h = ((b - r) / d + 2) / 6.0
        else
            h = ((r - g) / d + 4) / 6.0
        end
    end
    
    return h * 360.0, s, l
end

-- Convert HSL (0-360, 0-1, 0-1) to RGB (0-255)
function HSLToRGB(h, s, l)
    h = h / 360.0
    local r, g, b
    
    if s == 0 then
        r, g, b = l, l, l
    else
        local function hue2rgb(p, q, t)
            if t < 0 then t = t + 1 end
            if t > 1 then t = t - 1 end
            if t < 1/6 then return p + (q - p) * 6 * t end
            if t < 1/2 then return q end
            if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
            return p
        end
        
        local q = l < 0.5 and l * (1 + s) or l + s - l * s
        local p = 2 * l - q
        r = hue2rgb(p, q, h + 1/3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1/3)
    end
    
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

-- Check if a color is a primary color (red, green, or blue)
function IsPrimaryColor(color)
    local r, g, b = color[1], color[2], color[3]
    -- Red: high R, low G and B
    local isRed = r > 200 and g < 50 and b < 50
    -- Green: high G, low R and B
    local isGreen = g > 200 and r < 50 and b < 50
    -- Blue: high B, low R and G
    local isBlue = b > 200 and r < 50 and g < 50
    return isRed, isGreen, isBlue
end

-- Check if mixing would result in all three primaries (should produce white)
function WouldProduceWhite(color1, color2)
    -- Simple check: if both colors together have significant amounts of all three RGB components
    -- This catches all cases: primaries, secondaries, or any mix
    local totalR = color1[1] + color2[1]
    local totalG = color1[2] + color2[2]
    local totalB = color1[3] + color2[3]
    
    -- If we have significant amounts of all three components, we have all primaries
    local hasAllComponents = totalR > 150 and totalG > 150 and totalB > 150
    if hasAllComponents then
        return true
    end
    
    -- Also check individual color detection for more accuracy
    local r1, g1, b1 = IsPrimaryColor(color1)
    local r2, g2, b2 = IsPrimaryColor(color2)
    
    -- Check if we have all three primaries between the two colors
    local hasRed = r1 or r2 or color1[1] > 150 or color2[1] > 150
    local hasGreen = g1 or g2 or color1[2] > 150 or color2[2] > 150
    local hasBlue = b1 or b2 or color1[3] > 150 or color2[3] > 150
    
    -- Check if color1 is a mix of two primaries (like yellow = red+green, cyan = green+blue, magenta = red+blue)
    -- Use more lenient thresholds to catch mixed colors
    local c1IsYellow = color1[1] > 80 and color1[2] > 80 and color1[3] < 100
    local c1IsCyan = color1[1] < 100 and color1[2] > 80 and color1[3] > 80
    local c1IsMagenta = color1[1] > 80 and color1[2] < 100 and color1[3] > 80
    
    -- Check if color2 is a mix of two primaries
    local c2IsYellow = color2[1] > 80 and color2[2] > 80 and color2[3] < 100
    local c2IsCyan = color2[1] < 100 and color2[2] > 80 and color2[3] > 80
    local c2IsMagenta = color2[1] > 80 and color2[2] < 100 and color2[3] > 80
    
    -- Check if color2 is a primary (for when color1 is a secondary)
    local c2IsRed = color2[1] > 150 and color2[2] < 100 and color2[3] < 100
    local c2IsGreen = color2[2] > 150 and color2[1] < 100 and color2[3] < 100
    local c2IsBlue = color2[3] > 150 and color2[1] < 100 and color2[2] < 100
    
    -- Check if color1 is a primary (for when color2 is a secondary)
    local c1IsRed = color1[1] > 150 and color1[2] < 100 and color1[3] < 100
    local c1IsGreen = color1[2] > 150 and color1[1] < 100 and color1[3] < 100
    local c1IsBlue = color1[3] > 150 and color1[1] < 100 and color1[2] < 100
    
    -- If one is yellow (red+green) and the other is blue
    if (c1IsYellow and c2IsBlue) or (c2IsYellow and c1IsBlue) then
        return true
    end
    -- If one is cyan (green+blue) and the other is red
    if (c1IsCyan and c2IsRed) or (c2IsCyan and c1IsRed) then
        return true
    end
    -- If one is magenta (red+blue) and the other is green
    if (c1IsMagenta and c2IsGreen) or (c2IsMagenta and c1IsGreen) then
        return true
    end
    
    -- Check if we have all three primaries directly
    if hasRed and hasGreen and hasBlue then
        return true
    end
    
    return false
end

-- Mix two colors in HSL space to preserve vibrancy, or use additive RGB if mixing primaries
function MixColors(color1, color2, weight1, weight2)
    -- First, calculate what the additive RGB mix would be
    local additiveR = math.min(255, math.floor(color1[1] * weight1 + color2[1] * weight2))
    local additiveG = math.min(255, math.floor(color1[2] * weight1 + color2[2] * weight2))
    local additiveB = math.min(255, math.floor(color1[3] * weight1 + color2[3] * weight2))
    
    -- Check if mixing would produce white using the detection function
    -- This detects when all three primaries (red, green, blue) are present
    if WouldProduceWhite(color1, color2) then
        -- All three primaries are present = pure white (255, 255, 255)
        -- Don't calculate based on weights - just return pure white
        return {255, 255, 255}
    end
    
    -- Also check if the additive mix would produce white (all three components are high)
    -- This is a fallback check in case WouldProduceWhite doesn't catch it
    local wouldBeWhite = additiveR > 150 and additiveG > 150 and additiveB > 150
    if wouldBeWhite then
        -- All three components are high = bright white
        -- Ensure it's bright white, not grey
        local brightness = math.max(250, math.min(255, (additiveR + additiveG + additiveB) / 3))
        return {math.floor(brightness), math.floor(brightness), math.floor(brightness)}
    end
    
    -- Otherwise use HSL mixing for vibrant color blending
    local h1, s1, l1 = RGBToHSL(color1[1], color1[2], color1[3])
    local h2, s2, l2 = RGBToHSL(color2[1], color2[2], color2[3])
    
    -- Mix hue (handle circular nature of hue)
    local h = 0
    local dh = math.abs(h2 - h1)
    if dh > 180 then
        if h1 < h2 then
            h1 = h1 + 360
        else
            h2 = h2 + 360
        end
    end
    h = (h1 * weight1 + h2 * weight2) % 360
    
    -- Mix saturation and lightness - ensure we maintain vibrancy
    -- Use weighted average but ensure minimum saturation to prevent white
    local s = (s1 * weight1 + s2 * weight2)
    s = math.max(s, 0.3) -- Ensure minimum saturation of 30% to prevent white
    s = math.min(s, 1.0) -- Clamp to 1.0
    
    -- Mix lightness but keep it in a vibrant range (not too light, not too dark)
    local l = (l1 * weight1 + l2 * weight2)
    l = math.max(l, 0.2) -- Minimum lightness 20%
    l = math.min(l, 0.8) -- Maximum lightness 80% to keep colors vibrant
    
    local r, g, b = HSLToRGB(h, s, l)
    
    -- Final validation: ensure we didn't get white or near-white (unless we should have white)
    if r >= 250 and g >= 250 and b >= 250 then
        -- If result is too close to white, boost saturation and reduce lightness
        s = math.min(s * 1.5, 1.0)
        l = math.max(l * 0.7, 0.3)
        r, g, b = HSLToRGB(h, s, l)
    end
    
    return {r, g, b}
end

function InteractiveEntityThread(entity, data)
    local currentEntity = ENTITIES[entity]
    if not currentEntity then return end
    local entType = InteractiveEntityTypes[currentEntity.type]
    if not entType then return end
    if entType.entityThread then
        entType.entityThread(entity, data)
    end
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
    local currentEntity = ENTITIES[entity]
    if not currentEntity then return end
    local entType = InteractiveEntityTypes[currentEntity.type]
    if not entType then return end
    if entType.unSelected then
        entType.unSelected(entity, data)
    end
end

function RegisterInteractiveEntity(entType, data)
    InteractiveEntityTypes[entType] = data
end

function CreateInteractiveEntity(entType, coords, heading, params)
    -- local entity = CreateEntity(entType, coords, heading, data)
    -- ENTITIES[entity] = data
    if not InteractiveEntityTypes[entType] then return print("^1ERROR: No interactive entity type found for: ", entType) end
    local entityData = {
        type = entType,
        zOffset = 0.01,
    }
    local entity = nil
    local newData = {}
    if InteractiveEntityTypes[entType].init then
        entity, newData = InteractiveEntityTypes[entType].init(coords, heading, entityData, params)
    end
    if not entity then return print("^1ERROR: No entity created for: ", entType) end
    for k,v in pairs(newData or {}) do
        entityData[k] = v
    end
    ENTITIES[entity] = entityData
    print("^2Created interactive entity: ", entType, json.encode(entityData, {indent = true}))
    return entity
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
        init = function(coords, heading, data, params)
            local bottle = CreateProp(`ng_proc_brkbottle_02a`, coords.x, coords.y, coords.z + 0.3, false, false, false)
            SetEntityCollision(bottle, true, true)
            SetEntityHeading(bottle, heading)
            return bottle, {
                color = params.color or {255, 255, 255},
                flavorIndex = params.flavorIndex, -- Index in Config.Bartender.flavors
                progress = params.progress or 0.0,
            }
        end,
        entityThread = function(entity, data)
            local radius = 0.08
            local maxHeight = 0.1575
            local surfaceHeight = 0.01
            local alpha = 128
            local height = ENTITIES[entity].progress * maxHeight
            local rotation = GetEntityRotation(bottle)
            local rx, ry, rz = rotation.x, rotation.y, rotation.z
            local forwardVector, rightVector, upVector, position = GetEntityMatrix(entity)
            local renderCoords = position + (upVector * surfaceHeight)
            local surfaceCoords = renderCoords + (upVector * height)
            local color = ENTITIES[entity].color or {255, 255, 255}
            if ENTITIES[entity].progress > 0.0 then
                DrawMarker(1, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 90.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(28, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(1, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(28, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], alpha, false, false, 2)
            end
        end,
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
                if closestChild and (childEntity.type == "drink") and currentEntity.progress > 0.0 and childEntity.progress < 1.0 then
                    if not currentEntity.ptfx or currentEntity.refreshTime < GetGameTimer() then
                        currentEntity.refreshTime = GetGameTimer() + 2000
                        if currentEntity.ptfx then
                            local ptfxHandle = currentEntity.ptfx
                            SetTimeout(300, function()
                                StopParticleFxLooped(ptfxHandle, false)
                                RemoveParticleFx(ptfxHandle, true)
                            end)
                        end
                        RequestNamedPtfxAsset("cut_family1")
                        while not HasNamedPtfxAssetLoaded("cut_family1") do
                            Wait(0)
                        end
                        UseParticleFxAssetNextCall("cut_family1")
                        currentEntity.ptfx = StartParticleFxLoopedOnEntity("cs_fam1_bourbon_pour", CURRENT_ENTITY, 0.0, 0.0, 0.285, 0.0, 0.0, 0.0, 0.5, false, false, false)
                        SetParticleFxLoopedColour(currentEntity.ptfx, 255, 0, 0, 255)
                    end
                    -- -- Decrease bottle's progress when pouring (based on pitch)
                    -- if currentEntity.progress > 0.0 then
                    --     local pourRate = CalculatePourRate(pitch)
                    --     local basePourAmount = 0.005 -- Maximum pour amount
                    --     local pourAmount = basePourAmount * pourRate
                    --     currentEntity.progress = currentEntity.progress - pourAmount
                    --     if currentEntity.progress < 0.0 then
                    --         currentEntity.progress = 0.0
                    --     end
                    --     if currentEntity.ptfx then
                    --         local scale = 0.5 * pourRate
                    --         SetParticleFxLoopedScale(currentEntity.ptfx, scale)
                    --     end
                    -- end
                    -- ENTITIES[CURRENT_ENTITY].progress = currentEntity.progress
                    if (childEntity.type == "drink") and childEntity.progress < 1.0 then
                        local oldProgress = childEntity.progress
                        -- Calculate pour rate based on pitch (how much the bottle is tilted)
                        local pourRate = CalculatePourRate(pitch)
                        local basePourAmount = 0.005 -- Maximum pour amount
                        local pourAmount = basePourAmount * pourRate
                        childEntity.progress = childEntity.progress + pourAmount
                        ENTITIES[closestChild.entity].progress = childEntity.progress
                        
                        -- Add flavor weight based on what's being poured
                        local bottleFlavorIndex = currentEntity.flavorIndex
                        if bottleFlavorIndex then
                            -- Initialize flavorWeights if it doesn't exist
                            if not childEntity.flavorWeights then
                                childEntity.flavorWeights = {}
                            end
                            
                            -- Calculate the proportion this pour adds (pourAmount / total progress)
                            local flavorProportion = pourAmount / childEntity.progress
                            
                            -- Adjust existing weights to account for the new liquid
                            -- Existing weights need to be scaled down: oldWeight * (oldProgress / newProgress)
                            local scaleFactor = oldProgress / childEntity.progress
                            for flavorIndex, weight in pairs(childEntity.flavorWeights) do
                                childEntity.flavorWeights[flavorIndex] = weight * scaleFactor
                            end
                            
                            -- Add the new flavor proportion
                            if not childEntity.flavorWeights[bottleFlavorIndex] then
                                childEntity.flavorWeights[bottleFlavorIndex] = 0
                            end
                            childEntity.flavorWeights[bottleFlavorIndex] = childEntity.flavorWeights[bottleFlavorIndex] + flavorProportion
                            
                            -- Update the entity data
                            ENTITIES[closestChild.entity].flavorWeights = childEntity.flavorWeights
                        end
                    end
                elseif currentEntity.ptfx then
                    StopParticleFxLooped(currentEntity.ptfx, false)
                    RemoveParticleFx(currentEntity.ptfx, true)
                    currentEntity.ptfx = nil
                end
            elseif currentEntity.ptfx then
                StopParticleFxLooped(currentEntity.ptfx, false)
                RemoveParticleFx(currentEntity.ptfx, true)
                currentEntity.ptfx = nil
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
    RegisterInteractiveEntity("drink", {
        init = function(coords, heading, data, params)
            local drink = CreateProp(`prop_tall_glass`, coords.x, coords.y, coords.z + 0.3, false, false, false)
            SetEntityCollision(drink, true, true)
            SetEntityHeading(drink, heading)
            return drink, {
                progress = params.progress or 0.0,
                flavorWeights = params.flavorWeights or {}, -- Track proportion of each flavor: {1 = 0.01, 2 = 0.02, ...}
            }
        end,
        entityThread = function(entity, data)
            local radius = 0.08
            local maxHeight = 0.1875
            local surfaceHeight = 0.01
            local alpha = 128
            local height = ENTITIES[entity].progress * maxHeight
            local rotation = GetEntityRotation(entity)
            local rx, ry, rz = rotation.x, rotation.y, rotation.z
            local forwardVector, rightVector, upVector, position = GetEntityMatrix(entity)
            local renderCoords = position + (upVector * surfaceHeight)
            local surfaceCoords = renderCoords + (upVector * height)
            -- Calculate color from flavor weights
            local calculatedColor = CalculateColorFromFlavors(ENTITIES[entity].flavorWeights)
            local color = calculatedColor or {255, 255, 255}
            if ENTITIES[entity].progress > 0.0 then
                DrawMarker(1, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 90.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(28, renderCoords.x, renderCoords.y, renderCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(1, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius, radius, height, color[1], color[2], color[3], alpha, false, false, 2)
                DrawMarker(28, surfaceCoords.x, surfaceCoords.y, surfaceCoords.z, upVector.x, upVector.y, upVector.z, 270.0, -ry, rz, radius * 0.5, radius * 0.5, 0.001, color[1], color[2], color[3], alpha, false, false, 2)
            end
            
            -- Draw flavor percentages above the drink
            local flavorWeights = ENTITIES[entity].flavorWeights
            if flavorWeights and next(flavorWeights) ~= nil then
                local textY = position.z + 0.15 -- Start above the drink
                local textLines = {}
                
                -- Collect all flavors with their percentages
                for flavorIndex, weight in pairs(flavorWeights) do
                    if weight > 0.001 then -- Only show flavors with significant amount
                        local flavor = Config.Bartender.flavors[flavorIndex]
                        local percentage = math.floor(weight * 100 + 0.5) -- Round to nearest integer
                        if flavor then
                            local label = flavor.label or ("Flavor " .. flavorIndex)
                            table.insert(textLines, {index = flavorIndex, text = label .. ": " .. percentage .. "%", weight = weight})
                        else
                            table.insert(textLines, {index = flavorIndex, text = "Flavor " .. flavorIndex .. ": " .. percentage .. "%", weight = weight})
                        end
                    end
                end
                
                -- Sort by weight (descending) so most prominent flavors are shown first
                table.sort(textLines, function(a, b) return a.weight > b.weight end)
                
                -- Draw each line
                for i, lineData in ipairs(textLines) do
                    local textCoords = position + (upVector * (0.15 + (i - 1) * 0.03))
                    DrawText3D(textCoords.x, textCoords.y, textCoords.z, lineData.text)
                end
            end
        end,
        selectedThread = function(entity, data)
            local pitch = data.pitch
            local currentEntity = ENTITIES[entity]
            local minimum, maximum = data.minimum, data.maximum
            if math.abs(pitch) > 90.0 and math.abs(pitch) < 270.0 and currentEntity.progress > 0.0 then
                -- Calculate pour rate based on pitch (how much the drink is tilted)
                local pourRate = CalculatePourRate(pitch)
                local basePourAmount = 0.005 -- Maximum pour amount
                local pourAmount = basePourAmount * pourRate
                currentEntity.progress = currentEntity.progress - pourAmount
                -- Ensure progress doesn't go below 0
                if currentEntity.progress <= 0.0 then
                    currentEntity.progress = 0.0
                    -- Reset flavor weights when drink is fully poured out
                    currentEntity.flavorWeights = {}
                    ENTITIES[entity].flavorWeights = {}
                end
                if not currentEntity.ptfx or currentEntity.refreshTime < GetGameTimer() then
                    currentEntity.refreshTime = GetGameTimer() + 2000
                    if currentEntity.ptfx then
                        local ptfxHandle = currentEntity.ptfx
                        SetTimeout(300, function()
                            StopParticleFxLooped(ptfxHandle, false)
                            RemoveParticleFx(ptfxHandle, true)
                        end)
                    end
                    RequestNamedPtfxAsset("cut_family1")
                    while not HasNamedPtfxAssetLoaded("cut_family1") do
                        Wait(0)
                    end
                    UseParticleFxAssetNextCall("cut_family1")
                    currentEntity.ptfx = StartParticleFxLoopedOnEntity("cs_fam1_bourbon_pour", CURRENT_ENTITY, 0.0, 0.0, 0.285, 0.0, 0.0, 0.0, 2.5, false, false, false)
                    SetParticleFxLoopedColour(currentEntity.ptfx, 255, 0, 0, 255)
                else
                    local scale = 4 * pourRate
                    SetParticleFxLoopedScale(currentEntity.ptfx, scale)
                    SetParticleFxLoopedOffsets(currentEntity.ptfx, (0.045 * (pourRate + -1)) * (math.abs(pitch) < 180 and -1 or 1), 0.0, 0.285 + (0.05 * (pourRate + -1)), 0.0, 0.0, 0.0)
                end
            elseif currentEntity.ptfx then
                StopParticleFxLooped(currentEntity.ptfx, false)
                RemoveParticleFx(currentEntity.ptfx, true)
                currentEntity.ptfx = nil
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
    CreateInteractiveEntity("drink", coords + (rightVector * -0.5), heading, {
        progress = 1.0,
        flavorWeights = {
            [1] = 1.0,
        },
    })
    for i=1, #Config.Bartender.flavors do
        local flavor = Config.Bartender.flavors[i]
        CreateInteractiveEntity("bottle", coords + (rightVector * (0.5)) + (rightVector * (-0.1 * i)), heading, {
            color = flavor.color,
            flavorIndex = i, -- Store the flavor index
            progress = 1.0,
        })
    end
    CreateThread(function()
        local pitch = 0.0
        local lastX, lastY = -1, -1
        while true do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 51, true)
            local screenX, screenY = GetNuiCursorPosition()
            local x, y = GetActualScreenResolution()
            screenX = screenX / x
            screenY = screenY / y
            for k,v in pairs(ENTITIES) do
                InteractiveEntityThread(k, {
                    coords = coords,
                    heading = heading,
                    minimum = minimum,
                    maximum = maximum,
                })
            end
            if not CURRENT_ENTITY then
                local hit, dragCoords, entityHit = GetCursorRaycast(camCoords, vector3(0.0, 0.0, heading))
                -- DrawMarker(1, dragCoords.x, dragCoords.y, dragCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.1, 0.1, 255, 0, 0, 255, false, false, 2)
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
                if IsDisabledControlPressed(0, 25) then
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
                    v.zOffset = v.zOffset - 0.050
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
        for k,v in pairs(ENTITIES) do
            DeleteEntity(k)
        end
        ENTITIES = {}
    end
end)