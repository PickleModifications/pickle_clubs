Config = {}
Config.Language = "en"
Config.Debug = true -- This enables debugging prints.
Config.RenderDistance = 100.0
Config.InteractDistance = 2.0
Config.MusicRadius = 20.0
Config.DebugListen = false -- When false, the broadcaster will not auto-listen to their own stream
Config.UseTarget = true -- This enables the use of the target system when available.
Config.ImageDirectory = "nui://ox_inventory/web/images/"
Config.ImageExtension = "png"
Config.WeaponsAreItems = true -- This enables the use of weapons as items. If set to false, weapons will be treated as items and not as weapons.
Config.Currency = { currency = "USD", countryCode = "en-US" } -- Look up JS currency and countryCode variables for more options. 
Config.AdminGroups = {
    "qbcore.admin",
    "qbcore.god",
    "god",
    "admin",
    "mod",
    "superadmin",
}
Config.TargetIcons = {
    bartender = "fas fa-cocktail",
}

-- Jobs that bypass club entry/bouncer checks regardless of club job assignments.
-- Format: { jobName = minimumRank }  (0 = any rank)
Config.BypassJobs = {
    ["police"] = 0,
    -- ["ambulance"] = 0,
}

-- Society entity: model used for placement/management gizmo (optional prop at interaction point)
Config.Society = {
    model = `prop_atm_01`, -- e.g. prop_atm_01, vw_prop_casino_till
}

Config.FrameworkSettings = {
    dirtyMoney = "DEFAULT",
    society = "qb-management", -- QBCore society system: "qb-management" or "qb-banking". ESX uses esx_addonaccount.
    usableItemMetadata = function(item, data)
        if type(data) == "table" and data.metadata then return data.metadata end
        if type(item) == "table" and item.metadata then return item.metadata end
        if type(data) == "table" and data.info then return data.info end
        if type(item) == "table" and item.info then return item.info end
        print("ERROR: METADATA IS WRONGLY CONFIGURED, CHECK CONFIG.LUA:^0", item, data)
    end
}

Config.Bartender = {
    mixThreshold = 0.25, -- This is the minimum requirement of a secondary flavor to be considered for a mixed drink.
    -- Flavors are key-value pairs; adding/removing a key never shifts other references.
    -- Alcohol strength is set per-drink (the alcohol% field) — it is not a flavor.
    flavors = {
        ["orange_juice"]   = { label = "Orange Juice",   color = {255, 165, 0} },
        ["cranberry"]      = { label = "Cranberry",      color = {180, 20, 40} },
        ["lime_juice"]     = { label = "Lime Juice",     color = {50, 205, 50} },
        ["cola"]           = { label = "Cola",           color = {60, 30, 10} },
        ["tonic"]          = { label = "Tonic Water",    color = {220, 240, 255} },
        ["grenadine"]      = { label = "Grenadine",      color = {200, 30, 60} },
        ["pineapple"]      = { label = "Pineapple Juice",color = {255, 215, 0} },
        ["sour_mix"]       = { label = "Sour Mix",       color = {230, 230, 100} },
    },
    alcoholBottle = {
        label = "Alcohol",
        color = {255, 255, 255}, -- White
        key = "_alcohol", -- Reserved flavorWeights key (excluded from item names and color mixing)
    },
    alcoholTolerance = 10, -- Allowed deviation in alcohol % (e.g. order wants 20%, player can submit 10-30%)
    orderSpawnOffset = -2.0, -- Distance along forwardVector to spawn NPCs (negative = behind bar)
    orderQueueSpacing = 0.8, -- Spacing between NPCs in queue (along rightVector)
    orderTimerDuration = 60, -- Order timeout in seconds
    maxActiveOrders = 3, -- Maximum simultaneous orders
    orderNPCs = {
        "s_m_y_bartender_01",
        "a_f_y_business_01",
        "a_m_y_business_01",
        "a_f_y_business_02",
        "a_m_y_business_02",
        "a_f_y_business_03",
        "a_m_y_business_03",
        "s_f_y_bartender_01",
    },
    orderSpawnInterval = 10, -- Time between new orders in seconds
    orderPayment = 50, -- Payment amount for correct order
    playerOrderExpireSeconds = 60, -- Time before player orders expire (default: same as orderTimerDuration)
    playerOrderPayment = 0, -- If > 0, take cash from ordering player; 0 = free drinks
    registerModel = `vw_prop_casino_till`, -- Model used for bartender placement/management gizmo
    defaultBlip = {
        name = "Bartending Station",
        color = 5,
        sprite = 52,
        scale = 0.8,
        visible = true,
    },
    orderConversations = {
        correct = {
            "Perfect! This is exactly what I ordered!",
            "Thanks! This is great!",
            "Exactly what I wanted!",
            "Perfect drink, thank you!",
        },
        incorrect = {
            "This isn't what I ordered...",
            "Hmm, this doesn't taste right.",
            "I think you made the wrong drink.",
            "This isn't what I asked for.",
        },
    },
}

Config.Drinks = {
    alcoholPerDrink = 100, -- Scale factor for alcohol system. One full drink at 5% alcohol adds 0.05 to drunk level.
}

Config.DrunkEffects = {
    enabled = true, -- Enable/disable drunk effects system
    visualEffects = true, -- Enable visual screen effects (blur, distortion, etc.)
    enableWalkCycles = true, -- Enable drunk walk animations
    cameraShake = true, -- Enable camera shake effects
    debug = true, -- Enable debug prints for drunk effects
    
    -- Alcohol decay settings
    decayRate = 0.002, -- Amount of alcohol removed per second. Lower = effects last longer.
    -- With decayRate 0.002: moderate drunk (0.25) takes ~2 minutes to wear off
    decayInterval = 1000, -- How often to decay alcohol (milliseconds)
    
    -- Effect thresholds (alcohol level values)
    -- A 5% beer adds 0.05 per full drink, so 2 beers = 0.10, 4 beers = 0.20
    thresholds = {
        light = 0.03, -- ~1 beer
        moderate = 0.10, -- ~2 beers
        heavy = 0.20, -- ~4 beers
        extreme = 0.35, -- ~7 beers
    },

    -- Max alcohol level for intensity scaling (at this level, effects are at 100%)
    -- Formula: maxBeers * (alcoholPct / 100), e.g. 6 beers at 5% = 6 * 0.05 = 0.30
    maxAlcoholLevel = 0.30, -- ~6 beers at 5%
    
    -- Walk cycle movement clipsets (GTA V movement styles)
    walkCycles = {
        light = "move_m@drunk@moderatedrunk", -- Light drunk walk
        moderate = "move_m@drunk@moderatedrunk", -- Moderate drunk walk
        heavy = "move_m@drunk@slightlydrunk", -- Heavy drunk walk
        extreme = "move_m@drunk@verydrunk", -- Extreme drunk walk
    },
}

Config.Peds = {
    ["bouncer_1"] = {
        model = "s_m_m_bouncer_01",
    },
}