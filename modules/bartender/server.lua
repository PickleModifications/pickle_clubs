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

local function GetClubIdFromStationId(stationId)
    if type(stationId) ~= "string" then return nil end
    local clubIdStr = stationId:match("^(%d+):")
    return clubIdStr and tonumber(clubIdStr) or nil
end

local function GetClubDrinkMenuForStation(stationId)
    local clubId = GetClubIdFromStationId(stationId)
    if not clubId or not GetClubDrinkMenu then return nil end
    return GetClubDrinkMenu(clubId)
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

-- Ensure StationData exists and timer is running (for player orders and/or NPC service)
local function EnsureStationData(stationId)
    if StationData[stationId] then return end
    local station = GetStation(stationId)
    if not station then return end
    local coords = station.coords
    if type(coords) == "table" then
        coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    end
    StationData[stationId] = {
        orderQueue = {},
        serviceActive = false,
        interactionData = {
            coords = coords,
            heading = station.heading or 0.0,
        },
    }
    CreateThread(function()
        while StationData[stationId] do
            Wait(1000)
            local sd = StationData[stationId]
            if not sd then break end
            local expiredOrders = {}
            for i = 1, #sd.orderQueue do
                local order = sd.orderQueue[i]
                order.timer = order.timer - 1
                if order.timer <= 0 then
                    table.insert(expiredOrders, order.id)
                end
            end
            for _, orderId in ipairs(expiredOrders) do
                ExpireOrder(stationId, orderId)
            end
            UpdateCurrentOrderDisplay(stationId)
        end
    end)
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
    if controlType == "interaction" then
        EnsureStationData(stationId)
    end
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

-- Generate all possible drink item names (taste flavors only; alcohol base excluded)
function GenerateAllDrinkItems()
    local items = {}
    local flavors = Config.Bartender.flavors
    if not flavors or #flavors == 0 then return items end
    local alcoholIdx = (Config.Bartender and type(Config.Bartender.alcoholFlavorIndex) == "number") and Config.Bartender.alcoholFlavorIndex or 0

    local function sanitizeFlavorName(label)
        local name = string.lower(label)
        name = string.gsub(name, "%s+", "_") -- Replace spaces with underscores
        name = string.gsub(name, "[^%w_]", "") -- Remove special characters
        return name
    end
    
    for i = 1, #flavors do
        if i == alcoholIdx then goto continue_single end
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
        ::continue_single::
    end

    for i = 1, #flavors do
        for j = i + 1, #flavors do
            if i == alcoholIdx or j == alcoholIdx then goto continue_mixed end
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
            ::continue_mixed::
        end
    end

    return items
end

-- Get list of all possible drink items (exported for use in item files)
function GetAllDrinkItems()
    return GenerateAllDrinkItems()
end

