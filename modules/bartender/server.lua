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

-- Collect all unique drink item names from loaded club menus
function GenerateAllDrinkItems()
    local items = {}
    local seen = {}
    for _, club in pairs(Clubs or {}) do
        for _, entry in pairs(club.drink_menu or {}) do
            if type(entry) == "table" and type(entry.item) == "string" and entry.item ~= "" and not seen[entry.item] then
                seen[entry.item] = true
                items[#items + 1] = {
                    name = entry.item,
                    label = type(entry.name) == "string" and entry.name or entry.item,
                }
            end
        end
    end
    return items
end

-- Get list of all drink items (exported)
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

-- Pick a random drink from the club menu for the given station; returns nil if no drinks defined
function GenerateDrinkOrder(stationId)
    local clubId = GetClubIdFromStationId(stationId)
    local menu = (clubId and GetClubDrinkMenu and GetClubDrinkMenu(clubId)) or {}
    local entries = {}
    for key, entry in pairs(menu) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= ""
            and type(entry.flavors) == "table" and #entry.flavors > 0 then
            entries[#entries + 1] = { key = key, entry = entry }
        end
    end
    if #entries == 0 then return nil end
    local chosen = entries[math.random(1, #entries)].entry
    return chosen.name, chosen.flavors,
        (type(chosen.alcohol) == "number" and chosen.alcohol or 5),
        (type(chosen.item) == "string" and chosen.item or "")
end

function CreateOrder(stationId)
    local orderId = GetGameTimer() .. "_" .. math.random(1000, 9999)
    local drinkName, requiredFlavorIndices, alcoholPct, item = GenerateDrinkOrder(stationId)
    if not drinkName then return nil end
    return {
        id = orderId,
        drinkName = drinkName,
        requiredFlavorIndices = requiredFlavorIndices,
        alcoholPct = alcoholPct,
        item = item,
        flavors = requiredFlavorIndices,
        timer = Config.Bartender.orderTimerDuration,
        createdAt = GetGameTimer(),
        stationId = nil,
    }
end

function SpawnNextOrder(stationId)
    local stationData = StationData[stationId]
    if not stationData or not stationData.serviceActive then return end
    
    -- Check queue length
    if #stationData.orderQueue >= Config.Bartender.maxActiveOrders then return end
    
    local order = CreateOrder(stationId)
    if not order then
        debugPrint("No drinks defined in club menu for station " .. stationId .. ", skipping NPC order")
        return
    end
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

    local order = nil
    for i = 1, #stationData.orderQueue do
        if stationData.orderQueue[i].id == orderId then
            order = stationData.orderQueue[i]
            break
        end
    end
    if not order then return false, "Order not found" end

    local requiredFlavors = order.requiredFlavorIndices
    if not requiredFlavors or #requiredFlavors == 0 then
        return false, "Invalid order requirements"
    end

    local totalWeight = 0
    for _, weight in pairs(flavorWeights) do
        totalWeight = totalWeight + weight
    end
    if totalWeight < 0.5 then return false, "Drink not full enough" end

    local requiredWeight = 0
    for i = 1, #requiredFlavors do
        local flavorIndex = requiredFlavors[i]
        local weight = flavorWeights[tonumber(flavorIndex)] or flavorWeights[flavorIndex] or 0
        if weight < 0.01 then return false, "Missing required flavor" end
        requiredWeight = requiredWeight + weight
    end

    local threshold = #requiredFlavors == 1 and 0.85 or 0.70
    if (requiredWeight / totalWeight) < threshold then
        return false, "Too many extra flavors"
    end

    return true, "Correct"
end

-- Track registered drink items to avoid duplicate registrations (used by submitDrink and giveDrinkItem)
local RegisteredDrinkItems = {}

local function RegisterDrinkItemIfNeeded(itemName)
    if not itemName or itemName == "" then return end
    if RegisteredDrinkItems[itemName] then return end
    RegisterUsableItem(itemName, function(source, item)
        local metadata = Config.FrameworkSettings.usableItemMetadata(item, item)
        local flavors = (metadata and type(metadata.flavors) == "table") and metadata.flavors or {}
        local alcoholPct = (metadata and type(metadata.alcoholPct) == "number") and metadata.alcoholPct or 5
        Inventory.RemoveItem(source, itemName, 1)
        TriggerClientEvent("pickle_clubs:useDrinkItem", source, itemName, flavors, alcoholPct)
    end)
    RegisteredDrinkItems[itemName] = true
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
                local itemName = order.item
                if itemName and itemName ~= "" then
                    local flavorsConfig = Config.Bartender and Config.Bartender.flavors or {}
                    local flavorLabels = {}
                    for _, idx in ipairs(order.flavors or {}) do
                        local f = flavorsConfig[idx]
                        if f then flavorLabels[#flavorLabels + 1] = string.lower(f.label) end
                    end
                    local description
                    if #flavorLabels == 1 then
                        description = ("A %s drink."):format(flavorLabels[1])
                    elseif #flavorLabels > 1 then
                        table.sort(flavorLabels)
                        description = ("A %s mixture."):format(table.concat(flavorLabels, "-"))
                    else
                        description = "A bar drink."
                    end
                    local alcoholPct = order.alcoholPct or 5
                    if alcoholPct >= 20 then
                        description = description .. " Strong."
                    elseif alcoholPct >= 10 then
                        description = description .. " (Medium.)"
                    elseif alcoholPct > 0 then
                        description = description .. " (Light.)"
                    end
                    local metadata = { flavors = order.flavors or {}, alcoholPct = alcoholPct, description = description }
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
            -- NPC order: pay bartender
            local orderPayment = Config.Bartender.orderPayment
            AddMoney(source, orderPayment, "money")
            local feedbackMessages = Config.Bartender.orderConversations.correct
            local feedback = feedbackMessages[math.random(1, #feedbackMessages)]
            ExpireOrder(stationId, orderId)
            TriggerClientEvent("pickle_clubs:drinkSubmissionResult", source, true, feedback, orderPayment)
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

-- Build list of drinks for Place Order UI: { drinkKey, name, price, flavors, alcoholPct, item }
lib.callback.register("pickle_clubs:getClubDrinkMenu", function(source, stationId)
    local menu = GetClubDrinkMenuForStation(stationId)
    if not menu or type(menu) ~= "table" then return {} end
    local list = {}
    for drinkKey, entry in pairs(menu) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= ""
            and type(entry.flavors) == "table" and #entry.flavors >= 1 then
            list[#list + 1] = {
                drinkKey = drinkKey,
                name = entry.name,
                price = type(entry.price) == "number" and entry.price or 0,
                flavors = entry.flavors,
                alcoholPct = type(entry.alcohol) == "number" and entry.alcohol or 5,
                item = type(entry.item) == "string" and entry.item or "",
            }
        end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
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

RegisterNetEvent("pickle_clubs:placePlayerOrder", function(stationId, drinkKey)
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
    local menu = GetClubDrinkMenuForStation(stationId)
    if not menu or not drinkKey or type(menu[drinkKey]) ~= "table" then
        ShowNotification(source, "Invalid drink")
        return
    end
    local menuEntry = menu[drinkKey]
    local requiredFlavorIndices = type(menuEntry.flavors) == "table" and menuEntry.flavors or {}
    if #requiredFlavorIndices == 0 then
        ShowNotification(source, "Drink has no required flavors")
        return
    end
    local drinkName = menuEntry.name or ("Drink " .. tostring(drinkKey))
    local price = type(menuEntry.price) == "number" and menuEntry.price or 0
    local alcoholPct = type(menuEntry.alcohol) == "number" and menuEntry.alcohol or 5
    local item = type(menuEntry.item) == "string" and menuEntry.item or ""
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
        flavors = requiredFlavorIndices,
        alcoholPct = alcoholPct,
        item = item,
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

RegisterNetEvent("pickle_clubs:giveDrinkItem", function(itemName, flavors, alcoholPct)
    local source = source
    if not itemName then return end
    if Inventory.CanCarryItem and not Inventory.CanCarryItem(source, itemName, 1) then
        ShowNotification(source, "You cannot carry this item")
        return
    end
    local metadata = {
        flavors = type(flavors) == "table" and flavors or {},
        alcoholPct = type(alcoholPct) == "number" and alcoholPct or 5,
    }
    RegisterDrinkItemIfNeeded(itemName)
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

-- Register club drink items and generate install files after clubs load
CreateThread(function()
    Wait(3000) -- Wait for clubs to load from SQL

    -- Generate item files from club menus
    GenerateItemFiles()

    -- Register all items as usable
    local allItems = GenerateAllDrinkItems()
    print("^2[pickle_clubs]^0 Registering " .. #allItems .. " drink items from club menus...")
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
RegisterNetEvent("pickle_clubs:drinkConsumed", function(amount, alcoholPct)
    local source = source
    if not amount or amount <= 0 then return end
    if amount > 1.0 then amount = 1.0 end
    alcoholPct = tonumber(alcoholPct) or 5
    if alcoholPct < 0 then alcoholPct = 0 end
    if alcoholPct > 100 then alcoholPct = 100 end
    if Config.Drinks and Config.Drinks.alcoholPerDrink and Config.Drinks.alcoholPerDrink > 0 and AddAlcohol then
        local scaled = math.floor(Config.Drinks.alcoholPerDrink * amount * (alcoholPct / 100) + 0.5)
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
