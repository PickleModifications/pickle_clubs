-- Multi-Station Bartender Server
-- Import station management functions (will be available after management module loads)

-- Per-station data: stationId -> {orderQueue, serviceActive, interactionData, spawnThread, timerThread}
StationData = {}

-- Calculate forwardVector from heading using trigonometry
function CalculateForwardVector(heading)
    -- Convert heading (degrees) to radians
    local headingRad = math.rad(heading)
    -- Calculate forward vector (x = sin(heading), y = -cos(heading), z = 0)
    local forwardX = math.sin(headingRad)
    local forwardY = -math.cos(headingRad)
    local forwardZ = 0.0
    return vector3(forwardX, forwardY, forwardZ)
end

function CalculateSpawnPosition(stationId)
    local stationData = StationData[stationId]
    if not stationData or not stationData.interactionData then return nil end
    
    local coords = stationData.interactionData.coords
    local heading = stationData.interactionData.heading
    local forwardVector = CalculateForwardVector(heading)
    
    -- Ensure coords is vector3
    if type(coords) == "table" then
        coords = vector3(coords.x, coords.y, coords.z)
    end
    return coords + (forwardVector * Config.Bartender.orderSpawnOffset)
end

function CalculateWalkPosition(stationId, queueIndex)
    local stationData = StationData[stationId]
    if not stationData or not stationData.interactionData then return nil end
    
    local coords = stationData.interactionData.coords
    local heading = stationData.interactionData.heading
    local forwardVector = CalculateForwardVector(heading)
    
    -- Calculate rightVector for queue positioning
    local rightVector = vector3(math.cos(math.rad(heading + 90)), math.sin(math.rad(heading + 90)), 0.0)
    
    -- Ensure coords is vector3
    if type(coords) == "table" then
        coords = vector3(coords.x, coords.y, coords.z)
    end
    
    -- First NPC at walkOffset, others offset along rightVector
    local basePos = coords + (forwardVector * -1.5)
    if queueIndex > 0 then
        basePos = basePos + (rightVector * (Config.Bartender.orderQueueSpacing * queueIndex))
    end
    return basePos - vector3(0.0, 0.0, 1.0)
end