-- Generate item name from flavorWeights (taste flavors only; alcohol base excluded)
local function GenerateDrinkItemNameFromWeights(flavorWeights)
    if not flavorWeights or next(flavorWeights) == nil then return nil end
    local flavors = Config.Bartender and Config.Bartender.flavors or {}
    local mixThreshold = Config.Bartender and Config.Bartender.mixThreshold or 0.25
    local alcoholIdx = (Config.Bartender and type(Config.Bartender.alcoholFlavorIndex) == "number") and Config.Bartender.alcoholFlavorIndex or 0
    local flavorList = {}
    for flavorIndex, weight in pairs(flavorWeights) do
        local idx = tonumber(flavorIndex)
        if idx and idx ~= alcoholIdx and weight > 0.001 then
            local flavor = flavors[idx]
            if flavor and flavor.label then
                local flavorName = string.lower(flavor.label)
                flavorName = string.gsub(flavorName, "%s+", "_")
                flavorName = string.gsub(flavorName, "[^%w_]", "")
                table.insert(flavorList, { name = flavorName, weight = weight })
            end
        end
    end
    if #flavorList == 0 then return nil end
    table.sort(flavorList, function(a, b) return a.weight > b.weight end)
    if #flavorList == 1 or flavorList[1].weight >= (1.0 - mixThreshold) then
        return flavorList[1].name .. "_drink"
    end
    local topFlavors = {flavorList[1].name, flavorList[2].name}
    table.sort(topFlavors)
    return topFlavors[1] .. "_" .. topFlavors[2] .. "_bar_drink"
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
    local alcoholIdx = (Config.Bartender and type(Config.Bartender.alcoholFlavorIndex) == "number") and Config.Bartender.alcoholFlavorIndex or 0

    -- Only orderable flavors (exclude alcohol base)
    local availableIndices = {}
    for i = 1, #flavors do
        if i ~= alcoholIdx then table.insert(availableIndices, i) end
    end
    if #availableIndices == 0 then return "Unknown Drink", {} end

    -- Randomly select 1-2 flavors
    local numFlavors = math.random(1, 2)
    local selectedFlavorIndices = {}
    local selectedFlavorLabels = {}
    
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
    
    -- Select random NPC model server-side so all clients spawn the same ped
    local npcModels = Config.Bartender.orderNPCs
    local npcModel = "a_m_m_skater_01" -- default fallback
    if npcModels and #npcModels > 0 then
        npcModel = npcModels[math.random(1, #npcModels)]
    end
    if type(npcModel) ~= "string" or npcModel == "" then
        npcModel = "a_m_m_skater_01"
    end

    -- Trigger spawn event to all clients (model is server-authoritative)
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
        local payload = {
            stationId = stationId,
            orderId = currentOrder.id,
            orderName = currentOrder.drinkName,
            timeRemaining = currentOrder.timer,
            active = true,
            isPlayerOrder = currentOrder.isPlayerOrder == true,
        }
        if currentOrder.isPlayerOrder and currentOrder.playerSource then
            local playerName = GetPlayerCharacterName(currentOrder.playerSource)
            payload.orderPlayerName = playerName
        end
        TriggerClientEvent("pickle_clubs:updateOrder", -1, payload)
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

function ExpireOrder(stationId, orderId, skipPlayerExpiredNotify)
    local stationData = StationData[stationId]
    local order = nil
    if stationData then
        for i = 1, #stationData.orderQueue do
            if stationData.orderQueue[i].id == orderId then
                order = stationData.orderQueue[i]
                break
            end
        end
    end
    -- Delete NPC only for NPC orders (player orders have no NPC)
    if not order or not order.isPlayerOrder then
        TriggerClientEvent("pickle_clubs:deleteOrderNPC", -1, stationId, orderId)
    end
    if order and order.isPlayerOrder and order.playerSource and not skipPlayerExpiredNotify then
        ShowNotification(order.playerSource, "Your order expired")
    end
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

    if StationData[stationId] and StationData[stationId].serviceActive then
        print("ERROR: Bartender service already active for station " .. stationId)
        return false
    end

    EnsureStationData(stationId)
    local stationData = StationData[stationId]
    if not stationData then return false end

    stationData.serviceActive = true
    if type(coords) == "table" then
        coords = vector3(coords.x, coords.y, coords.z)
    end
    stationData.interactionData = {
        coords = coords,
        heading = heading,
    }

    -- Do not clear orderQueue; player orders may already be in queue

    -- Timer thread is already running from EnsureStationData

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

    local alcoholIdx = (Config.Bartender and type(Config.Bartender.alcoholFlavorIndex) == "number") and Config.Bartender.alcoholFlavorIndex or 0

    -- Total weight and taste-only weight (alcohol is base, not a flavor for validation)
    local totalWeight = 0
    local alcoholWeight = flavorWeights[alcoholIdx] or flavorWeights[tostring(alcoholIdx)] or 0
    for flavorIndex, weight in pairs(flavorWeights) do
        totalWeight = totalWeight + weight
    end
    local tasteWeight = totalWeight - alcoholWeight
    if tasteWeight < 0 then tasteWeight = 0 end

    if totalWeight < 0.5 then
        return false, "Drink not full enough"
    end
    if tasteWeight < 0.01 then
        return false, "Drink must have flavor"
    end

    -- Check if drink has all required flavors (with minimum threshold)
    local requiredWeight = 0
    for i = 1, #requiredFlavors do
        local flavorIndex = requiredFlavors[i]
        local weight = flavorWeights[tonumber(flavorIndex)] or flavorWeights[flavorIndex] or 0
        if weight < 0.01 then
            return false, "Missing required flavor"
        end
        requiredWeight = requiredWeight + weight
    end

    -- Percentage of taste that is required flavors (alcohol base excluded)
    local requiredPercentage = requiredWeight / tasteWeight
    
    -- For single-flavor orders, require 85%+ of that flavor (allows for minor mixing)
    -- For multi-flavor orders, require 70%+ to be the required flavors
    local threshold = #requiredFlavors == 1 and 0.85 or 0.70
    
    if requiredPercentage < threshold then
        return false, "Too many extra flavors"
    end
    
    return true, "Correct"
end

-- Track registered drink items to avoid duplicate registrations (used by submitDrink and giveDrinkItem)
local RegisteredDrinkItems = {}

local function RegisterDrinkItemIfNeeded(itemName)
    if RegisteredDrinkItems[itemName] then
        return -- Already registered
    end
    -- Check if item name matches drink pattern
    if string.match(itemName, "_drink$") or string.match(itemName, "_bar_drink$") then
        RegisterUsableItem(itemName, function(source, item)
            local metadata = Config.FrameworkSettings.usableItemMetadata(item, item)
            local flavorWeights = metadata and metadata.flavorWeights or {}
            Inventory.RemoveItem(source, itemName, 1)
            TriggerClientEvent("pickle_clubs:useDrinkItem", source, itemName, flavorWeights)
        end)
        RegisteredDrinkItems[itemName] = true
    end
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
    
    local order = stationData.orderQueue[1]
    local isValid, message = ValidateDrink(stationId, orderId, flavorWeights)
    
    if isValid then
        if order.isPlayerOrder and order.playerSource then
            -- Player order: give drink item to ordering player
            local targetSource = order.playerSource
            if GetPlayerPing(targetSource) > 0 then
                local itemName = GenerateDrinkItemNameFromWeights(flavorWeights)
                if itemName then
                    local mixThreshold = Config.Bartender and Config.Bartender.mixThreshold or 0.25
                    local alcoholIdx = (Config.Bartender and type(Config.Bartender.alcoholFlavorIndex) == "number") and Config.Bartender.alcoholFlavorIndex or 0
                    local flavorList = {}
                    local alcoholWeight = 0
                    for flavorIndex, weight in pairs(flavorWeights) do
                        local idx = tonumber(flavorIndex)
                        if idx == alcoholIdx then
                            alcoholWeight = weight
                        elseif idx and weight > 0.001 then
                            local flavor = Config.Bartender and Config.Bartender.flavors and Config.Bartender.flavors[idx]
                            if flavor then
                                table.insert(flavorList, { index = idx, weight = weight })
                            end
                        end
                    end
                    table.sort(flavorList, function(a, b) return a.weight > b.weight end)
                    -- Normalized weights keep all flavors including alcohol (strength)
                    local normalizedWeights = {}
                    if #flavorList >= 1 then
                        if #flavorList >= 2 and flavorList[1].weight < (1.0 - mixThreshold) then
                            normalizedWeights[flavorList[1].index] = 0.5
                            normalizedWeights[flavorList[2].index] = 0.5
                        else
                            normalizedWeights[flavorList[1].index] = 1.0
                        end
                    end
                    if alcoholWeight > 0.001 then
                        normalizedWeights[alcoholIdx] = math.min(1.0, alcoholWeight)
                    end
                    local description = nil
                    local flavorsConfig = Config.Bartender and Config.Bartender.flavors or {}
                    if #flavorList == 1 and flavorsConfig[flavorList[1].index] and flavorsConfig[flavorList[1].index].label then
                        local lab = string.lower(flavorsConfig[flavorList[1].index].label)
                        description = ("A %s drink."):format(lab)
                    elseif #flavorList >= 2 then
                        local l1 = string.lower((flavorsConfig[flavorList[1].index] and flavorsConfig[flavorList[1].index].label) or "")
                        local l2 = string.lower((flavorsConfig[flavorList[2].index] and flavorsConfig[flavorList[2].index].label) or "")
                        if l1 > l2 then l1, l2 = l2, l1 end
                        description = ("A %s-%s mixture."):format(l1, l2)
                    end
                    -- Append strength based on alcohol (base) amount
                    if description and alcoholWeight > 0.001 then
                        if alcoholWeight >= 0.5 then
                            description = description .. " Strong."
                        elseif alcoholWeight >= 0.2 then
                            description = description .. " (Medium.)"
                        else
                            description = description .. " (Light.)"
                        end
                    end
                    local metadata = { flavorWeights = normalizedWeights, description = description }
                    RegisterDrinkItemIfNeeded(itemName)
                    if not Inventory.CanCarryItem or Inventory.CanCarryItem(targetSource, itemName, 1) then
                        Inventory.AddItem(targetSource, itemName, 1, metadata)
                        ShowNotification(targetSource, "Your drink is ready!")
                    else
                        ShowNotification(targetSource, "Your drink is ready but you cannot carry it")
                    end
                end
            end
            ExpireOrder(stationId, orderId, true)
            TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, true, "Order fulfilled", nil)
        else
            -- NPC order: pay bartender and society
            local station = GetStation(stationId)
            local orderPayment = Config.Bartender.orderPayment
            local playerPayment = orderPayment
            local societyPayment = 0
            if station and station.society_name and station.society_name ~= "" and station.society_percentage and station.society_percentage > 0 then
                societyPayment = math.floor(orderPayment * (station.society_percentage / 100))
                playerPayment = orderPayment - societyPayment
                if societyPayment > 0 then
                    AddSocietyMoney(station.society_name, societyPayment)
                end
            end
            AddMoney(source, playerPayment, "money")
            local feedbackMessages = Config.Bartender.orderConversations.correct
            local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
            ExpireOrder(stationId, orderId)
            TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, true, feedback, playerPayment)
        end
    else
        ShowNotification(source, message)
        local feedbackMessages = Config.Bartender.orderConversations.incorrect
        local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
        TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, false, feedback)
    end
