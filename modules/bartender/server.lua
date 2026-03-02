-- Multi-Station Bartender Server
-- Bartender entities are stored in Clubs[id].entities[entityId].

-- Per-station runtime data: stationId -> {orderQueue, serviceActive, interactionData, spawnThread, timerThread}
StationData = {}
StationRegistry = {} -- stationId -> persisted station metadata from club entity
StationControllers = {} -- stationId -> {interaction = {source=...}, service = {source=...}}

local function BuildStationId(clubId, entityId)
    return ("%s:%s"):format(clubId, entityId)
end

local function GetPrimaryJobName(club)
    local jobs = club and club.jobs or {}
    for i = 1, #jobs do
        if jobs[i].primary and type(jobs[i].name) == "string" and jobs[i].name ~= "" then
            return jobs[i].name
        end
    end
    return nil
end

local function BuildStationFromEntity(clubId, entityId)
    local club = Clubs[clubId]
    if not club then return nil end
    local entity = club.entities and club.entities[entityId]
    if not entity or entity.type ~= "bartender" or not entity.bartender then return nil end

    local bartender = entity.bartender
    local coords = bartender.coords
    if type(coords) == "table" then
        coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    end

    return {
        id = BuildStationId(clubId, entityId),
        clubId = clubId,
        entityId = entityId,
        coords = coords,
        heading = bartender.heading or 0.0,
        blip = bartender.blip or (Config.Bartender.defaultBlip or {
            name = "Bartending Station",
            color = 5,
            sprite = 52,
            scale = 0.8,
            visible = true,
        }),
        society_name = GetPrimaryJobName(club),
        society_percentage = club.society_percentage or 0,
    }
end

local function RegisterBartenderStation(clubId, entityId)
    local station = BuildStationFromEntity(clubId, entityId)
    if not station then return end
    StationRegistry[station.id] = station
    TriggerClientEvent("pickle_clubs:syncStations", -1, StationRegistry)
end

local function UnregisterBartenderStation(clubId, entityId)
    local stationId = BuildStationId(clubId, entityId)
    if StationData[stationId] and StationData[stationId].serviceActive then
        StopBartenderService(stationId)
    end
    StationData[stationId] = nil
    StationControllers[stationId] = nil
    StationRegistry[stationId] = nil
    TriggerClientEvent("pickle_clubs:syncStations", -1, StationRegistry)
    TriggerClientEvent("pickle_clubs:removeStation", -1, stationId)
end

local function GetStation(stationId)
    return StationRegistry[stationId]
end

local function IsStationControlled(stationId, controlType)
    if not StationControllers[stationId] then return false end
    if controlType then
        return StationControllers[stationId][controlType] ~= nil
    end
    for _, controller in pairs(StationControllers[stationId]) do
        if controller then return true end
    end
    return false
end

local function SetStationController(stationId, source, controlType)
    if not GetStation(stationId) then return false, "Station not found" end
    if IsStationControlled(stationId, controlType) then
        return false, "Station is already controlled"
    end
    if not StationControllers[stationId] then StationControllers[stationId] = {} end
    StationControllers[stationId][controlType] = {
        source = source,
        type = controlType,
    }
    return true
end

local function ClearStationController(stationId, controlType)
    if not StationControllers[stationId] then return end
    if controlType then
        StationControllers[stationId][controlType] = nil
        local hasAny = false
        for _, controller in pairs(StationControllers[stationId]) do
            if controller then
                hasAny = true
                break
            end
        end
        if not hasAny then
            StationControllers[stationId] = nil
        end
    else
        StationControllers[stationId] = nil
    end
end

-- Generate all possible drink item names from configured flavors
function GenerateAllDrinkItems()
    local items = {}
    local flavors = Config.Bartender.flavors
    
    if not flavors or #flavors == 0 then
        return items
    end
    
    -- Helper function to sanitize flavor name for item name
    local function sanitizeFlavorName(label)
        local name = string.lower(label)
        name = string.gsub(name, "%s+", "_") -- Replace spaces with underscores
        name = string.gsub(name, "[^%w_]", "") -- Remove special characters
        return name
    end
    
    -- Generate single flavor drinks
    for i = 1, #flavors do
        local flavor = flavors[i]
        if flavor and flavor.label then
            local itemName = sanitizeFlavorName(flavor.label) .. "_drink"
            table.insert(items, {
                name = itemName,
                label = flavor.label .. " Drink",
                type = "single",
                flavorIndex = i
            })
        end
    end
    
    -- Generate mixed drinks (all combinations of 2 flavors, sorted alphabetically)
    for i = 1, #flavors do
        for j = i + 1, #flavors do
            local flavor1 = flavors[i]
            local flavor2 = flavors[j]
            if flavor1 and flavor1.label and flavor2 and flavor2.label then
                local name1 = sanitizeFlavorName(flavor1.label)
                local name2 = sanitizeFlavorName(flavor2.label)
                
                -- Sort alphabetically
                local sortedNames = {name1, name2}
                table.sort(sortedNames)
                
                local itemName = sortedNames[1] .. "_" .. sortedNames[2] .. "_bar_drink"
                table.insert(items, {
                    name = itemName,
                    label = flavor1.label .. "-" .. flavor2.label .. " Bar Drink",
                    type = "mixed",
                    flavorIndices = {i, j}
                })
            end
        end
    end
    
    return items
