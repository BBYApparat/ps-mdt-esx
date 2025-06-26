-- ESX VERSION - Complete server/main.lua (Full Version)
ESX = exports["es_extended"]:getSharedObject()

local incidents = {}
local convictions = {}
local bolos = {}
local MugShots = {}
local activeUnits = {}
local impound = {}
local dispatchMessages = {}
local isDispatchRunning = false
local antiSpam = false
local calls = {}

--------------------------------
-- SET YOUR WEBHOOKS IN HERE
-- Images for mug shots will be uploaded here. Add a Discord webhook. 
local MugShotWebhook = ''

-- Clock-in notifications for duty. Add a Discord webhook.
-- Command /mdtleaderboard, will display top players per clock-in hours.
local ClockinWebhook = ''

-- Incident and Incident editing. Add a Discord webhook.
-- Incident Author, Title, and Report will display in webhook post.
local IncidentWebhook = ''
--------------------------------

ESX.RegisterServerCallback('ps-mdt:server:MugShotWebhook', function(source, cb)
    if MugShotWebhook == '' then
        print("\27[31mA webhook is missing in: MugShotWebhook (server > main.lua > line 16)\27[0m")
    else
        cb(MugShotWebhook)
    end
end)

local function GetActiveData(identifier)
	local player = type(identifier) == "string" and identifier or tostring(identifier)
	if player then
		return activeUnits[player] and true or false
	end
	return false
end

local function IsPoliceOrEms(job)
	for k, v in pairs(Config.PoliceJobs) do
        if job == k then
            return true
        end
    end
         
    for k, v in pairs(Config.AmbulanceJobs) do
        if job == k then
            return true
        end
    end
    return false
end

RegisterServerEvent("ps-mdt:dispatchStatus", function(bool)
	isDispatchRunning = bool
end)

function sendToDiscord(color, name, message, footer)
    local embed = {
        {
            ["color"] = color,
            ["title"] = "**".. name .."**",
            ["description"] = message,
            ["footer"] = {
                ["text"] = footer,
            },
        }
    }
    PerformHttpRequest(ClockinWebhook, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end

function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function GetBoloStatus(plate)
    local result = MySQL.query.await("SELECT * FROM mdt_bolos where plate = @plate", {['@plate'] = plate})
	if result and result[1] then
		local title = result[1]['title']
		local boloId = result[1]['id']
		return true, title, boloId
	end
	return false
end

function GetWarrantStatus(plate)
    local result = MySQL.query.await("SELECT ov.plate, ov.owner, m.id FROM owned_vehicles ov INNER JOIN mdt_convictions m ON ov.owner = m.cid WHERE m.warrant =1 AND ov.plate =?", {plate})
    if result and result[1] then
        local identifier = result[1]['owner']
        local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
        local owner
        if xPlayer then
            owner = xPlayer.variables.firstName.." "..xPlayer.variables.lastName
        else
            -- Player offline, get from database
            local playerResult = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = @identifier', {['@identifier'] = identifier})
            if playerResult and playerResult[1] then
                owner = playerResult[1]['firstname'].." "..playerResult[1]['lastname']
            else
                owner = "Unknown"
            end
        end
        local incidentId = result[1]['id']
        return true, owner, incidentId
    end
    return false
end

function GetVehicleInformation(plate)
	local result = MySQL.query.await('SELECT * FROM mdt_vehicleinfo WHERE plate = @plate', {['@plate'] = plate})
    if result[1] then
        return result[1]
    else
        return false
    end
end

function GetVehicleOwner(plate)
    local result = MySQL.query.await('SELECT plate, owner, id FROM owned_vehicles WHERE plate = @plate', {['@plate'] = plate})
    if result and result[1] then
        local identifier = result[1]['owner']
        local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
        if xPlayer then
            local owner = xPlayer.variables.firstName.." "..xPlayer.variables.lastName
            return owner
        else
            -- Player offline, get from database
            local playerResult = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = @identifier', {['@identifier'] = identifier})
            if playerResult and playerResult[1] then
                return playerResult[1]['firstname'].." "..playerResult[1]['lastname']
            end
        end
    end
    return "Unknown"
end

if Config.UseWolfknightRadar == true then
	RegisterNetEvent("wk:onPlateScanned")
	AddEventHandler("wk:onPlateScanned", function(cam, plate, index)
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		local vehicleOwner = GetVehicleOwner(plate)
		local bolo, title, boloId = GetBoloStatus(plate)
		local warrant, owner, incidentId = GetWarrantStatus(plate)
		local driversLicense = xPlayer.getInventoryItem('driverlicense') and xPlayer.getInventoryItem('driverlicense').count > 0

		if bolo == true then
			TriggerClientEvent('esx:showNotification', src, 'BOLO ID: '..boloId..' | Title: '..title..' | Registered Owner: '..vehicleOwner..' | Plate: '..plate)
		end
		if warrant == true then
			TriggerClientEvent('esx:showNotification', src, 'WANTED - INCIDENT ID: '..incidentId..' | Registered Owner: '..owner..' | Plate: '..plate)
		end

		if Config.PlateScanForDriversLicense and driversLicense == false and vehicleOwner then
			TriggerClientEvent('esx:showNotification', src, 'NO DRIVERS LICENCE | Registered Owner: '..vehicleOwner..' | Plate: '..plate)
		end

		if bolo or warrant or (Config.PlateScanForDriversLicense and not driversLicense) and vehicleOwner then
			TriggerClientEvent("wk:togglePlateLock", src, cam, true, 1)
		end
	end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
	Wait(3000)
	if MugShotWebhook == '' then
		print("\27[31mA webhook is missing in: MugShotWebhook (server > main.lua > line 16)\27[0m")
    end
    if ClockinWebhook == '' then
		print("\27[31mA webhook is missing in: ClockinWebhook (server > main.lua > line 20)\27[0m")
	end
	if GetResourceState('ps-dispatch') == 'started' then
		local calls = exports['ps-dispatch']:GetDispatchCalls()
		return calls
	end
end)

RegisterNetEvent("ps-mdt:server:OnPlayerUnload", function()
	--// Delete player from the MDT on logout
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetActiveData(xPlayer.identifier) then
		activeUnits[xPlayer.identifier] = nil
	end
end)

AddEventHandler('esx:playerDropped', function(playerId, reason)
    local xPlayer = ESX.GetPlayerFromId(playerId)
	if xPlayer == nil then return end -- Player not loaded in correctly and dropped early

    local time = os.date("%Y-%m-%d %H:%M:%S")
    local job = xPlayer.job.name
    local firstName = xPlayer.variables.firstName or "Unknown"
    local lastName = xPlayer.variables.lastName or "Unknown"

    -- Auto clock out if the player is off duty
    if IsPoliceOrEms(job) and xPlayer.getMeta('onduty') then
		MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id ORDER BY id DESC LIMIT 1', {
			['@user_id'] = xPlayer.identifier
		})

		local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id', {
			['@user_id'] = xPlayer.identifier
		})
		if result then
			local time_formatted = format_time(tonumber(result))
			sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. xPlayer.job.name .. '**\n\nRank: **' .. xPlayer.job.grade_name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
		end
	end

    -- Delete player from the MDT on logout
    if xPlayer ~= nil then
        if GetActiveData(xPlayer.identifier) then
            activeUnits[xPlayer.identifier] = nil
        end
    else
        local license = ESX.GetIdentifier(src, "license")
        local identifiers = GetCitizenID(license)

        for _, v in pairs(identifiers) do
            if GetActiveData(v.identifier) then
                activeUnits[v.identifier] = nil
            end
        end
    end