end)

RegisterNetEvent("pickle_clubs:orderCompleted", function(stationId, orderId)
    -- Legacy event, now handled by submitDrink
    if StationData[stationId] then
        ExpireOrder(stationId, orderId)
    end
end)

-- Build list of drinks for Place Order UI: { drinkKey, name, price, requiredFlavorIndices }
lib.callback.register("pickle_clubs:getClubDrinkMenu", function(source, stationId)
    local menu = GetClubDrinkMenuForStation(stationId)
    if not menu or type(menu) ~= "table" then return {} end
    local list = {}
    for drinkKey, entry in pairs(menu) do
        if type(entry) == "table" and entry.name then
            local requiredFlavorIndices = {}
            if drinkKey:match("^%d+_%d+$") then
                local i, j = drinkKey:match("^(%d+)_(%d+)$")
                if i and j then
                    requiredFlavorIndices = { tonumber(i), tonumber(j) }
                end
            else
                local i = tonumber(drinkKey)
                if i then requiredFlavorIndices = { i } end
            end
            if #requiredFlavorIndices >= 1 then
                list[#list + 1] = {
                    drinkKey = drinkKey,
                    name = entry.name,
                    price = type(entry.price) == "number" and entry.price or 0,
                    requiredFlavorIndices = requiredFlavorIndices,
                }
            end
        end
    end
    table.sort(list, function(a, b) return (a.drinkKey or "") < (b.drinkKey or "") end)
    return list
end)