end

-- Get list of all possible drink items (exported for use in item files)
function GetAllDrinkItems()
    return GenerateAllDrinkItems()
end

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
        print("ERROR: Could not calculate spawn/walk positions for order")
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
    local station = GetStation(stationId)
    if not station then
        print("ERROR: Station " .. stationId .. " not found")
        return false
    end
    
    -- Check if station already has active service
    if StationData[stationId] and StationData[stationId].serviceActive then
        print("ERROR: Bartender service already active for station " .. stationId)
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
        print("ERROR: Bartender service not active for station " .. stationId)
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

    local success, message = SetStationController(stationId, source, "service")
    if not success then
        TriggerClientEvent("pickle_clubs:stationControlDenied", source, message or "Station is already in use")
        return
    end
    
    if StartBartenderService(stationId, coords, heading) then
        print("Bartender service started by player: " .. source .. " for station: " .. stationId)
    else
        -- Clear controller if service failed to start
        ClearStationController(stationId, "service")
        TriggerClientEvent("pickle_clubs:stationControlDenied", source, "Failed to start service")
    end
end)

RegisterNetEvent("pickle_clubs:stopBartenderService", function(stationId)
    local source = source
    
    if StopBartenderService(stationId) then
        ClearStationController(stationId, "service")
        print("Bartender service stopped by player: " .. source .. " for station: " .. stationId)
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
        -- Get station data to check for society configuration
        local station = GetStation(stationId)
        local orderPayment = Config.Bartender.orderPayment
        local playerPayment = orderPayment
        local societyPayment = 0
        
        -- Check if society is configured and calculate split payment
        if station and station.society_name and station.society_name ~= "" and station.society_percentage and station.society_percentage > 0 then
            -- Calculate society payment
            societyPayment = math.floor(orderPayment * (station.society_percentage / 100))
            -- Player gets the remainder
            playerPayment = orderPayment - societyPayment
            
            -- Send payment to society
            if societyPayment > 0 then
                AddSocietyMoney(station.society_name, societyPayment)
            end
        end
        
        -- Pay the player
        AddMoney(source, playerPayment, "money")
        
        -- Get random feedback message
        local feedbackMessages = Config.Bartender.orderConversations.correct
        local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
        
        -- Remove order from queue (ExpireOrder handles deletion and queue update)
        ExpireOrder(stationId, orderId)
        
        -- Send success feedback
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, true, feedback, playerPayment)
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

-- Track registered drink items to avoid duplicate registrations
local RegisteredDrinkItems = {}

-- Track equipped drinks for syncing
local EquippedDrinksServer = {} -- source -> {coords, flavorWeights, color, progress, lastUpdate}

-- Register usable item handler for drink items
local function RegisterDrinkItemIfNeeded(itemName)
    if RegisteredDrinkItems[itemName] then
        return -- Already registered
    end
    
    -- Check if item name matches drink pattern
    if string.match(itemName, "_drink$") or string.match(itemName, "_bar_drink$") then
        RegisterUsableItem(itemName, function(source, item)
            -- Get metadata from item
            local metadata = Config.FrameworkSettings.usableItemMetadata(item, item)
            local flavorWeights = metadata and metadata.flavorWeights or {}
            
            -- Remove item from inventory when used
            Inventory.RemoveItem(source, itemName, 1)
            
            -- Trigger client event to use the drink (alcohol is added server-side when they actually drink, via drinkConsumed)
            TriggerClientEvent("pickle_clubs:useDrinkItem", source, itemName, flavorWeights)
        end)
        RegisteredDrinkItems[itemName] = true
    end
end

RegisterNetEvent("pickle_clubs:giveDrinkItem", function(itemName, flavorWeights)
    local source = source
    
    if not itemName or not flavorWeights then
        return
    end
    
    -- Check if player can carry the item
    if Inventory.CanCarryItem and not Inventory.CanCarryItem(source, itemName, 1) then
        ShowNotification(source, "You cannot carry this item")
        return
    end
    
    -- Create metadata with flavorWeights for later use
    local metadata = {
        flavorWeights = flavorWeights
    }
    
    -- Register the item as usable if not already registered
    RegisterDrinkItemIfNeeded(itemName)
    
    -- Give item to player
    Inventory.AddItem(source, itemName, 1, metadata)
    ShowNotification(source, "You received a " .. itemName)
end)

