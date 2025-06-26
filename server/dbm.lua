-- ESX VERSION - server/dbm.lua
ESX = exports["es_extended"]:getSharedObject()

-- Get CitizenIDs from Player License
function GetCitizenID(license)
    local result = MySQL.query.await("SELECT identifier FROM users WHERE license = ?", {license,})
    if result ~= nil then
        return result
    else
        print("Cannot find an identifier for License: "..license)
        return nil
    end
end

-- (Start) Opening the MDT and sending data
function AddLog(text)
    return MySQL.insert.await('INSERT INTO `mdt_logs` (`text`, `time`) VALUES (?,?)', {text, os.time() * 1000})
end

function GetNameFromId(identifier)
	local result = MySQL.scalar.await('SELECT CONCAT(firstname, " ", lastname) as fullname FROM users WHERE identifier = @identifier', { ['@identifier'] = identifier })
    if result ~= nil then
        return result
    else
        --print('Player does not exist')
        return nil
    end
end

function GetPersonInformation(identifier, jobtype)
    local result = MySQL.query.await('SELECT information, tags, gallery, pfp, fingerprint FROM mdt_data WHERE cid = ? and jobtype = ?', { identifier,  jobtype})
    return result[1]
end

function GetIncidentName(id)
	local result = MySQL.query.await('SELECT title FROM `mdt_incidents` WHERE id = :id LIMIT 1', { id = id })
    return result[1]
end

function GetConvictions(identifiers)
	return MySQL.query.await('SELECT * FROM `mdt_convictions` WHERE `cid` IN(?)', { identifiers })
end

function GetLicenseInfo(identifier)
	local result = MySQL.query.await('SELECT * FROM `user_licenses` WHERE `owner` = ?', { identifier })
	return result
end

function CreateUser(identifier, tableName)
	AddLog("A user was created with the identifier: "..identifier)
	return MySQL.insert.await("INSERT INTO `"..tableName.."` (cid) VALUES (:cid)", { cid = identifier })
end

function GetPlayerVehicles(identifier, cb)
	return MySQL.query.await('SELECT plate, vehicle FROM owned_vehicles WHERE owner=:identifier', { identifier = identifier })
end

function GetBulletins(JobType)
	return MySQL.query.await('SELECT * FROM `mdt_bulletin` WHERE `jobtype` = ? LIMIT 10', { JobType })
end

function GetPlayerProperties(identifier, cb)
	-- ESX property system varies, adjust based on your property system
	local result =  MySQL.query.await('SELECT property_name, coords FROM owned_properties WHERE owner = ?', {identifier})
	return result
end

function GetPlayerDataById(id)
    local xPlayer = ESX.GetPlayerFromIdentifier(id)
    if xPlayer ~= nil then
		local response = {
			identifier = xPlayer.identifier, 
			firstname = xPlayer.variables.firstName,
			lastname = xPlayer.variables.lastName,
			dateofbirth = xPlayer.variables.dateofbirth,
			sex = xPlayer.variables.sex,
			job = xPlayer.job,
			metadata = {
				callsign = xPlayer.getMeta('callsign') or '000',
				licences = {
					driver = xPlayer.getInventoryItem('driverslicense') and true or false,
					weapon = xPlayer.getInventoryItem('weaponlicense') and true or false,
				}
			}
		}
        return response
    else
        return MySQL.single.await('SELECT identifier, firstname, lastname, dateofbirth, sex, job, job_grade FROM users WHERE identifier = ?', {id})
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

function GetVehicleInformation(plate)
	local result = MySQL.single.await('SELECT code5, stolen, image FROM mdt_vehicleinfo WHERE plate = ?', { plate })
	return result
end

function GetBoloStatus(plate)
	local result = MySQL.single.await('SELECT id, title FROM mdt_bolos WHERE plate = ? AND type = "vehicle"', { plate })
	if result then
		return true, result.title, result.id
	end
	return false, nil, nil
end

function GetWarrantStatus(plate)
	local owner = MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE plate = ?', { plate })
	if owner then
		local warrant = MySQL.single.await('SELECT * FROM mdt_incidents WHERE FIND_IN_SET(?, JSON_EXTRACT(civsinvolved, "$[*].cid")) > 0 AND warrant = 1', { owner })
		if warrant then
			local ownerName = MySQL.scalar.await('SELECT CONCAT(firstname, " ", lastname) as fullname FROM users WHERE identifier = ?', { owner })
			return true, ownerName, warrant.id
		end
	end
	return false, nil, nil
end

function GetPlayerPropertiesByCitizenId(identifier)
	-- Adjust based on your ESX property system
	return MySQL.query.await('SELECT property_name FROM owned_properties WHERE owner = ?', { identifier })
end

function GetPlayerApartment(identifier)
	-- ESX doesn't have default apartments like QB, adjust for your system
	return nil
end