lib.callback.register("pickle_clubs:canPlacePlayerOrder", function(source, stationId)
    if not GetStation(stationId) then
        return false, "Station not found"
    end
    if not IsStationControlled(stationId, "interaction") then
        return false, "No bartender at the bar - try again when someone is serving"
    end
    local stationData = StationData[stationId]
    if not stationData then
        return false, "Station not ready"
    end
    if #stationData.orderQueue >= Config.Bartender.maxActiveOrders then
        return false, "Too many orders, try again later"
    end
    return true
end)

RegisterNetEvent("pickle_clubs:placePlayerOrder", function(stationId, drinkKey, requiredFlavorIndices)
    local source = source
    if not GetStation(stationId) then
        ShowNotification(source, "Station not found")
        return
    end
    if not IsStationControlled(stationId, "interaction") then
        ShowNotification(source, "No bartender at the bar - try again when someone is serving")
        return
    end
    local stationData = StationData[stationId]
    if not stationData then
        ShowNotification(source, "Station not ready")
        return
    end
    if #stationData.orderQueue >= Config.Bartender.maxActiveOrders then
        ShowNotification(source, "Too many orders, try again later")
        return
    end
    local flavors = Config.Bartender and Config.Bartender.flavors or {}
    if not requiredFlavorIndices or type(requiredFlavorIndices) ~= "table" then
        ShowNotification(source, "Invalid order")
        return
    end
    for _, idx in ipairs(requiredFlavorIndices) do
        if type(idx) ~= "number" or idx < 1 or idx > #flavors then
            ShowNotification(source, "Invalid drink selection")
            return
        end
    end
    local menu = GetClubDrinkMenuForStation(stationId)
    if not menu or not drinkKey or not menu[drinkKey] then
        ShowNotification(source, "Invalid drink")
        return
    end
    local drinkName = menu[drinkKey].name or ("Drink " .. tostring(drinkKey))
    local price = type(menu[drinkKey].price) == "number" and menu[drinkKey].price or 0
    if price > 0 then
        local cash = (GetMoney and GetMoney(source, "money")) or 0
        if cash < price then
            ShowNotification(source, "Not enough cash")
            return
        end
        RemoveMoney(source, price, "money")
    end
    local orderId = GetGameTimer() .. "_" .. math.random(1000, 9999)
    local timerDuration = Config.Bartender.playerOrderExpireSeconds or Config.Bartender.orderTimerDuration
    local order = {
        id = orderId,
        drinkKey = drinkKey,
        drinkName = drinkName,
        requiredFlavorIndices = requiredFlavorIndices,
        timer = timerDuration,
        createdAt = GetGameTimer(),
        stationId = stationId,
        isPlayerOrder = true,
        playerSource = source,
    }
    table.insert(stationData.orderQueue, order)
    UpdateCurrentOrderDisplay(stationId)
    ShowNotification(source, "Order placed: " .. drinkName)
end)

-- Track equipped drinks for syncing
local EquippedDrinksServer = {} -- source -> {coords, flavorWeights, color, progress, lastUpdate}

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

-- Callback so client only proceeds when server grants control (prevents race where client starts interaction despite denial)
lib.callback.register("pickle_clubs:requestStationControl", function(source, stationId, controlType)
    local success, message = SetStationController(stationId, source, controlType)
    return success, (not success and (message or "Station is already in use")) or nil
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
