-- ESX VERSION - server/utils.lua
ESX = exports["es_extended"]:getSharedObject()

function GetPlayerData(source)
	local xPlayer = ESX.GetPlayerFromId(source)
	if xPlayer == nil then return end -- Player not loaded in correctly
	return xPlayer
end

function UnpackJob(data)
	local job = {
		name = data.name,
		label = data.label
	}
	local grade = {
		name = data.grade_name,
	}

	return job, grade
end

function PermCheck(src, xPlayer)
	local result = true

	if not Config.AllowedJobs[xPlayer.job.name] then
		print(("UserId: %s(%d) tried to access the mdt even though they are not authorised (server direct)"):format(GetPlayerName(src), src))
		result = false
	end

	return result
end

function ProfPic(gender, profilepic)
	if profilepic then return profilepic end;
	if gender == "f" then return "img/female.png" end;
	return "img/male.png"
end

function IsJobAllowedToMDT(job)
	if Config.PoliceJobs[job] then
		return true
	elseif Config.AmbulanceJobs[job] then
		return true
	elseif Config.DojJobs[job] then
		return true
	else
		return false
	end
end

function GetNameFromPlayerData(xPlayer)
	return ('%s %s'):format(xPlayer.variables.firstName, xPlayer.variables.lastName)
end

-- ESX specific helper functions
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