RegisterNetEvent("pickle_clubs:setStationController", function(stationId, controlType)
    local src = source
    local success, message = SetStationController(stationId, src, controlType)
    if not success then
        TriggerClientEvent("pickle_clubs:stationControlDenied", src, message)
        return
    end
end)

RegisterNetEvent("pickle_clubs:clearStationController", function(stationId, controlType)
    ClearStationController(stationId, controlType)
end)

RegisterNetEvent("pickle_clubs:requestStationControllerStates", function()
    local src = source
    for stationId, _ in pairs(StationRegistry) do
        if IsStationControlled(stationId, "interaction") then
            TriggerClientEvent("pickle_clubs:hideStationRegister", src, stationId)
        else
            TriggerClientEvent("pickle_clubs:showStationRegister", src, stationId)
        end
    end
end)

RegisterNetEvent("pickle_clubs:requestStations", function()
    local src = source
    TriggerClientEvent("pickle_clubs:syncStations", src, StationRegistry)
end)

-- Generate item files on resource start
local function GenerateItemFiles()
    local allItems = GenerateAllDrinkItems()
    local resourceName = GetCurrentResourceName()
    
    if #allItems == 0 then
        print("^1[pickle_clubs]^0 No drink items to generate!")
        return
    end
    
    -- Generate QBCore format
    local qbcoreContent = "-- Auto-generated drink items for QBCore\n"
    qbcoreContent = qbcoreContent .. "-- Add these to your qb-core/shared/items.lua file\n\n"
    for i = 1, #allItems do
        local item = allItems[i]
        qbcoreContent = qbcoreContent .. "['" .. item.name .. "'] = {\n"
        qbcoreContent = qbcoreContent .. "    ['name'] = '" .. item.name .. "',\n"
        qbcoreContent = qbcoreContent .. "    ['label'] = '" .. item.label .. "',\n"
        qbcoreContent = qbcoreContent .. "    ['weight'] = 200,\n"
        qbcoreContent = qbcoreContent .. "    ['type'] = 'item',\n"
        qbcoreContent = qbcoreContent .. "    ['image'] = 'drink.png',\n"
        qbcoreContent = qbcoreContent .. "    ['unique'] = false,\n"
        qbcoreContent = qbcoreContent .. "    ['useable'] = true,\n"
        qbcoreContent = qbcoreContent .. "    ['shouldClose'] = true,\n"
        qbcoreContent = qbcoreContent .. "    ['combinable'] = nil,\n"
        qbcoreContent = qbcoreContent .. "    ['description'] = '" .. item.label .. " from the bar.'\n"
        qbcoreContent = qbcoreContent .. "},\n"
    end
    
    -- Generate ox_inventory format
    local oxContent = "-- Auto-generated drink items for ox_inventory\n"
    oxContent = oxContent .. "-- Add these to your ox_inventory/data/items.lua file\n\n"
    for i = 1, #allItems do
        local item = allItems[i]
        oxContent = oxContent .. "['" .. item.name .. "'] = {\n"
        oxContent = oxContent .. "    label = '" .. item.label .. "',\n"
        oxContent = oxContent .. "    weight = 200,\n"
        oxContent = oxContent .. "    stack = true,\n"
        oxContent = oxContent .. "    description = '" .. item.label .. " from the bar.'\n"
        oxContent = oxContent .. "},\n"
    end
    
    -- Generate ESX SQL format
    local esxContent = "-- Auto-generated drink items for ESX\n"
    esxContent = esxContent .. "-- Run these SQL commands in your database\n\n"
    for i = 1, #allItems do
        local item = allItems[i]
        local sqlName = string.gsub(item.name, "'", "''") -- Escape single quotes
        local sqlLabel = string.gsub(item.label, "'", "''")
        esxContent = esxContent .. "INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES ('" .. sqlName .. "', '" .. sqlLabel .. "', 200, 0, 1);\n"
    end
    
    -- Write files
    local qbcorePath = "__INSTALL/drink_items/qbcore.lua"
    local oxPath = "__INSTALL/drink_items/ox_inventory.lua"
    local esxPath = "__INSTALL/drink_items/esx.sql"
    
    SaveResourceFile(resourceName, qbcorePath, qbcoreContent, -1)
    SaveResourceFile(resourceName, oxPath, oxContent, -1)
    SaveResourceFile(resourceName, esxPath, esxContent, -1)
    
    print("^2[pickle_clubs]^0 Generated " .. #allItems .. " drink items in __INSTALL/drink_items/")
    print("^3  - qbcore.lua")
    print("^3  - ox_inventory.lua")
    print("^3  - esx.sql")
end

-- Export function to get all drink items (for item file generation)
exports("GetAllDrinkItems", GetAllDrinkItems)
exports("GetStation", GetStation)
exports("IsStationControlled", IsStationControlled)
exports("SetStationController", SetStationController)
exports("ClearStationController", ClearStationController)

CreateThread(function()
    RegisterEntityType("bartender", {
        label = "Bartender",
        description = "Bartending station entity for club gameplay.",
        onStart = function(id, entityId)
            RegisterBartenderStation(id, entityId)
        end,
        onRender = function(id, entityId, source)
            local stationId = BuildStationId(id, entityId)
            local station = StationRegistry[stationId]
            if station then
                TriggerClientEvent("pickle_clubs:syncStations", source, {
                    [stationId] = station
                }, true)
            end
        end,
        onUnrender = function(id, entityId, source)
            local stationId = BuildStationId(id, entityId)
            TriggerClientEvent("pickle_clubs:removeStation", source, stationId)
        end,
        onStop = function(id, entityId)
            UnregisterBartenderStation(id, entityId)
        end,
    })
end)

-- Register all possible drink items and generate item files on resource start
CreateThread(function()
    Wait(1000) -- Wait for config to load
    
    -- Generate item files first
    GenerateItemFiles()
    
    -- Then register all items as usable
    local allItems = GenerateAllDrinkItems()
    print("^2[pickle_clubs]^0 Registering " .. #allItems .. " drink items...")
    for i = 1, #allItems do
        local item = allItems[i]
        RegisterDrinkItemIfNeeded(item.name)
    end
    print("^2[pickle_clubs]^0 All drink items registered!")
end)

-- Sync equipped drink to nearby players
RegisterNetEvent("pickle_clubs:syncEquippedDrink", function(coords, flavorWeights, color, progress)
    local source = source
    
    -- Update server-side tracking
    EquippedDrinksServer[source] = {
        coords = coords,
        flavorWeights = flavorWeights,
        color = color,
        progress = progress or 1.0,
        lastUpdate = GetGameTimer()
    }
    
    -- Sync to all nearby players (client will filter by distance)
    TriggerClientEvent("pickle_clubs:syncEquippedDrinkUpdate", -1, source, coords, flavorWeights, color, progress or 1.0)
end)

-- Periodic sync thread for equipped drinks
CreateThread(function()
    while true do
        Wait(1000) -- Update every second
        local currentTime = GetGameTimer()
        
        for sourceId, drinkData in pairs(EquippedDrinksServer) do
            -- Remove stale entries (older than 5 seconds)
            if currentTime - (drinkData.lastUpdate or 0) > 5000 then
                EquippedDrinksServer[sourceId] = nil
                TriggerClientEvent("pickle_clubs:removeEquippedDrink", -1, sourceId)
            else
                -- Sync to all players periodically (client will filter by distance)
                TriggerClientEvent("pickle_clubs:syncEquippedDrinkUpdate", -1, sourceId, drinkData.coords, drinkData.flavorWeights, drinkData.color, drinkData.progress or 1.0)
            end
        end
    end
end)

-- Handle player removing equipped drink
RegisterNetEvent("pickle_clubs:removeEquippedDrinkSync", function()
    local source = source
    if EquippedDrinksServer[source] then
        EquippedDrinksServer[source] = nil
        TriggerClientEvent("pickle_clubs:removeEquippedDrink", -1, source)
    end
end)

-- Handle scaled alcohol when player actually drinks (holds E); amount is proportion consumed 0-1
RegisterNetEvent("pickle_clubs:drinkConsumed", function(amount)
    local source = source
    if not amount or amount <= 0 then return end
    if amount > 1.0 then amount = 1.0 end
    if Config.Drinks and Config.Drinks.alcoholPerDrink and Config.Drinks.alcoholPerDrink > 0 and AddAlcohol then
        local scaled = math.floor(Config.Drinks.alcoholPerDrink * amount + 0.5)
        if scaled > 0 then
            AddAlcohol(source, scaled)
        end
    end
end)

-- Handle removing drink item from inventory when finished
RegisterNetEvent("pickle_clubs:removeDrinkItem", function(itemName)
    local source = source
    Inventory.RemoveItem(source, itemName, 1)
end)

-- Cleanup on player disconnect
AddEventHandler("playerDropped", function()
    local source = source
    if EquippedDrinksServer[source] then
        EquippedDrinksServer[source] = nil
        TriggerClientEvent("pickle_clubs:removeEquippedDrink", -1, source)
    end
    for stationId, controllers in pairs(StationControllers) do
        for controlType, controller in pairs(controllers) do
            if controller and controller.source == source then
                ClearStationController(stationId, controlType)
            end
        end
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
        StationRegistry = {}
        StationControllers = {}
        
        -- Clear equipped drinks
        EquippedDrinksServer = {}
        TriggerClientEvent("pickle_clubs:removeEquippedDrink", -1, -1) -- Remove all (playerId -1 means all)
    end
end)
