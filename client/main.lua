-- ESX VERSION - client/main.lua (Complete Fixed)
ESX = exports["es_extended"]:getSharedObject()
local PlayerData = {}
local CurrentCops = 0
local isOpen = false
local callSign = ""
local tabletObj = nil
local tabletDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local tabletAnim = "base"
local tabletProp = `prop_cs_tablet`
local tabletBone = 60309
local tabletOffset = vector3(0.03, 0.002, -0.0)
local tabletRot = vector3(10.0, 160.0, 0.0)
local coolDown = false
local lastVeh = nil
local lastPlate = nil

CreateThread(function()
    while ESX.GetPlayerData().job == nil do
        Wait(100)
    end
    PlayerData = ESX.GetPlayerData()
end)

CreateThread(function()
    if GetResourceState('ps-dispatch') == 'started' then
        TriggerServerEvent("ps-mdt:dispatchStatus", true)
    end
end)

-- ESX Events
RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
end)

RegisterNetEvent('esx:onPlayerLogout')
AddEventHandler('esx:onPlayerLogout', function()
    TriggerServerEvent("ps-mdt:server:OnPlayerUnload")
    PlayerData = {}
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    PlayerData.job = job
    if AllowedJob(job.name) then
        TriggerServerEvent("ps-mdt:server:ToggleDuty")
        TriggerServerEvent("ps-mdt:server:ClockSystem")
    end
end)

function AllowedJob(job)
    if not job then return false end
    return Config.AllowedJobs[job] or false
end

RegisterNetEvent("esx:setJob", function(job)
    if AllowedJob(job.name) then
        TriggerServerEvent("ps-mdt:server:ToggleDuty")
        TriggerServerEvent("ps-mdt:server:ClockSystem")
        
        if job.name == "police" then
            TriggerServerEvent("police:server:UpdateCurrentCops")
        end
        
        if job.name == "ambulance" then
            if PlayerData.onduty then
                TriggerServerEvent('hospital:server:AddDoctor', 'ambulance')
            else
                TriggerServerEvent('hospital:server:RemoveDoctor', 'ambulance')
            end
        end
        TriggerServerEvent("police:server:UpdateBlips")
    end
end)

RegisterNetEvent('police:SetCopCount', function(amount)
    CurrentCops = amount
end)

RegisterNetEvent('esx:setPlayerData', function(key, val)
    if GetInvokingResource() ~= "es_extended" then
        return
    end
    PlayerData[key] = val
end)

RegisterNetEvent('ps-mdt:client:selfregister')
AddEventHandler('ps-mdt:client:selfregister', function()
    GetPlayerWeaponInfos(function(weaponInfos)
        if weaponInfos and #weaponInfos > 0 then
            for _, weaponInfo in ipairs(weaponInfos) do
                TriggerServerEvent('mdt:server:registerweapon', weaponInfo.serialnumber, weaponInfo.weaponurl, weaponInfo.notes, weaponInfo.owner, weaponInfo.weapClass, weaponInfo.weaponmodel)
                ESX.ShowNotification("Weapon " .. weaponInfo.weaponmodel .. " has been added to police database.")
            end
        else
            ESX.ShowNotification("No weapons found to register.")
        end
    end)
end)

