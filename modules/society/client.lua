-- Society entity: interaction point for club society (balance, deposit, withdraw)
-- Society name = club's primary job. Players with job in club.jobs can use.

local SocietyInteractions = {} -- [clubId][entityId] -> interactionIndex

local function GetPrimaryJobName(club)
    if not club or not club.jobs then return nil end
    for i = 1, #club.jobs do
        if club.jobs[i].primary and type(club.jobs[i].name) == "string" and club.jobs[i].name ~= "" then
            return club.jobs[i].name
        end
    end
    return nil
end

local function RenderSociety(clubId, entityId)
    if not SocietyInteractions[clubId] then SocietyInteractions[clubId] = {} end
    if SocietyInteractions[clubId][entityId] then
        DeleteInteraction(SocietyInteractions[clubId][entityId])
        SocietyInteractions[clubId][entityId] = nil
    end

    local club = Clubs[clubId]
    if not club then return end
    local entity = club.entities and club.entities[entityId]
    if not entity or entity.type ~= "society" or not entity.society then return end

    local coords = entity.society.coords
    if type(coords) == "table" then
        coords = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    end
    local interactCoords = coords + vector3(0.0, 0.0, 1.0)
    local heading = entity.society.heading or 0.0

    local interactionIndex = CreateInteraction({
        label = "Society",
        coords = interactCoords,
        heading = heading,
    }, function()
        lib.callback("pickle_clubs:checkIsAdmin", false, function(isAdmin)
            local societyName = GetPrimaryJobName(club)
            local options = {}

            if isAdmin then
                table.insert(options, {
                    title = "Manage",
                    description = "Open this entity's management menu",
                    onSelect = function()
                        OpenClubManagementNuiForEntity(clubId, entityId)
                    end,
                })
            end

            if societyName then
                table.insert(options, {
                    title = "View Balance",
                    description = "Check society account balance",
                    onSelect = function()
                        lib.callback("pickle_clubs:getSocietyBalance", false, function(balance)
                            if balance ~= nil then
                                ShowNotification(("%s: $%s"):format(_L("balance") or "Balance", tostring(balance)))
                            else
                                ShowNotification(_L("no_access") or "No access")
                            end
                        end, clubId)
                    end,
                })
                table.insert(options, {
                    title = "Deposit",
                    description = "Deposit cash into society",
                    onSelect = function()
                        local input = lib.inputDialog("Deposit", {
                            { type = "number", label = "Amount", min = 1, default = 100 },
                        })
                        if input and input[1] and input[1] > 0 then
                            lib.callback("pickle_clubs:societyDeposit", false, function(success, msg)
                                if success then
                                    ShowNotification(_L("deposit_success") or "Deposited successfully")
                                else
                                    ShowNotification(msg or "Deposit failed")
                                end
                            end, clubId, input[1])
                        end
                    end,
                })
                table.insert(options, {
                    title = "Withdraw",
                    description = "Withdraw cash from society",
                    onSelect = function()
                        local input = lib.inputDialog("Withdraw", {
                            { type = "number", label = "Amount", min = 1, default = 100 },
                        })
                        if input and input[1] and input[1] > 0 then
                            lib.callback("pickle_clubs:societyWithdraw", false, function(success, msg)
                                if success then
                                    ShowNotification(_L("withdraw_success") or "Withdrawn successfully")
                                else
                                    ShowNotification(msg or "Withdraw failed")
                                end
                            end, clubId, input[1])
                        end
                    end,
                })
            else
                table.insert(options, {
                    title = "No society configured",
                    description = "Club has no primary job set",
                    disabled = true,
                })
            end

            if #options == 0 then return end
            local contextId = ("society_interact_%s_%s"):format(clubId, entityId)
            lib.registerContext({
                id = contextId,
                title = "Society",
                options = options,
            })
            lib.showContext(contextId)
        end)
    end)
    SocietyInteractions[clubId][entityId] = interactionIndex
end

local function UnrenderSociety(clubId, entityId)
    if SocietyInteractions[clubId] and SocietyInteractions[clubId][entityId] then
        DeleteInteraction(SocietyInteractions[clubId][entityId])
        SocietyInteractions[clubId][entityId] = nil
    end
end

CreateThread(function()
    RegisterEntityType("society", {
        label = "Society",
        description = "Society deposit/withdraw interaction point.",
        onRender = function(id, entityId)
            RenderSociety(id, entityId)
        end,
        onUnrender = function(id, entityId)
            UnrenderSociety(id, entityId)
        end,
    })
end)
