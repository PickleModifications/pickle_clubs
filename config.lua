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
Config.FrameworkSettings = {
    dirtyMoney = "DEFAULT",
    society = "qb-management", -- QBCore society system: "qb-management" or "qb-banking"
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
    flavors = {
        {
            label = "Strawberry",
            color = {255, 0, 0},
        },
        {
            label = "Lime",
            color = {0, 255, 0},
        },
        {
            label = "Blueberry",
            color = {0, 0, 255},
        },
    },
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
    alcoholPerDrink = 1000000,
}

Config.DrunkEffects = {
    enabled = true, -- Enable/disable drunk effects system
    visualEffects = true, -- Enable visual screen effects (blur, distortion, etc.)
    enableWalkCycles = true, -- Enable drunk walk animations
    cameraShake = true, -- Enable camera shake effects
    debug = true, -- Enable debug prints for drunk effects
    
    -- Alcohol decay settings
    decayRate = 0.008, -- Amount of alcohol removed per second (as proportion of alcoholPerDrink)
    -- With decayRate 0.008: A full drink (1.0) takes ~2.15 minutes to wear off completely
    -- Adjust this value to make alcohol wear off faster (higher) or slower (lower)
    decayInterval = 1000, -- How often to decay alcohol (milliseconds)
    
    -- Effect thresholds (as proportion of alcoholPerDrink, 0.0 to 1.0+)
    -- Lower thresholds mean effects start sooner
    thresholds = {
        light = 0.05, -- Light effects start (very low threshold)
        moderate = 0.25, -- Moderate effects start
        heavy = 0.50, -- Heavy effects start
        extreme = 0.75, -- Extreme effects start
    },
    
    -- Visual effect intensities (0.0 to 1.0)
    visualIntensity = {
        light = 0.15,
        moderate = 0.35,
        heavy = 0.55,
        extreme = 0.75,
    },
    
    -- Camera shake intensities
    shakeIntensity = {
        light = 0.15,
        moderate = 0.35,
        heavy = 0.55,
        extreme = 0.75,
    },
    
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