function GenerateDrinkOrder()
    local flavors = Config.Bartender.flavors
    if not flavors or #flavors == 0 then return "Unknown Drink", {} end
    
    -- Randomly select 1-2 flavors
    local numFlavors = math.random(1, 2)
    local selectedFlavorIndices = {}
    local selectedFlavorLabels = {}
    
    -- Select unique flavors
    local availableIndices = {}
    for i = 1, #flavors do
        table.insert(availableIndices, i)
    end
    
    for i = 1, numFlavors do
        if #availableIndices == 0 then break end
        local randomIndex = math.random(1, #availableIndices)
        local flavorIndex = availableIndices[randomIndex]
        table.insert(selectedFlavorIndices, flavorIndex)
        table.insert(selectedFlavorLabels, flavors[flavorIndex].label)
        table.remove(availableIndices, randomIndex)
    end
    
    -- Create drink name
    local drinkName = ""
    if #selectedFlavorLabels == 1 then
        drinkName = selectedFlavorLabels[1]
    else
        drinkName = selectedFlavorLabels[1] .. "-" .. selectedFlavorLabels[2]
    end
    
    return drinkName, selectedFlavorIndices
end

function CreateOrder()
    local orderId = GetGameTimer() .. "_" .. math.random(1000, 9999)
    local drinkName, requiredFlavorIndices = GenerateDrinkOrder()
    local order = {
        id = orderId,
        drinkName = drinkName,
        requiredFlavorIndices = requiredFlavorIndices,
        timer = Config.Bartender.orderTimerDuration,
        createdAt = GetGameTimer(),
        stationId = nil, -- Will be set when added to queue
    }
    return order
end

function SpawnNextOrder(stationId)
    local stationData = StationData[stationId]
    if not stationData or not stationData.serviceActive then return end
    
    -- Check queue length
    if #stationData.orderQueue >= Config.Bartender.maxActiveOrders then return end
    
    local order = CreateOrder()
    order.stationId = stationId
    -- Add to end of queue
    table.insert(stationData.orderQueue, order)
    local queueIndex = #stationData.orderQueue - 1 -- 0-based index for positioning
    
    -- Calculate positions
    local spawnPos = CalculateSpawnPosition(stationId)
    local walkPos = CalculateWalkPosition(stationId, queueIndex)
    
    if not spawnPos or not walkPos then
        print("^1ERROR: Could not calculate spawn/walk positions for order")
        -- Remove from queue
        for i = 1, #stationData.orderQueue do
            if stationData.orderQueue[i].id == order.id then
                table.remove(stationData.orderQueue, i)
                break
            end
        end
        return
    end
    
    -- Select random NPC model
    local npcModels = Config.Bartender.orderNPCs
    local npcModel = npcModels[math.random(1, #npcModels)]
    
    -- Trigger spawn event to all clients with stationId
    TriggerClientEvent("pickle_clubs:spawnOrderNPC", -1, {
        stationId = stationId,
        orderId = order.id,
        drinkName = order.drinkName,
        timer = order.timer,
        spawnCoords = spawnPos,
        walkCoords = walkPos,
        npcModel = npcModel,
        queueIndex = queueIndex,
        heading = stationData.interactionData.heading,
    })
    
    -- Update current order display (only first in queue)
    UpdateCurrentOrderDisplay(stationId)
end

function UpdateCurrentOrderDisplay(stationId)
    local stationData = StationData[stationId]
    if not stationData then return end
    
    -- First order in queue is the current order
    if #stationData.orderQueue > 0 then
        local currentOrder = stationData.orderQueue[1]
        TriggerClientEvent("pickle_clubs:updateOrder", -1, {
            stationId = stationId,
            orderName = currentOrder.drinkName,
            timeRemaining = currentOrder.timer,
            active = true,
        })
    else
        TriggerClientEvent("pickle_clubs:updateOrder", -1, {
            stationId = stationId,
            active = false,
        })
    end
end

function RemoveOrderFromQueue(stationId, orderId)
    local stationData = StationData[stationId]
    if not stationData then return false end
    
    -- Find and remove order from queue
    for i = 1, #stationData.orderQueue do
        if stationData.orderQueue[i].id == orderId then
            table.remove(stationData.orderQueue, i)
            -- Send updated queue indices to clients
            local queueData = {}
            for j = 1, #stationData.orderQueue do
                queueData[stationData.orderQueue[j].id] = j - 1 -- 0-based index
            end
            TriggerClientEvent("pickle_clubs:updateQueuePositions", -1, stationId, stationData.interactionData.heading, queueData)
            return true
        end
    end
    return false
end

function ExpireOrder(stationId, orderId)
    -- Delete NPC on all clients
    TriggerClientEvent("pickle_clubs:deleteOrderNPC", -1, stationId, orderId)
    
    -- Remove from queue
    RemoveOrderFromQueue(stationId, orderId)
    
    -- Update display
    UpdateCurrentOrderDisplay(stationId)
end

function StartBartenderService(stationId, coords, heading)
    -- Check if station exists (use management module exports)
    
    local station = exports["pickle_clubs"]:GetStation(stationId)
    if not station then
        print("^1ERROR: Station " .. stationId .. " not found")
        return false
    end
    
    -- Check if station already has active service
    if StationData[stationId] and StationData[stationId].serviceActive then
        print("^1ERROR: Bartender service already active for station " .. stationId)
        return false
    end
    
    -- Initialize station data if needed
    if not StationData[stationId] then
        StationData[stationId] = {
            orderQueue = {},
            serviceActive = false,
            interactionData = nil,
        }
    end
    
    StationData[stationId].serviceActive = true
    -- Ensure coords is vector3
    if type(coords) == "table" then
        coords = vector3(coords.x, coords.y, coords.z)
    end
    StationData[stationId].interactionData = {
        coords = coords,
        heading = heading,
    }
    
    -- Clear any existing orders
    StationData[stationId].orderQueue = {}
    
    -- Start order timer thread
    StationData[stationId].timerThread = CreateThread(function()
        while StationData[stationId] and StationData[stationId].serviceActive do
            Wait(1000) -- Update every second
            
            -- Update timers
            local expiredOrders = {}
            for i = 1, #StationData[stationId].orderQueue do
                local order = StationData[stationId].orderQueue[i]
                order.timer = order.timer - 1
                if order.timer <= 0 then
                    table.insert(expiredOrders, order.id)
                end
            end
            
            -- Expire orders
            for i = 1, #expiredOrders do
                ExpireOrder(stationId, expiredOrders[i])
            end
            
            -- Update display
            UpdateCurrentOrderDisplay(stationId)
        end
    end)
    
    -- Start spawn thread
    StationData[stationId].spawnThread = CreateThread(function()
        while StationData[stationId] and StationData[stationId].serviceActive do
            Wait(Config.Bartender.orderSpawnInterval * 1000)
            if StationData[stationId] and StationData[stationId].serviceActive then
                SpawnNextOrder(stationId)
            end
        end
    end)
    
    -- Spawn first order immediately
    SpawnNextOrder(stationId)
    
    return true
end

function StopBartenderService(stationId)
    local stationData = StationData[stationId]
    if not stationData or not stationData.serviceActive then
        print("^1ERROR: Bartender service not active for station " .. stationId)
        return false
    end
    
    stationData.serviceActive = false
    
    -- Cleanup all orders
    for i = 1, #stationData.orderQueue do
        TriggerClientEvent("pickle_clubs:deleteOrderNPC", -1, stationId, stationData.orderQueue[i].id)
    end
    stationData.orderQueue = {}
    
    -- Cleanup all NPCs on all clients for this station
    TriggerClientEvent("pickle_clubs:cleanupAllOrders", -1, stationId)
    
    -- Clear order display
    TriggerClientEvent("pickle_clubs:updateOrder", -1, {
        stationId = stationId,
        active = false,
    })
    
    return true
end

-- Events
RegisterNetEvent("pickle_clubs:startBartenderService", function(stationId, coords, heading)
    local source = source
    
    -- Request station control via management module
    local success, message = exports["pickle_clubs"]:SetStationController(stationId, source, "service")
    if not success then
        TriggerClientEvent("pickle_clubs:stationControlDenied", source, message or "Station is already in use")
        return
    end
    
    if StartBartenderService(stationId, coords, heading) then
        print("^2Bartender service started by player: " .. source .. " for station: " .. stationId)
    else
        -- Clear controller if service failed to start
        exports["pickle_clubs"]:ClearStationController(stationId, "service")
        TriggerClientEvent("pickle_clubs:stationControlDenied", source, "Failed to start service")
    end
end)

RegisterNetEvent("pickle_clubs:stopBartenderService", function(stationId)
    local source = source
    
    if StopBartenderService(stationId) then
        -- Clear station control via management module
        exports["pickle_clubs"]:ClearStationController(stationId, "service")
        print("^2Bartender service stopped by player: " .. source .. " for station: " .. stationId)
    end
end)

function ValidateDrink(stationId, orderId, flavorWeights)
    local stationData = StationData[stationId]
    if not stationData then return false, "Station not found" end
    
    -- Find order in queue
    local order = nil
    for i = 1, #stationData.orderQueue do
        if stationData.orderQueue[i].id == orderId then
            order = stationData.orderQueue[i]
            break
        end
    end
    
    if not order then
        return false, "Order not found"
    end
    local requiredFlavors = order.requiredFlavorIndices
    
    if not requiredFlavors or #requiredFlavors == 0 then
        return false, "Invalid order requirements"
    end
    
    -- Calculate total weight of all flavors in drink
    local totalWeight = 0
    for flavorIndex, weight in pairs(flavorWeights) do
        totalWeight = totalWeight + weight
    end
    
    if totalWeight < 0.5 then
        return false, "Drink not full enough"
    end
    
    -- Check if drink has all required flavors (with minimum threshold)
    local requiredWeight = 0
    for i = 1, #requiredFlavors do
        local flavorIndex = requiredFlavors[i]
        -- Ensure flavorIndex is a number for comparison
        local weight = flavorWeights[tonumber(flavorIndex)] or flavorWeights[flavorIndex] or 0
        if weight < 0.01 then
            return false, "Missing required flavor"
        end
        requiredWeight = requiredWeight + weight
    end
    
    -- Calculate percentage of required flavors
    local requiredPercentage = requiredWeight / totalWeight
    
    -- For single-flavor orders, require 85%+ of that flavor (allows for minor mixing)
    -- For multi-flavor orders, require 70%+ to be the required flavors
    local threshold = #requiredFlavors == 1 and 0.85 or 0.70
    
    if requiredPercentage < threshold then
        return false, "Too many extra flavors"
    end
    
    return true, "Correct"
end

RegisterNetEvent("pickle_clubs:submitDrink", function(stationId, orderId, flavorWeights)
    local source = source
    
    local stationData = StationData[stationId]
    if not stationData then
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, false, "Station not found")
        return
    end
    
    -- Check if order exists and is first in queue (current order)
    if #stationData.orderQueue == 0 or stationData.orderQueue[1].id ~= orderId then
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, false, "This is not the current order")
        return
    end
    
    local isValid, message = ValidateDrink(stationId, orderId, flavorWeights)
    
    if isValid then
        -- Pay the player
        AddMoney(source, Config.Bartender.orderPayment, "money")
        
        -- Get random feedback message
        local feedbackMessages = Config.Bartender.orderConversations.correct
        local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
        
        -- Remove order from queue (ExpireOrder handles deletion and queue update)
        ExpireOrder(stationId, orderId)
        
        -- Send success feedback
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, true, feedback, Config.Bartender.orderPayment)
    else
        -- Get random feedback message
        ShowNotification(source, message)
        local feedbackMessages = Config.Bartender.orderConversations.incorrect
        local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
        
        -- Send failure feedback (don't expire order, let them try again)
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, false, feedback)
    end
end)

RegisterNetEvent("pickle_clubs:orderCompleted", function(stationId, orderId)
    -- Legacy event, now handled by submitDrink
    if StationData[stationId] then
        ExpireOrder(stationId, orderId)
    end
end)

-- Cleanup station data when station is deleted
RegisterNetEvent("pickle_clubs:stationDeleted", function(stationId)
    if StationData[stationId] then
        StopBartenderService(stationId)
        StationData[stationId] = nil
    end
end)

-- Cleanup all station data on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        -- Stop all active services and cleanup
        for stationId, stationData in pairs(StationData) do
            if stationData.serviceActive then
                StopBartenderService(stationId)
            end
        end
        
        -- Clear all station data
        StationData = {}
    end
end)