end)

RegisterNetEvent("ps-mdt:server:ToggleDuty", function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer.getMeta('onduty') then
	--// Remove from MDT
	if GetActiveData(xPlayer.identifier) then
		activeUnits[xPlayer.identifier] = nil
	end
    end
end)

RegisterCommand("mdtleaderboard", "Show MDT leaderboard", {}, false, function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    local job = xPlayer.job.name

    if not IsPoliceOrEms(job) then
        TriggerClientEvent('esx:showNotification', source, "You don't have permission to use this command.")
        return
    end

	local result = MySQL.Sync.fetchAll('SELECT firstname, lastname, total_time FROM mdt_clocking ORDER BY total_time DESC')

    local leaderboard_message = '**MDT Leaderboard**\n\n'

    for i, record in ipairs(result) do
		local firstName = record.firstname:sub(1,1):upper()..record.firstname:sub(2)
		local lastName = record.lastname:sub(1,1):upper()..record.lastname:sub(2)
		local total_time = format_time(record.total_time)
	
		leaderboard_message = leaderboard_message .. i .. '. **' .. firstName .. ' ' .. lastName .. '** - ' .. total_time .. '\n'
	end

    sendToDiscord(16753920, "MDT Leaderboard", leaderboard_message, "ps-mdt | Made by Project Sloth")
    TriggerClientEvent('esx:showNotification', source, "MDT leaderboard sent to Discord!")
end)

RegisterNetEvent("ps-mdt:server:ClockSystem", function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer.job.name
    local firstName = xPlayer.variables.firstName
    local lastName = xPlayer.variables.lastName
    local onDuty = xPlayer.getMeta('onduty')

    if IsPoliceOrEms(job) then
        if onDuty then
            -- Clock In
            MySQL.insert.await('INSERT INTO mdt_clocking (user_id, firstname, lastname, clock_in_time) VALUES (@user_id, @firstname, @lastname, NOW())', {
                ['@user_id'] = xPlayer.identifier,
                ['@firstname'] = firstName,
                ['@lastname'] = lastName
            })
            sendToDiscord(65280, "MDT Clock-In", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. job .. '**\n\nRank: **' .. xPlayer.job.grade_name .. '**\n\nStatus: **On Duty**', "ps-mdt | Made by Project Sloth")
        else
            -- Clock Out
            MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id AND clock_out_time IS NULL ORDER BY id DESC LIMIT 1', {
                ['@user_id'] = xPlayer.identifier
            })

            local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id AND clock_out_time IS NOT NULL ORDER BY id DESC LIMIT 1', {
                ['@user_id'] = xPlayer.identifier
            })
            if result then
                local time_formatted = format_time(tonumber(result))
                sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. job .. '**\n\nRank: **' .. xPlayer.job.grade_name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
            end
        end
    end
end)

-- Returns the source for the given identifier
ESX.RegisterServerCallback('mdt:server:GetPlayerSourceId', function(source, cb, targetIdentifier)
    local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
    if targetPlayer == nil then 
        TriggerClientEvent('esx:showNotification', source, "Citizen seems Asleep / Missing")
        return
    end
    local targetSource = targetPlayer.source
    cb(targetSource)
end)

ESX.RegisterServerCallback('mdt:server:GetProfPic', function(source, cb, sentIdentifier, JobType)
	local result = MySQL.query.await('SELECT pfp FROM `mdt_data` WHERE cid = ? AND jobtype = ? LIMIT 1', { sentIdentifier, JobType })
	if result and result[1] then
		cb(result[1]['pfp'])
	else
		cb(nil)
	end
end)

ESX.RegisterServerCallback('mdt:server:GetActiveUnits', function(source, cb)
	cb(activeUnits)
end)

ESX.RegisterServerCallback('mdt:server:SearchCalls', function(source, cb, sentData)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if GetResourceState('ps-dispatch') == 'started' then
			local calls = exports['ps-dispatch']:GetDispatchCalls()
			cb(calls)
		else
			cb({})
		end
	end
end)

