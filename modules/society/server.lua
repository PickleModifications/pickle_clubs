-- Society entity: server-side registration and employee management

local function GetPrimaryJobName(club)
    local jobs = club and club.jobs or {}
    for i = 1, #jobs do
        if jobs[i].primary and type(jobs[i].name) == "string" and jobs[i].name ~= "" then
            return jobs[i].name
        end
    end
    return nil
end

local function PlayerHasClubAccess(source, clubId)
    local club = Clubs[clubId]
    if not club or not club.jobs then return false end
    local jobName = GetPlayerJobName(source)
    if not jobName then return false end
    for i = 1, #club.jobs do
        if club.jobs[i].name == jobName then
            return true
        end
    end
    return false
end

-- Get employees for a club's primary job
lib.callback.register("pickle_clubs:getEmployees", function(source, clubId)
    if not PlayerHasClubAccess(source, clubId) then return {} end
    local club = Clubs[clubId]
    local jobName = GetPrimaryJobName(club)
    if not jobName or not GetEmployees then return {} end
    local employees = GetEmployees(jobName)
    return employees or {}
end)

-- Get job grades for a club's primary job
lib.callback.register("pickle_clubs:getJobGrades", function(source, clubId)
    if not PlayerHasClubAccess(source, clubId) then return {} end
    local club = Clubs[clubId]
    local jobName = GetPrimaryJobName(club)
    if not jobName or not GetJobGrades then return {} end
    return GetJobGrades(jobName)
end)

-- Set employee grade
lib.callback.register("pickle_clubs:setEmployeeGrade", function(source, clubId, targetSource, grade)
    if not PlayerHasClubAccess(source, clubId) then return false, "No access" end
    local club = Clubs[clubId]
    local jobName = GetPrimaryJobName(club)
    if not jobName or not SetPlayerJob then return false, "No job configured" end
    targetSource = tonumber(targetSource)
    grade = tonumber(grade)
    if not targetSource or not grade then return false, "Invalid parameters" end
    SetPlayerJob(targetSource, jobName, grade)
    return true
end)

-- Fire employee (set to unemployed)
lib.callback.register("pickle_clubs:fireEmployee", function(source, clubId, targetSource)
    if not PlayerHasClubAccess(source, clubId) then return false, "No access" end
    if not SetPlayerJob then return false, "Not supported" end
    targetSource = tonumber(targetSource)
    if not targetSource then return false, "Invalid target" end
    SetPlayerJob(targetSource, "unemployed", 0)
    ShowNotification(targetSource, "You have been fired")
    return true
end)

-- Hire nearby player
lib.callback.register("pickle_clubs:hirePlayer", function(source, clubId, targetSource)
    if not PlayerHasClubAccess(source, clubId) then return false, "No access" end
    local club = Clubs[clubId]
    local jobName = GetPrimaryJobName(club)
    if not jobName or not SetPlayerJob then return false, "No job configured" end
    targetSource = tonumber(targetSource)
    if not targetSource then return false, "Invalid target" end
    SetPlayerJob(targetSource, jobName, 0)
    local name = GetPlayerCharacterName and GetPlayerCharacterName(targetSource) or ("Player " .. targetSource)
    ShowNotification(targetSource, "You have been hired!")
    return true, name
end)

-- Get/set entry settings for a club
lib.callback.register("pickle_clubs:getEntrySettings", function(source, clubId)
    if not PlayerHasClubAccess(source, clubId) then return nil end
    local club = Clubs[clubId]
    if not club then return nil end
    return club.entry_settings or {}
end)

lib.callback.register("pickle_clubs:setEntrySettings", function(source, clubId, settings)
    if not PlayerHasClubAccess(source, clubId) then return false end
    local club = Clubs[clubId]
    if not club then return false end
    if UpdateClub then
        UpdateClub(clubId, { entry_settings = settings }, function() end)
    end
    return true
end)

-- Get nearby players with character names
lib.callback.register("pickle_clubs:getNearbyPlayers", function(source)
    local srcPed = GetPlayerPed(source)
    if not srcPed then return {} end
    local srcCoords = GetEntityCoords(srcPed)
    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid ~= source then
            local targetPed = GetPlayerPed(pid)
            if targetPed then
                local targetCoords = GetEntityCoords(targetPed)
                if #(srcCoords - targetCoords) < 10.0 then
                    local name = GetPlayerCharacterName and GetPlayerCharacterName(pid) or GetPlayerName(pid)
                    players[#players + 1] = {
                        source = pid,
                        name = name or ("Player " .. pid),
                    }
                end
            end
        end
    end
    return players
end)

CreateThread(function()
    RegisterEntityType("society", {
        label = "Society",
        description = "Society deposit/withdraw interaction point.",
        onStart = function(id, entityId) end,
        onRender = function(id, entityId, source) end,
        onUnrender = function(id, entityId, source) end,
        onStop = function(id, entityId) end,
    })
end)