function GetPlayerWeaponInfos(cb)
    ESX.RegisterServerCallback('getWeaponInfo', function(source, cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        local weaponInfos = {}
        
        if Config.InventoryForWeaponsImages == "ox_inventory" then
            local inv = exports.ox_inventory:GetInventoryItems(source)
            for _, item in pairs(inv) do
                if string.find(item.name, "WEAPON_") then
                    local invImage = ("https://cfx-nui-ox_inventory/web/images/%s.png"):format(item.name)
                    if invImage then
                        local weaponInfo = {
                            serialnumber = item.metadata and item.metadata.serial or "Unknown",
                            owner = xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName,
                            weaponmodel = item.label or item.name,
                            weaponurl = invImage,
                            notes = "Self Registered",
                            weapClass = "Class 1",
                        }
                        table.insert(weaponInfos, weaponInfo)
                    end
                end
            end
        else
            -- For other ESX inventories, you'd need specific handling here
            -- This is inventory-dependent
        end
        cb(weaponInfos)
    end)
end

-- Helper function to get vehicle name for ESX
function GetVehicleName(vehicleModel)
    if not vehicleModel then return "Unknown Vehicle" end
    
    -- Try to get the display name
    local displayName = GetDisplayNameFromVehicleModel(vehicleModel)
    
    -- If no display name found, return the model name
    if displayName == "CARNOTFOUND" or displayName == vehicleModel then
        return vehicleModel
    end
    
    return displayName
end

--====================================================================================
------------------------------------------
--               MAIN PAGE              --
------------------------------------------
--====================================================================================

function EnableGUI(enable)
    if enable then
        SetNuiFocus(true, true)
        isOpen = true
        
        -- FIXED: Send the correct message structure that JavaScript expects
        SendNUIMessage({ 
            type = "show",
            enable = true,  -- ← THIS WAS MISSING!
            -- Add these required data that JS expects:
            rosterLink = Config.RosterLink[PlayerData.job.name] or "",
            sopLink = Config.sopLink[PlayerData.job.name] or "",
            job = PlayerData.job.name,
            jobType = GetJobType(PlayerData.job.name)
        })
        
        print("^2[ps-mdt] UI Opened with correct message structure^0")
    else
        SetNuiFocus(false, false)
        isOpen = false
        
        -- FIXED: Send correct hide message  
        SendNUIMessage({ 
            type = "show",
            enable = false  -- ← THIS TELLS JS TO HIDE
        })
        
        print("^1[ps-mdt] UI Closed^0")
    end
end

function RefreshGUI()
    SendNUIMessage({ type = "refresh" })
end

RegisterCommand("mdt", function()
    print("^3[ps-mdt] MDT command executed^0") -- Debug line
    
    local PlayerData = ESX.GetPlayerData()
    
    if not PlayerData then
        print("^1[ps-mdt] PlayerData is nil^0")
        return
    end
    
    if not PlayerData.job then
        print("^1[ps-mdt] PlayerData.job is nil^0")
        return
    end
    
    print("^3[ps-mdt] Current job:^0 " .. tostring(PlayerData.job.name))
    
    if AllowedJob(PlayerData.job.name) then
        print("^2[ps-mdt] Job is allowed, checking duty status^0")
        
        if Config.OnlyShowOnDuty then
            if PlayerData.job.onduty then
                print("^2[ps-mdt] Player is on duty, opening MDT^0")
                EnableGUI(true)
            else
                print("^1[ps-mdt] Player is not on duty^0")
                ESX.ShowNotification("You must be on duty to access the MDT!")
            end
        else
            print("^2[ps-mdt] Duty not required, opening MDT^0")
            EnableGUI(true)
        end
    else
        print("^1[ps-mdt] Job not allowed:^0 " .. tostring(PlayerData.job.name))
        ESX.ShowNotification("You don't have access to the MDT!")
    end
end)

RegisterKeyMapping('mdt', 'Open Mobile Data Terminal', 'keyboard', 'F5')

RegisterCommand("restartmdt", function(source, args, rawCommand)
    RefreshGUI()
end, false)

RegisterNUICallback("deleteBulletin", function(data, cb)
    local id = data.id
    TriggerServerEvent('mdt:server:deleteBulletin', id, data.title)
    cb(true)
end)

RegisterNUICallback("newBulletin", function(data, cb)
    local title = data.title
    local info = data.info
    local time = data.time
    TriggerServerEvent('mdt:server:NewBulletin', title, info, time)
    cb(true)
end)

RegisterNUICallback('escape', function(data, cb)
    EnableGUI(false)
    cb(true)
end)

RegisterNetEvent('mdt:client:dashboardbulletin', function(sentData)
    SendNUIMessage({ type = "bulletin", data = sentData })
end)

RegisterNetEvent('mdt:client:dashboardWarrants', function()
    ESX.TriggerServerCallback("mdt:server:getWarrants", function(data)
        if data then
            SendNUIMessage({ type = "warrants", data = data })
        end
    end)
end)

RegisterNUICallback("getAllDashboardData", function(data, cb)
    TriggerEvent("mdt:client:dashboardWarrants")
    cb(true)
end)

RegisterNetEvent('mdt:client:dashboardReports', function(sentData)
    SendNUIMessage({ type = "reports", data = sentData })
end)

RegisterNetEvent('mdt:client:dashboardCalls', function(sentData)
    SendNUIMessage({ type = "calls", data = sentData })
end)

RegisterNetEvent('mdt:client:newBulletin', function(sentData)
    SendNUIMessage({ type = "newBulletin", data = sentData })
end)

--====================================================================================
------------------------------------------
--               PROFILES PAGE          --
------------------------------------------
--====================================================================================

RegisterNUICallback("searchProfiles", function(data, cb)
    local p = promise.new()
    ESX.TriggerServerCallback('mdt:server:searchPeople', function(result)
        p:resolve(result)
    end, data.name)
    local result = Citizen.Await(p)
    cb(result)
end)

RegisterNUICallback("getProfileData", function(data, cb)
    local p = promise.new()
    ESX.TriggerServerCallback('mdt:server:GetProfileData', function(result)
        p:resolve(result)
    end, data.id)
    local result = Citizen.Await(p)
    cb(result)
end)

RegisterNUICallback("updateLicense", function(data, cb)
    TriggerServerEvent("mdt:server:updateLicense", data.cid, data.type, data.status)
    cb(true)
end)

RegisterNUICallback("saveProfile", function(data, cb)
    local pfp = data.pfp
    local information = data.information
    local tags = data.tags
    local gallery = data.gallery
    local identifier = data.id
    local fingerprint = data.fingerprint
    local fName = data.fName
    local sName = data.sName
    local jobtype = GetJobType(PlayerData.job.name)
    TriggerServerEvent('mdt:server:saveProfile', pfp, information, tags, gallery, identifier, fingerprint, fName, sName, jobtype)
    cb(true)
end)

RegisterNetEvent('mdt:client:getProfileData', function(sentData, isLimited)
    if not isLimited then
        local vehicles = sentData['vehicles']
        for i=1, #vehicles do
            sentData['vehicles'][i]['plate'] = string.upper(sentData['vehicles'][i]['plate'])
            local tempModel = vehicles[i]['model']
            if tempModel and tempModel ~= "Unknown" then
                if tempModel ~= "UNKNOWN" then
                    sentData['vehicles'][i]['model'] = tempModel
                end
            end
        end
    end
    SendNUIMessage({ type = "profileData", data = sentData, isLimited = isLimited })
end)

--====================================================================================
------------------------------------------
--               INCIDENTS PAGE         --
------------------------------------------
--====================================================================================

RegisterNUICallback("searchIncidents", function(data, cb)
    TriggerServerEvent('mdt:server:searchIncidents', data.name)
    cb(true)
end)

RegisterNUICallback("getIncidentData", function(data, cb)
    local id = data.id
    TriggerServerEvent('mdt:server:getIncidentData', id)
    cb(true)
end)

RegisterNUICallback("incidentSearchPerson", function(data, cb)
    local name = data.name
    TriggerServerEvent('mdt:server:incidentSearchPerson', name)
    cb(true)
end)

RegisterNUICallback("sendFine", function(data, cb)
    local citizenId, fine, incidentId = data.citizenId, data.fine, data.incidentId
    
    local p = promise.new()
    ESX.TriggerServerCallback('mdt:server:GetPlayerSourceId', function(result)
        p:resolve(result)
    end, citizenId)

    local targetSourceId = Citizen.Await(p)

    if fine > 0 then
        if Config.BillVariation then
            TriggerServerEvent("mdt:server:removeMoney", citizenId, fine, incidentId)
        else
            ExecuteCommand(('bill %s %s'):format(targetSourceId, fine))
            TriggerServerEvent("mdt:server:giveCitationItem", citizenId, fine, incidentId)
        end
    end
    cb(true)
end)

RegisterNUICallback("saveIncident", function(data, cb)
    TriggerServerEvent('mdt:server:saveIncident', data.ID, data.title, data.information, data.tags, data.officers, data.civilians, data.evidence, data.associated, data.time)
    cb(true)
end)

RegisterNUICallback("removeIncidentCriminal", function(data, cb)
    TriggerServerEvent('mdt:server:removeIncidentCriminal', data.cid, data.incidentId)
    cb(true)
end)

RegisterNUICallback("deleteIncident", function(data, cb)
    TriggerServerEvent('mdt:server:deleteIncident', data.id)
    cb(true)
end)

RegisterNUICallback("getAllIncidents", function(data, cb)
    ESX.TriggerServerCallback('mdt:server:getAllIncidents', function(result)
        SendNUIMessage({ type = "incidents", data = result })
    end)
    cb(true)
end)

-- FIXED: Reports refresh system  
RegisterNUICallback("getAllReports", function(data, cb)
    ESX.TriggerServerCallback('mdt:server:getAllReports', function(result)
        SendNUIMessage({ type = "getAllReports", data = result })
    end)
    cb(true)
end)

-- FIXED: Enhanced save incident with auto-refresh
RegisterNUICallback("saveIncident", function(data, cb)
    TriggerServerEvent('mdt:server:saveIncident', data.ID, data.title, data.information, data.tags, data.officers, data.civilians, data.evidence, data.associated, data.time)
    
    -- Auto-refresh incidents list after saving
    Wait(500) -- Small delay to ensure save completes
    ESX.TriggerServerCallback('mdt:server:getAllIncidents', function(result)
        SendNUIMessage({ type = "incidents", data = result })
        print("^2[MDT] Incidents list refreshed after save^0")
    end)
    
    cb(true)
end)

-- FIXED: Enhanced new incident with auto-refresh
RegisterNUICallback("newIncident", function(data, cb)
    local existing = data.existing
    local id = data.id
    local title = data.title
    local details = data.details
    local tags = data.tags
    local officers = data.officers
    local civilians = data.civilians
    local evidence = data.evidence
    local time = data.time
    
    TriggerServerEvent('mdt:server:newIncident', existing, id, title, details, tags, officers, civilians, evidence, time)
    
    -- Auto-refresh incidents list after creating
    Wait(500)
    ESX.TriggerServerCallback('mdt:server:getAllIncidents', function(result)
        SendNUIMessage({ type = "incidents", data = result })
        print("^2[MDT] Incidents list refreshed after creation^0")
    end)
    
    cb(true)
end)

RegisterNUICallback("newBolo", function(data, cb)
    local existing = data.existing
    local id = data.id
    local title = data.title
    local plate = data.plate
    local owner = data.owner
    local individual = data.individual
    local detail = data.detail
    local tags = data.tags
    local gallery = data.gallery
    local officers = data.officers
    local time = data.time
    
    TriggerServerEvent('mdt:server:newBolo', existing, id, title, plate, owner, individual, detail, tags, gallery, officers, time)
    cb(true)
end)

RegisterNetEvent('mdt:client:getIncidents', function(sentData)
    SendNUIMessage({ type = "incidents", data = sentData })
end)

RegisterNetEvent('mdt:client:getIncidentData', function(sentData, sentConvictions)
    SendNUIMessage({ type = "incidentData", data = sentData, convictions = sentConvictions })
end)

RegisterNetEvent('mdt:client:incidentSearchPerson', function(sentData)
    SendNUIMessage({ type = "incidentSearchPerson", data = sentData })
end)

RegisterNetEvent('mdt:client:updateIncidentDbId', function(sentId)
    SendNUIMessage({ type = "updateIncidentDbId", data = sentId })
end)

--====================================================================================
------------------------------------------
--               VEHICLES PAGE          --
------------------------------------------
--====================================================================================

-- FIXED: Search vehicles function for ESX
RegisterNUICallback("searchVehicles", function(data, cb)
    local p = promise.new()
    ESX.TriggerServerCallback('mdt:server:searchVehicles', function(result)
        for i=1, #result do
            result[i]['plate'] = string.upper(result[i]['plate'])
            if result[i]['vehicle'] and result[i]['vehicle'] ~= '' then
                -- FIXED: Use proper vehicle name function for ESX
                result[i]['model'] = GetVehicleName(result[i]['vehicle'])
            else
                result[i]['model'] = "UNKNOWN"
            end
        end
        p:resolve(result)
    end, data.name)

    local result = Citizen.Await(p)
    cb(result)
end)

RegisterNUICallback("getVehicleData", function(data, cb)
    local plate = data.plate
    TriggerServerEvent('mdt:server:getVehicleData', plate)
    cb(true)
end)

RegisterNUICallback("saveVehicleInfo", function(data, cb)
    local dbid = data.dbid
    local plate = data.plate
    local imageurl = data.imageurl
    local notes = data.notes
    local stolen = data.stolen
    local code5 = data.code5
    local impound = data.impound
    local points = data.points
    local JobType = GetJobType(PlayerData.job.name)
    
    if JobType == 'police' and impound.impoundChanged == true then
        if impound.impoundActive then
            local found = 0
            local plate = string.upper(string.gsub(data['plate'], "^%s*(.-)%s*$", "%1"))
            local vehicles = GetGamePool('CVehicle')

            for k,v in pairs(vehicles) do
                local plt = string.upper(string.gsub(GetVehicleNumberPlateText(v), "^%s*(.-)%s*$", "%1"))
                if plt == plate then
                    local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(v))
                    if dist < 5.0 then
                        found = VehToNet(v)
                        SendNUIMessage({ type = "greenImpound" })
                        TriggerServerEvent('mdt:server:saveVehicleInfo', dbid, plate, imageurl, notes, stolen, code5, impound, points)
                    end
                    break
                end
            end

            if found == 0 then
                ESX.ShowNotification('Vehicle not found!')
                SendNUIMessage({ type = "redImpound" })
            end
        else
            local ped = PlayerPedId()
            local playerPos = GetEntityCoords(ped)
            for k, v in pairs(Config.ImpoundLocations) do
                if (#(playerPos - vector3(v.x, v.y, v.z)) < 20.0) then
                    impound.CurrentSelection = k
                    TriggerServerEvent('mdt:server:saveVehicleInfo', dbid, plate, imageurl, notes, stolen, code5, impound, points)
                    break
                end
            end
        end
    else
        TriggerServerEvent('mdt:server:saveVehicleInfo', dbid, plate, imageurl, notes, stolen, code5, impound, points)
    end
    cb(true)
end)

-- FIXED: Get vehicle data event for ESX
RegisterNetEvent('mdt:client:getVehicleData', function(sentData)
    if sentData and sentData[1] then
        local vehicle = sentData[1]
        vehicle['color'] = Config.ColorInformation[vehicle['color1']]
        vehicle['colorName'] = Config.ColorNames[vehicle['color1']]
        
        -- FIXED: Use proper vehicle name function for ESX
        if vehicle.vehicle then
            vehicle.model = GetVehicleName(vehicle.vehicle)
        else
            vehicle.model = "Unknown Vehicle"
        end
        
        vehicle['class'] = Config.ClassList[GetVehicleClassFromName(vehicle['vehicle'])] or 'Unknown'
        vehicle['vehicle'] = nil
        SendNUIMessage({ type = "getVehicleData", data = vehicle })
    end
end)

RegisterNetEvent('mdt:client:updateVehicleDbId', function(sentData)
    SendNUIMessage({ type = "updateVehicleDbId", data = tonumber(sentData) })
end)

--====================================================================================
------------------------------------------
--                Weapons PAGE          --
------------------------------------------
--====================================================================================

RegisterNUICallback("searchWeapons", function(data, cb)
    local p = promise.new()
    ESX.TriggerServerCallback('mdt:server:searchWeapons', function(result)
        p:resolve(result)
    end, data.name)
    local result = Citizen.Await(p)
    cb(result)
end)

RegisterNUICallback("saveWeaponInfo", function(data, cb)
    local serial = data.serial
    local notes = data.notes
    local imageurl = data.imageurl
    local owner = data.owner
    local weapClass = data.weapClass
    local weapModel = data.weapModel
    local JobType = GetJobType(PlayerData.job.name)
    if JobType == 'police' then
        TriggerServerEvent('mdt:server:saveWeaponInfo', serial, imageurl, notes, owner, weapClass, weapModel)
    end
    cb(true)
end)

RegisterNUICallback("getWeaponData", function(data, cb)
    local serial = data.serial
    TriggerServerEvent('mdt:server:getWeaponData', serial)
    cb(true)
end)

RegisterNetEvent('mdt:client:getWeaponData', function(sentData)
    if sentData and sentData[1] then
        local results = sentData[1]
        SendNUIMessage({ type = "getWeaponData", data = results })
    end
end)

RegisterNetEvent('mdt:client:updateWeaponDbId', function(sentData)
    SendNUIMessage({ type = "updateWeaponDbId", data = tonumber(sentData) })
end)

--====================================================================================
------------------------------------------
--               REPORTS PAGE           --
------------------------------------------
--====================================================================================

RegisterNUICallback("getAllReports", function(data, cb)
    TriggerServerEvent('mdt:server:getAllReports')
    cb(true)
end)

RegisterNUICallback("getReportData", function(data, cb)
    local id = data.id
    TriggerServerEvent('mdt:server:getReportData', id)
    cb(true)
end)

RegisterNUICallback("searchReports", function(data, cb)
    local name = data.name
    TriggerServerEvent('mdt:server:searchReports', name)
    cb(true)
end)

RegisterNUICallback("newReport", function(data, cb)
    local existing = data.existing
    local id = data.id
    local title = data.title
    local reporttype = data.type
    local details = data.details
    local tags = data.tags
    local gallery = data.gallery
    local officers = data.officers
    local civilians = data.civilians
    local time = data.time

    TriggerServerEvent('mdt:server:newReport', existing, id, title, reporttype, details, tags, gallery, officers, civilians, time)
    cb(true)
end)

RegisterNUICallback("deleteReport", function(data, cb)
    TriggerServerEvent('mdt:server:deleteReport', data.id)
    cb(true)
end)

RegisterNetEvent('mdt:client:getAllReports', function(sentData)
    SendNUIMessage({ type = "getAllReports", data = sentData })
end)

RegisterNetEvent('mdt:client:getReportData', function(sentData)
    SendNUIMessage({ type = "getReportData", data = sentData })
end)

RegisterNetEvent('mdt:client:updateReportId', function(sentId)
    SendNUIMessage({ type = "updateReportId", data = sentId })
end)

--====================================================================================
------------------------------------------
--               BOLOS PAGE              --
------------------------------------------
--====================================================================================

RegisterNUICallback("searchBolos", function(data, cb)
    local searchVal = data.searchVal
    TriggerServerEvent('mdt:server:searchBolos', searchVal)
    cb(true)
end)

RegisterNUICallback("getAllBolos", function(data, cb)
    TriggerServerEvent('mdt:server:getAllBolos')
    cb(true)
end)

RegisterNUICallback("getBoloData", function(data, cb)
    local id = data.id
    TriggerServerEvent('mdt:server:getBoloData', id)
    cb(true)
end)

RegisterNUICallback("deleteBolo", function(data, cb)
    TriggerServerEvent('mdt:server:deleteBolo', data.id)
    cb(true)
end)

RegisterNetEvent('mdt:client:getAllBolos', function(sentData)
    SendNUIMessage({ type = "bolos", data = sentData })
end)

RegisterNetEvent('mdt:client:getBoloData', function(sentData)
    SendNUIMessage({ type = "boloData", data = sentData })
end)

RegisterNetEvent('mdt:client:boloComplete', function(sentData)
    SendNUIMessage({ type = "boloComplete", data = sentData })
end)

RegisterNetEvent('mdt:client:updateBolo', function(sentId)
    SendNUIMessage({ type = "updateBolo", data = sentId })
end)

--====================================================================================
------------------------------------------
--               CALLS PAGE              --
------------------------------------------
--====================================================================================

RegisterNUICallback("searchCalls", function(data, cb)
    local searchCall = data.searchCall
    TriggerServerEvent('mdt:server:searchCalls', searchCall)
    cb(true)
end)

RegisterNetEvent('mdt:client:getCalls', function(calls, callid)
    SendNUIMessage({ type = "calls", data = calls })
end)

--====================================================================================
------------------------------------------
--               CONVICTIONS PAGE       --
------------------------------------------
--====================================================================================

RegisterNUICallback("saveConviction", function(data, cb)
    local identifier = data.cid
    local linkedincident = data.linkedincident
    local charges = data.charges
    local fine = data.fine
    local sentence = data.sentence
    local recfine = data.recfine
    local recsentence = data.recsentence
    local time = data.time
    TriggerServerEvent('mdt:server:saveConviction', identifier, linkedincident, charges, fine, sentence, recfine, recsentence, time)
    cb(true)
end)

RegisterNUICallback("deleteConviction", function(data, cb)
    TriggerServerEvent('mdt:server:deleteConviction', data.id)
    cb(true)
end)

RegisterNetEvent('mdt:client:updateConvictionDbId', function(sentId)
    SendNUIMessage({ type = "updateConvictionDbId", data = sentId })
end)

--====================================================================================
------------------------------------------
--               LOGS PAGE              --
------------------------------------------
--====================================================================================

RegisterNUICallback("getAllLogs", function(data, cb)
    TriggerServerEvent('mdt:server:getAllLogs')
    cb(true)
end)

RegisterNetEvent('mdt:client:getAllLogs', function(sentData)
    SendNUIMessage({ type = "getAllLogs", data = sentData })
end)

--====================================================================================
------------------------------------------
--               PENAL CODE PAGE        --
------------------------------------------
--====================================================================================

RegisterNUICallback("getPenalCode", function(data, cb)
    TriggerServerEvent('mdt:server:getPenalCode')
    cb(true)
end)

RegisterNetEvent('mdt:client:getPenalCode', function(titles, penalcode)
    SendNUIMessage({ type = "getPenalCode", titles = titles, penalcode = penalcode })
end)

--====================================================================================
------------------------------------------
--               BULLETINS PAGE         --
------------------------------------------
--====================================================================================

RegisterNUICallback("getAllBulletins", function(data, cb)
    TriggerServerEvent('mdt:server:getAllBulletins')
    cb(true)
end)

RegisterNetEvent('mdt:client:getAllBulletins', function(sentData)
    SendNUIMessage({ type = "getAllBulletins", data = sentData })
end)

--====================================================================================
------------------------------------------
--               DISPATCH PAGE          --
------------------------------------------
--====================================================================================

RegisterNUICallback("sendDispatchMessage", function(data, cb)
    local message = data.message
    local time = data.time
    TriggerServerEvent('mdt:server:sendMessage', message, time)
    cb(true)
end)

RegisterNUICallback("getDispatchMessages", function(data, cb)
    TriggerServerEvent('mdt:server:refreshDispatchMsgs')
    cb(true)
end)

RegisterNUICallback("dispatchNotify", function(data, cb)
    local info = data
    local PlayerData = ESX.GetPlayerData()
    if string.find(info['message'], PlayerData.firstName) then
        ESX.ShowNotification("You have been mentioned in dispatch!")
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
        PlaySoundFrontend(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", 0)
    end
    cb(true)
end)

RegisterNUICallback("getCallResponses", function(data, cb)
    TriggerServerEvent('mdt:server:getCallResponses', data.callid or data.id)
    cb(true)
end)

RegisterNUICallback("sendCallResponse", function(data, cb)
    TriggerServerEvent('mdt:server:sendCallResponse', data.message, data.time, data.callid)
    cb(true)
end)

RegisterNUICallback("removeImpound", function(data, cb)
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        local playerPos = GetEntityCoords(ped)
        if playerPos and Config.ImpoundLocations then
            for k, v in pairs(Config.ImpoundLocations) do
                if v.x and v.y and v.z then
                    local distance = #(playerPos - vector3(v.x, v.y, v.z))
                    if distance < 20.0 then
                        TriggerServerEvent('mdt:server:removeImpound', data['plate'], k)
                        break
                    end
                end
            end
        end
    end
    cb('ok')
end)

RegisterNUICallback("statusImpound", function(data, cb)
    TriggerServerEvent('mdt:server:statusImpound', data['plate'])
    cb('ok')
end)

RegisterNUICallback('openCamera', function(data)
    local camId = tonumber(data.cam)
    TriggerEvent('police:client:ActiveCamera', camId)
end)

RegisterNUICallback("toggleDuty", function(data, cb)
    TriggerServerEvent('esx:toggleDuty')
    TriggerServerEvent('ps-mdt:server:ClockSystem')
    cb(true)
end)

RegisterNUICallback("setCallsign", function(data, cb)
    TriggerServerEvent('mdt:server:setCallsign', data.cid, data.newcallsign)
    cb(true)
end)

RegisterNUICallback("setRadio", function(data, cb)
    TriggerServerEvent('mdt:server:setRadio', data.cid, data.newradio)
    cb(true)
end)

RegisterNUICallback('SetHouseLocation', function(data, cb)
    if data.coord and data.coord[1] then
        local coords = {}
        for word in data.coord[1]:gmatch('[^,%s]+') do
            local num = tonumber(word)
            if num then
                coords[#coords+1] = num
            end
        end
        if coords[1] and coords[2] then
            SetNewWaypoint(coords[1], coords[2])
            ESX.ShowNotification('GPS has been set!')
        end
    end
    cb('ok')
end)

--====================================================================================
------------------------------------------
--               EVENT HANDLERS         --
------------------------------------------
--====================================================================================

RegisterNetEvent('mdt:client:attachedUnits', function(sentData, callid)
    SendNUIMessage({ type = "attachedUnits", data = sentData, callid = callid })
end)

RegisterNetEvent('mdt:client:setWaypoint', function(callInformation)
    if callInformation['coords'] and callInformation['coords']['x'] and callInformation['coords']['y'] then
        SetNewWaypoint(callInformation['coords']['x'], callInformation['coords']['y'])
    end
end)

RegisterNetEvent('mdt:client:setWaypoint:unit', function(sentData)
    SetNewWaypoint(sentData.x, sentData.y)
end)

RegisterNetEvent('mdt:client:dashboardMessage', function(sentData)
    local PlayerData = ESX.GetPlayerData()
    local job = PlayerData.job.name
    if AllowedJob(job) then 
        SendNUIMessage({ type = "dispatchmessage", data = sentData })
    end
end)

RegisterNetEvent('mdt:client:dashboardMessages', function(sentData)
    SendNUIMessage({ type = "dispatchmessages", data = sentData })
end)

RegisterNetEvent('mdt:client:setRadio', function(radio)
    if type(tonumber(radio)) == "number" then
        if GetResourceState('pma-voice') == 'started' then
            exports["pma-voice"]:setVoiceProperty("radioEnabled", true)
            exports["pma-voice"]:setRadioChannel(tonumber(radio))
        end
        ESX.ShowNotification("You have set your radio frequency to "..radio..".")
    else
        ESX.ShowNotification("Invalid Station (Please enter a number)")
    end
end)

RegisterNetEvent('mdt:client:sig100', function(radio, type)
    local PlayerData = ESX.GetPlayerData()
    local job = PlayerData.job.name
    local duty = PlayerData.job.onduty
    if AllowedJob(job) and duty then
        if type == true then
            ESX.ShowNotification("Radio "..radio.." is currently signal 100!")
        else
            ESX.ShowNotification("Signal 100 cleared for radio "..radio)
        end
    end
end)

--====================================================================================
------------------------------------------
--               UTILITY FUNCTIONS      --
------------------------------------------
--====================================================================================

function GetJobType(job)
    if Config.PoliceJobs[job] then
        return 'police'
    elseif Config.AmbulanceJobs[job] then
        return 'ambulance'
    elseif Config.DojJobs[job] then
        return 'doj'
    else
        return nil
    end
end