RegisterNetEvent('mdt:server:callDragAttach', function(callid, identifier)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local playerdata = {
		name = xPlayer.variables.firstName.. " "..xPlayer.variables.lastName,
		job = xPlayer.job.name,
		cid = xPlayer.identifier,
		callsign = xPlayer.getMeta('callsign') or '000'
	}
	local callid = tonumber(callid)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			TriggerEvent('dispatch:addUnit', callid, playerdata, function(newNum)
				TriggerClientEvent('mdt:client:callAttach', -1, callid, newNum)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:setWaypoint:unit', function(identifier)
	local src = source
	local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
	if xPlayer then
		local PlayerCoords = GetEntityCoords(GetPlayerPed(xPlayer.source))
		TriggerClientEvent("mdt:client:setWaypoint:unit", src, PlayerCoords)
	end
end)

-- Dispatch chat
RegisterNetEvent('mdt:server:sendMessage', function(message, time)
	if message and time then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			MySQL.scalar("SELECT pfp FROM `mdt_data` WHERE cid=:id LIMIT 1", {
				id = xPlayer.identifier
			}, function(data)
				if data == "" then data = nil end
				local ProfilePicture = ProfPic(xPlayer.variables.sex, data)
				local callsign = xPlayer.getMeta('callsign') or "000"
				local Item = {
					profilepic = ProfilePicture,
					callsign = callsign,
					cid = xPlayer.identifier,
					name = '('..callsign..') '..xPlayer.variables.firstName.. " "..xPlayer.variables.lastName,
					message = message,
					time = time,
					job = xPlayer.job.name
				}
				dispatchMessages[#dispatchMessages+1] = Item
				TriggerClientEvent('mdt:client:dashboardMessage', -1, Item)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:refreshDispatchMsgs', function()
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if IsJobAllowedToMDT(xPlayer.job.name) then
		TriggerClientEvent('mdt:client:dashboardMessages', src, dispatchMessages)
	end
end)

RegisterNetEvent('mdt:server:getCallResponses', function(callid)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if IsPoliceOrEms(xPlayer.job.name) then
		if isDispatchRunning then
			TriggerClientEvent('mdt:client:getCallResponses', src, calls[callid]['responses'], callid)
		end
	end
end)

RegisterNetEvent('mdt:server:sendCallResponse', function(message, time, callid)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local name = xPlayer.variables.firstName.. " "..xPlayer.variables.lastName
	if IsPoliceOrEms(xPlayer.job.name) then
		TriggerEvent('dispatch:sendCallResponse', src, callid, message, time, function(isGood)
			if isGood then
				TriggerClientEvent('mdt:client:sendCallResponse', -1, message, time, callid, name)
			end
		end)
	end
end)

RegisterNetEvent('mdt:server:setRadio', function(identifier, newRadio)
	local src = source
	local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
	if not targetPlayer then
		TriggerClientEvent("esx:showNotification", src, 'Player not found!')
		return
	end
	
	local targetSource = targetPlayer.source
	local targetName = targetPlayer.variables.firstName .. ' ' .. targetPlayer.variables.lastName

	local radio = targetPlayer.getInventoryItem("radio")
	if radio and radio.count > 0 then
		TriggerClientEvent('mdt:client:setRadio', targetSource, newRadio)
	else
		TriggerClientEvent("esx:showNotification", src, targetName..' does not have a radio!')
	end
end)

RegisterNetEvent('mdt:server:setDispatchWaypoint', function(callid, identifier)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local callid = tonumber(callid)
	local JobType = GetJobType(xPlayer.job.name)
	if not callid then return end
	if JobType == 'police' or JobType == 'ambulance' then
		if isDispatchRunning then
			for i = 1, #calls do
				if calls[i]['id'] == callid then
					TriggerClientEvent('mdt:client:setWaypoint', src, calls[i])
					return
				end
			end
		end
	end
end)

RegisterNetEvent('mdt:server:attachedUnits', function(callid)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local JobType = GetJobType(xPlayer.job.name)
	if not callid then return end
    if JobType == 'police' or JobType == 'ambulance' then
        if isDispatchRunning then
            for i = 1, #calls do
                if calls[i]['id'] == callid then
                    TriggerClientEvent('mdt:client:attachedUnits', src, calls[i]['units'], callid)
                    return
                end
            end
        end
    end
end)

ESX.RegisterServerCallback('mdt:server:searchVehicles', function(source, cb, sentData)
	if not sentData then  return cb({}) end
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if not PermCheck(source, xPlayer) then return cb({}) end

	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'doj' then
		local vehicles = MySQL.query.await("SELECT pv.plate, pv.vehicle, pv.stored, u.firstname, u.lastname FROM `owned_vehicles` pv LEFT JOIN users u ON pv.owner = u.identifier WHERE LOWER(`plate`) LIKE :query OR LOWER(`vehicle`) LIKE :query LIMIT 25", {
			query = string.lower('%'..sentData..'%')
		})

		if not next(vehicles) then cb({}) return end

		for _, value in ipairs(vehicles) do
			if value.stored == 0 then
				value.state = "Out"
			elseif value.stored == 1 then
				value.state = "Garaged"
			elseif value.stored == 2 then
				value.state = "Impounded"
			end

			value.bolo = false
			local boloResult = GetBoloStatus(value.plate)
			if boloResult then
				value.bolo = true
			end

			value.code = false
			value.stolen = false
			value.image = "img/not-found.webp"
			local info = GetVehicleInformation(value.plate)
			if info then
				value.code = info['code5']
				value.stolen = info['stolen']
				value.image = info['image']
			end

			value.owner = value.firstname .. " " .. value.lastname
		end
		return cb(vehicles)
	end

	return cb({})
end)

RegisterNetEvent('mdt:server:getVehicleData', function(plate)
	if plate then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local vehicle = MySQL.query.await("select pv.plate, pv.vehicle, pv.stored, u.firstname, u.lastname FROM `owned_vehicles` pv LEFT JOIN users u ON pv.owner = u.identifier WHERE pv.plate = :plate", {
					plate = plate
				})
				TriggerClientEvent('mdt:client:getVehicleData', src, vehicle)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:saveVehicleInfo', function(dbid, plate, imageurl, notes, stolen, code5, impoundInfo, points)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		if dbid == 0 then
			local id = MySQL.insert.await('INSERT INTO `mdt_vehicleinfo` (`plate`, `imageurl`, `notes`, `stolen`, `code5`, `points`) VALUES (?, ?, ?, ?, ?, ?)', {
				plate, imageurl, notes, stolen, code5, points
			})
			TriggerClientEvent('mdt:client:updateVehicleDbId', src, id)
			AddLog("A new vehicle info for: "..plate.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
		else
			local affectedRows = MySQL.update.await('UPDATE `mdt_vehicleinfo` SET `imageurl` = ?, `notes` = ?, `stolen` = ?, `code5` = ?, `points` = ? WHERE `plate` = ?', {
				imageurl, notes, stolen, code5, points, plate
			})
			AddLog("Vehicle info for: "..plate.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
		end
	end
end)

ESX.RegisterServerCallback('mdt:server:searchPeople', function(source, cb, sentData)
	if not sentData then return cb({}) end
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if not PermCheck(src, xPlayer) then return cb({}) end

	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'doj' then
		local searchData = string.lower('%'..sentData..'%')
		local matches = MySQL.query.await("SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number FROM `users` WHERE LOWER(`firstname`) LIKE :query OR LOWER(`lastname`) LIKE :query OR LOWER(`identifier`) LIKE :query LIMIT 25", {
			query = searchData
		})

		for _, value in ipairs(matches) do
			value.image = "img/not-found.webp"
			local profileData = GetPersonInformation(value.identifier, JobType)
			if profileData then
				value.image = profileData.pfp or "img/not-found.webp"
			end

			value.warrant = false
			local warrantData = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_incidents WHERE FIND_IN_SET(?, JSON_EXTRACT(civsinvolved, "$[*].cid")) > 0 AND warrant = 1', { value.identifier })
			if warrantData and warrantData > 0 then
				value.warrant = true
			end
		end

		return cb(matches)
	end
	return cb({})
end)

ESX.RegisterServerCallback('mdt:server:GetProfileData', function(source, cb, sentId)
	if not sentId then return cb({}) end

	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if not PermCheck(src, xPlayer) then return cb({}) end
	local JobType = GetJobType(xPlayer.job.name)
	local target = GetPlayerDataById(sentId)
	local JobName = xPlayer.job.name
	
	local apartmentData

	if not target or not next(target) then return cb({}) end

	local licencesdata = {
        ['driver'] = target.identifier and MySQL.scalar.await('SELECT COUNT(*) FROM user_licenses WHERE owner = ? AND type = ?', {target.identifier, 'drive'}) > 0 or false,
        ['business'] = false,
        ['weapon'] = target.identifier and MySQL.scalar.await('SELECT COUNT(*) FROM user_licenses WHERE owner = ? AND type = ?', {target.identifier, 'weapon'}) > 0 or false,
		['pilot'] = false
	}

	local job = {
		name = target.job or 'unemployed',
		label = target.job_label or 'Unemployed'
	}

	local grade = {
		name = target.job_grade_name or 'No Rank'
	}

	if Config.UsingESXProperty then
		local propertyData = GetPlayerPropertiesByCitizenId(target.identifier)
		if propertyData and next(propertyData) then
			local apartmentList = {}
			for i, property in ipairs(propertyData) do
				table.insert(apartmentList, property.property_name)
			end
			if #apartmentList > 0 then
				apartmentData = table.concat(apartmentList, ', ')
			else
				TriggerClientEvent("esx:showNotification", src, 'The citizen does not have a property.')
			end
		else
			TriggerClientEvent("esx:showNotification", src, 'The citizen does not have a property.')
		end	
    end

	local convictions = GetConvictions({target.identifier})
	for i=1, #convictions do
		convictions[i]['name'] = GetNameFromId(convictions[i]['cid'])
		convictions[i]['charges'] = json.decode(convictions[i]['charges'])
	end

	local vehicles = GetPlayerVehicles(target.identifier)
	for i=1, #vehicles do
		local vehData = {}
		if vehicles[i]['vehicle'] and vehicles[i]['vehicle'] ~= '' then
			vehData = ESX.GetVehicleLabel(vehicles[i]['vehicle']) or vehicles[i]['vehicle']
		end
		vehicles[i]['model'] = vehData
		vehicles[i]['class'] = Config.ClassList[GetVehicleClassFromName(vehicles[i]['vehicle'])] or 'Unknown'
	end

	local information = GetPersonInformation(target.identifier, JobType)
	local profilepic = information and information.pfp or "img/not-found.webp"

	local response = {
		identifier = target.identifier,
		information = information and information.information or {},
		tags = information and json.decode(information.tags or '[]') or {},
		gallery = information and json.decode(information.gallery or '[]') or {},
		fingerprint = information and information.fingerprint or '',
		profilepic = profilepic,
		lastname = target.lastname,
		firstname = target.firstname,
		callsign = target.callsign or '000',
		phone = target.phone_number,
		dateofbirth = target.dateofbirth,
		sex = target.sex,
		convictions = convictions,
		vehicles = vehicles,
		job = job,
		grade = grade,
		licences = licencesdata,
		apartment = apartmentData,
		policemdtaccess = information and information.policemdtaccess or false,
		emsmdtaccess = information and information.emsmdtaccess or false,
	}

	return cb(response)
end)

ESX.RegisterServerCallback('mdt:server:searchIncidents', function(source, cb, query)
	if query then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` WHERE LOWER(`title`) LIKE :query OR LOWER(`id`) LIKE :query ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..query..'%')
				})

				TriggerClientEvent('mdt:client:getIncidents', src, matches)
			end
		end
	end
end)

ESX.RegisterServerCallback('mdt:server:getAllIncidents', function(source, cb)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'doj' then
		local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` ORDER BY `id` DESC LIMIT 30")
		cb(matches)
	else
		cb({})
	end
end)

RegisterNetEvent('mdt:server:getIncidentData', function(sentId)
	if sentId then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` WHERE `id` = :id", {
					id = sentId
				})
				local data = matches[1]
				data['tags'] = json.decode(data['tags'])
				data['officersinvolved'] = json.decode(data['officersinvolved'])
				data['civsinvolved'] = json.decode(data['civsinvolved'])
				data['evidence'] = json.decode(data['evidence'])

				local convictions = MySQL.query.await("SELECT * FROM `mdt_convictions` WHERE `linkedincident` = :id", {
					id = sentId
				})
				if convictions ~= nil then
					for i=1, #convictions do
						local res = GetNameFromId(convictions[i]['cid'])
						if res ~= nil then
							convictions[i]['name'] = res
						else
							convictions[i]['name'] = "Unknown"
						end
						convictions[i]['charges'] = json.decode(convictions[i]['charges'])
					end
				end
				TriggerClientEvent('mdt:client:getIncidentData', src, data, convictions)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getAllBolos', function()
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE jobtype = :jobtype", {jobtype = JobType})
		TriggerClientEvent('mdt:client:getAllBolos', src, matches)
	end
end)

RegisterNetEvent('mdt:server:searchBolos', function(sentSearch)
	if sentSearch then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		local JobType = GetJobType(xPlayer.job.name)
		if JobType == 'police' or JobType == 'ambulance' then
			local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE `plate` LIKE :query OR `owner` LIKE :query OR `individual` LIKE :query AND jobtype = :jobtype ORDER BY `id` DESC LIMIT 25", {
				query = string.lower('%'..sentSearch..'%'),
				jobtype = JobType
			})
			TriggerClientEvent('mdt:client:getBolos', src, matches)
		end
	end
end)

RegisterNetEvent('mdt:server:getBoloData', function(sentId)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE `id` = :id AND jobtype = :jobtype", {
			id = sentId,
			jobtype = JobType
		})
		if matches[1] then
			matches[1]['tags'] = json.decode(matches[1]['tags'])
			matches[1]['officers'] = json.decode(matches[1]['officers'])
			matches[1]['gallery'] = json.decode(matches[1]['gallery'])
		end
		TriggerClientEvent('mdt:client:getBoloData', src, matches)
	end
end)

RegisterNetEvent('mdt:server:newBolo', function(existing, id, title, plate, owner, individual, detail, tags, gallery, officers, time)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if existing then
			local affectedRows = MySQL.update.await('UPDATE `mdt_bolos` SET `title` = ?, `plate` = ?, `owner` = ?, `individual` = ?, `detail` = ?, `tags` = ?, `gallery` = ?, `officers` = ?, `time` = ? WHERE `id` = ?', {
				title, plate, owner, individual, detail, json.encode(tags), json.encode(gallery), json.encode(officers), time, id
			})
			TriggerClientEvent('mdt:client:updateBolo', src, id)
			AddLog("BOLO with ID: "..id.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
		else
			local id = MySQL.insert.await('INSERT INTO `mdt_bolos` (`title`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officers`, `time`, `jobtype`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
				title, plate, owner, individual, detail, json.encode(tags), json.encode(gallery), json.encode(officers), time, JobType
			})
			TriggerClientEvent('mdt:client:updateBolo', src, id)
			AddLog("A new BOLO with ID: "..id.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
		end
	end
end)

RegisterNetEvent('mdt:server:deleteBolo', function(id)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		MySQL.query.await('DELETE FROM `mdt_bolos` WHERE `id` = ?', {id})
		AddLog("BOLO with ID: "..id.." was deleted by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:getAllBulletins', function()
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' or JobType == 'doj' then
		local matches = GetBulletins(JobType)
		TriggerClientEvent('mdt:client:getAllBulletins', src, matches)
	end
end)

RegisterNetEvent('mdt:server:newBulletin', function(title, info, time)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' or JobType == 'doj' then
		local fullname = xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName
		local id = MySQL.insert.await('INSERT INTO `mdt_bulletin` (`title`, `desc`, `author`, `time`, `jobtype`) VALUES (?, ?, ?, ?, ?)', {
			title, info, fullname, time, JobType
		})
		TriggerClientEvent('mdt:client:newBulletin', -1, {
			id = id,
			title = title,
			desc = info,
			author = fullname,
			time = time
		})
		AddLog("A new bulletin with title: "..title.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:deleteBulletin', function(id, title)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' or JobType == 'doj' then
		MySQL.query.await('DELETE FROM `mdt_bulletin` WHERE `id` = ?', {id})
		AddLog("Bulletin with Title: "..title.." was deleted by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

ESX.RegisterServerCallback('mdt:server:searchWeapons', function(source, cb, sentData)
	if sentData then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await('SELECT * FROM mdt_weaponinfo WHERE LOWER(`serial`) LIKE :query OR LOWER(`weapModel`) LIKE :query OR LOWER(`owner`) LIKE :query LIMIT 25', {
					query = string.lower('%'..sentData..'%')
				})
				cb(matches)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getWeaponData', function(serial)
	if serial then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local weapon = MySQL.query.await("SELECT * FROM `mdt_weaponinfo` WHERE `serial` = :serial", {
					serial = serial
				})
				TriggerClientEvent('mdt:client:getWeaponData', src, weapon)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:saveWeaponInfo', function(dbid, serial, imageurl, notes, owner, weapClass, weapModel)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		if dbid == 0 then
			local id = MySQL.insert.await('INSERT INTO `mdt_weaponinfo` (`serial`, `imageurl`, `notes`, `owner`, `weapClass`, `weapModel`) VALUES (?, ?, ?, ?, ?, ?)', {
				serial, imageurl, notes, owner, weapClass, weapModel
			})
			TriggerClientEvent('mdt:client:updateWeaponDbId', src, id)
			AddLog("A new weapon with serial: "..serial.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
		else
			local affectedRows = MySQL.update.await('UPDATE `mdt_weaponinfo` SET `imageurl` = ?, `notes` = ?, `owner` = ?, `weapClass` = ?, `weapModel` = ? WHERE `serial` = ?', {
				imageurl, notes, owner, weapClass, weapModel, serial
			})
			AddLog("Weapon with serial: "..serial.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
		end
	end
end)

RegisterNetEvent('mdt:server:getAllLogs', function()
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if xPlayer then
		if Config.LogPerms[xPlayer.job.name] then
			if Config.LogPerms[xPlayer.job.name][xPlayer.job.grade] then
				local JobType = GetJobType(xPlayer.job.name)
				local infoResult = MySQL.query.await('SELECT * FROM mdt_logs WHERE `jobtype` = :jobtype ORDER BY `id` DESC LIMIT 250', {jobtype = JobType})
				TriggerLatentClientEvent('mdt:client:getAllLogs', src, 30000, infoResult)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getPenalCode', function()
	local src = source
	TriggerClientEvent('mdt:client:getPenalCode', src, Config.PenalCodeTitles, Config.PenalCode)
end)

RegisterNetEvent('mdt:server:setCallsign', function(identifier, newcallsign)
	local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
	if targetPlayer then
		targetPlayer.setMeta("callsign", newcallsign)
	end
end)

RegisterNetEvent('mdt:server:saveIncident', function(id, title, information, tags, officers, civilians, evidence, associated, time)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        if GetJobType(xPlayer.job.name) == 'police' then
            if id == 0 then
                local fullname = xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName
                local id = MySQL.insert.await('INSERT INTO `mdt_incidents` (`title`, `information`, `tags`, `officersinvolved`, `civsinvolved`, `evidence`, `time`, `author`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                    title, information, json.encode(tags), json.encode(officers), json.encode(civilians), json.encode(evidence), time, fullname
                })
                TriggerClientEvent('mdt:client:updateIncidentDbId', src, id)
                AddLog("A new incident with ID: "..id.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
            else
                local affectedRows = MySQL.update.await('UPDATE `mdt_incidents` SET `title` = ?, `information` = ?, `tags` = ?, `officersinvolved` = ?, `civsinvolved` = ?, `evidence` = ? WHERE `id` = ?', {
                    title, information, json.encode(tags), json.encode(officers), json.encode(civilians), json.encode(evidence), id
                })
                AddLog("Incident with ID: "..id.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
            end
        end
    end
end)

RegisterNetEvent('mdt:server:deleteIncident', function(id)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		MySQL.query.await('DELETE FROM `mdt_incidents` WHERE `id` = ?', {id})
		AddLog("Incident with ID: "..id.." was deleted by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:incidentSearchPerson', function(identifier)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local matches = MySQL.query.await("SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number FROM `users` WHERE identifier = :query LIMIT 1", {
			query = identifier
		})
		TriggerClientEvent('mdt:client:incidentSearchPerson', src, matches)
	end
end)

RegisterNetEvent('mdt:server:removeIncidentCriminal', function(id, identifier)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local data = MySQL.single.await('SELECT * FROM `mdt_incidents` WHERE `id` = :id', { id = id })
		if data then
			local civsinvolved = json.decode(data['civsinvolved'])
			for k, v in pairs(civsinvolved) do
				if v['cid'] == identifier then
					table.remove(civsinvolved, k)
					break
				end
			end
			MySQL.update.await('UPDATE `mdt_incidents` SET `civsinvolved` = ? WHERE `id` = ?', {
				json.encode(civsinvolved), id
			})
		end
	end
end)

RegisterNetEvent('mdt:server:saveProfile', function(pfp, information, tags, gallery, identifier, fingerprint, fName, sName, jobType)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' or GetJobType(xPlayer.job.name) == 'ambulance' or GetJobType(xPlayer.job.name) == 'doj' then
		local existing = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_data WHERE cid = ? AND jobtype = ?', { identifier, jobType })
		if existing and existing > 0 then
			MySQL.update.await('UPDATE mdt_data SET information = ?, tags = ?, gallery = ?, pfp = ?, fingerprint = ? WHERE cid = ? AND jobtype = ?', {
				information, json.encode(tags), json.encode(gallery), pfp, fingerprint, identifier, jobType
			})
		else
			CreateUser(identifier, 'mdt_data')
			MySQL.update.await('UPDATE mdt_data SET information = ?, tags = ?, gallery = ?, pfp = ?, fingerprint = ?, jobtype = ? WHERE cid = ?', {
				information, json.encode(tags), json.encode(gallery), pfp, fingerprint, jobType, identifier
			})
		end
		AddLog("Profile for "..fName.." "..sName.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:saveConviction', function(identifier, linkedincident, charges, fine, sentence, recfine, recsentence, time)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local id = MySQL.insert.await('INSERT INTO `mdt_convictions` (`cid`, `linkedincident`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
			identifier, linkedincident, json.encode(charges), fine, sentence, recfine, recsentence, time
		})
		local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
		
		if Config.BillVariation == true then
			if targetPlayer then
				if Config.ESXBankingUse then
					-- ESX Society system
					TriggerEvent('esx_addonaccount:getSharedAccount', 'society_police', function(account)
						targetPlayer.removeAccountMoney('bank', fine)
						account.addMoney(fine)
					end)
				else
					targetPlayer.removeAccountMoney('bank', fine)
				end
				TriggerClientEvent('esx:showNotification', targetPlayer.source, 'You have been charged with a fine of $'..fine..'.')
			end
		else
			-- Send bill instead
			if targetPlayer then
				TriggerEvent('esx_billing:sendBill', targetPlayer.source, 'society_police', 'Police Fine', fine)
			end
		end
		
		TriggerClientEvent('mdt:client:updateConvictionDbId', src, id)
		AddLog("A new conviction with ID: "..id.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:deleteConviction', function(id)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		MySQL.query.await('DELETE FROM `mdt_convictions` WHERE `id` = ?', {id})
		AddLog("Conviction with ID: "..id.." was deleted by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

RegisterNetEvent('mdt:server:setCuffState', function(identifier, boolean)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
		if targetPlayer then
			TriggerClientEvent('police:client:SetCuffState', targetPlayer.source, boolean)
		end
	end
end)

RegisterNetEvent('mdt:server:jailPlayer', function(identifier, time)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
		if targetPlayer then
			TriggerEvent('esx_jailer:sendToJail', targetPlayer.source, time)
		end
	end
end)

RegisterNetEvent('mdt:server:registerweapon', function(serial, imageurl, notes, owner, weapClass, weapModel)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		local id = MySQL.insert.await('INSERT INTO `mdt_weaponinfo` (`serial`, `imageurl`, `notes`, `owner`, `weapClass`, `weapModel`) VALUES (?, ?, ?, ?, ?, ?)', {
			serial, imageurl, notes, owner, weapClass, weapModel
		})
		TriggerClientEvent('mdt:client:updateWeaponDbId', src, id)
		AddLog("A new weapon with serial: "..serial.." was registered by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

-- Reports System
ESX.RegisterServerCallback('mdt:server:getAllReports', function(source, cb)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'doj' then
		local matches = MySQL.query.await("SELECT * FROM `mdt_reports` ORDER BY `id` DESC LIMIT 30")
		cb(matches)
	else
		cb({})
	end
end)

ESX.RegisterServerCallback('mdt:server:searchReports', function(source, cb, query)
	if query then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_reports` WHERE LOWER(`title`) LIKE :query OR LOWER(`id`) LIKE :query ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..query..'%')
				})
				cb(matches)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getReportData', function(sentId)
	if sentId then
		local src = source
		local xPlayer = ESX.GetPlayerFromId(src)
		if xPlayer then
			local JobType = GetJobType(xPlayer.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_reports` WHERE `id` = :id", {
					id = sentId
				})
				local data = matches[1]
				if data then
					data['tags'] = json.decode(data['tags'])
					data['officersinvolved'] = json.decode(data['officersinvolved'])
					data['civsinvolved'] = json.decode(data['civsinvolved'])
					data['gallery'] = json.decode(data['gallery'])
				end
				TriggerClientEvent('mdt:client:getReportData', src, data)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:newReport', function(existing, id, title, reporttype, details, tags, gallery, officers, civilians, time)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'ambulance' or JobType == 'doj' then
		if existing then
			local affectedRows = MySQL.update.await('UPDATE `mdt_reports` SET `title` = ?, `type` = ?, `details` = ?, `tags` = ?, `gallery` = ?, `officers` = ?, `civilians` = ?, `time` = ? WHERE `id` = ?', {
				title, reporttype, details, json.encode(tags), json.encode(gallery), json.encode(officers), json.encode(civilians), time, id
			})
			TriggerClientEvent('mdt:client:updateReportId', src, id)
			AddLog("Report with ID: "..id.." was updated by " .. GetNameFromPlayerData(xPlayer) .. ".")
		else
			local fullname = xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName
			local id = MySQL.insert.await('INSERT INTO `mdt_reports` (`title`, `type`, `details`, `tags`, `gallery`, `officers`, `civilians`, `time`, `author`, `jobtype`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
				title, reporttype, details, json.encode(tags), json.encode(gallery), json.encode(officers), json.encode(civilians), time, fullname, JobType
			})
			TriggerClientEvent('mdt:client:updateReportId', src, id)
			AddLog("A new report with ID: "..id.." was created by " .. GetNameFromPlayerData(xPlayer) .. ".")
		end
	end
end)

RegisterNetEvent('mdt:server:deleteReport', function(id)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local JobType = GetJobType(xPlayer.job.name)
	if JobType == 'police' or JobType == 'doj' then
		MySQL.query.await('DELETE FROM `mdt_reports` WHERE `id` = ?', {id})
		AddLog("Report with ID: "..id.." was deleted by " .. GetNameFromPlayerData(xPlayer) .. ".")
	end
end)

-- Impound System
local function isRequestVehicle(vehId)
	local found = false
	for i=1, #impound do
		if impound[i]['vehicle'] == vehId then
			found = true
			impound[i] = nil
			break
		end
	end
	return found
end
exports('isRequestVehicle', isRequestVehicle)

local function giveCitationItem(src, identifier, fine, incidentId)
    local targetPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if not targetPlayer then return end
    
    local PlayerName = targetPlayer.variables.firstName .. ' ' .. targetPlayer.variables.lastName
    local Officer = ESX.GetPlayerFromId(src)
    local callsign = Officer.getMeta('callsign') or '000'
    local OfficerFullName = '(' .. callsign .. ') ' .. Officer.variables.firstName .. ' ' .. Officer.variables.lastName
    
    local info = {
        identifier = identifier,
        fine = "$"..fine,
        date = os.date("%Y-%m-%d %H:%M"),
        incidentId = "#"..incidentId,
        officer = OfficerFullName,
    }
    
    targetPlayer.addInventoryItem('mdtcitation', 1, false, info)
    TriggerClientEvent('esx:showNotification', src, PlayerName.." (" ..identifier.. ") received a citation!")
end

RegisterNetEvent('mdt:server:impoundVehicle', function(sentInfo, sentVehicle)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if xPlayer then
		if GetJobType(xPlayer.job.name) == 'police' then
			if sentInfo and type(sentInfo) == 'table' then
				local plate, linkedreport, fee, time = sentInfo['plate'], sentInfo['linkedreport'], sentInfo['fee'], sentInfo['time']
				if (plate and linkedreport and fee and time) then
				local vehicle = MySQL.query.await("SELECT plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") })
					if vehicle and vehicle[1] then
						local data = vehicle[1]
						MySQL.insert('INSERT INTO `mdt_impound` (`plate`, `linkedreport`, `fee`, `time`) VALUES (:plate, :linkedreport, :fee, :time)', {
							plate = data['plate'],
							linkedreport = linkedreport,
							fee = fee,
							time = os.time() + (time * 60)
						}, function(res)
							local data = {
								plate = plate,
								beingcollected = 0,
								vehicle = sentVehicle,
								officer = xPlayer.variables.firstName.. " "..xPlayer.variables.lastName,
								number = xPlayer.variables.phone_number,
								time = os.time() * 1000,
								src = src,
							}
							local vehicle = NetworkGetEntityFromNetworkId(sentVehicle)
							FreezeEntityPosition(vehicle, true)
							impound[#impound+1] = data

							TriggerClientEvent("police:client:ImpoundVehicle", src, true, fee)
						end)
					end
				end
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getImpoundVehicles', function()
	TriggerClientEvent('mdt:client:getImpoundVehicles', source, impound)
end)

RegisterNetEvent('mdt:server:removeImpound', function(plate, currentSelection)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if xPlayer then
		if GetJobType(xPlayer.job.name) == 'police' then
			local result = MySQL.single.await("SELECT plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")})
			if result then
				local data = result
				MySQL.update("DELETE FROM `mdt_impound` WHERE plate=:plate", { plate = data['plate'] })
				TriggerClientEvent('police:client:TakeOutImpound', src, currentSelection, plate)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:statusImpound', function(plate)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if xPlayer then
		if GetJobType(xPlayer.job.name) == 'police' then
			local vehicle = MySQL.query.await("SELECT plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")})
			if vehicle and vehicle[1] then
				local data = vehicle[1]
				local impoundinfo = MySQL.query.await("SELECT * FROM `mdt_impound` WHERE plate=:plate LIMIT 1", { plate = data['plate'] })
				if impoundinfo and impoundinfo[1] then
					TriggerClientEvent('mdt:client:statusImpound', src, impoundinfo[1], plate)
				end
			end
		end
	end
end)

RegisterServerEvent("mdt:server:AddLog", function(text)
	AddLog(text)
end)

-- Active Units Management
RegisterNetEvent('mdt:server:toggleActiveUnit', function(identifier, firstname, lastname, callsign, job, grade, department)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if IsPoliceOrEms(xPlayer.job.name) then
		if not GetActiveData(identifier) then
			activeUnits[identifier] = {
				identifier = identifier,
				firstname = firstname,
				lastname = lastname,
				callsign = callsign,
				job = job,
				grade = grade,
				department = department,
				src = src
			}
		else
			activeUnits[identifier] = nil
		end
		TriggerClientEvent('mdt:client:activeUnitsUpdate', -1, activeUnits)
	end
end)

-- Mugshots
ESX.RegisterServerCallback('mdt:server:GetMugShots', function(source, cb, identifier)
	cb(MugShots[identifier] or {})
end)

RegisterNetEvent('mdt:server:mugshot', function(identifier, data)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	if GetJobType(xPlayer.job.name) == 'police' then
		if not MugShots[identifier] then
			MugShots[identifier] = {}
		end
		MugShots[identifier][#MugShots[identifier]+1] = {
			image = data,
			time = os.time() * 1000,
			author = xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName
		}
		TriggerClientEvent('mdt:client:updateMugshots', src, MugShots[identifier])
	end
end)

-- Exports
exports('CreateWeaponInfo', function(serial, imageurl, notes, owner, weapClass, weapModel)
    MySQL.insert.await('INSERT INTO `mdt_weaponinfo` (`serial`, `imageurl`, `notes`, `owner`, `weapClass`, `weapModel`) VALUES (?, ?, ?, ?, ?, ?)', {
        serial, imageurl, notes, owner, weapClass, weapModel
    })
end)

exports('IsCidFelon', function(identifier, cb)
	if identifier then
		local convictions = MySQL.query.await('SELECT charges FROM mdt_convictions WHERE cid=:cid', { cid = identifier })
		local Charges = {}
		for i=1, #convictions do
			local currCharges = json.decode(convictions[i]['charges'])
			for x=1, #currCharges do
				Charges[#Charges+1] = currCharges[x]
			end
		end
		local PenalCode = Config.PenalCode
		for i=1, #Charges do
			for p=1, #PenalCode do
				for x=1, #PenalCode[p] do
					if PenalCode[p][x]['title'] == Charges[i] then
						if PenalCode[p][x]['class'] == 'Felony' then
							cb(true)
							return
						end
						break
					end
				end
			end
		end
		cb(false)
	end
end)