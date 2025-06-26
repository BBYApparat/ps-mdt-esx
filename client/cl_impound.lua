-- ESX VERSION - client/cl_impound.lua
ESX = exports["es_extended"]:getSharedObject()
local currentGarage = 1

local function doCarDamage(currentVehicle, veh)
	local smash = false
	local damageOutside = false
	local damageOutside2 = false
	local engine = veh.engine + 0.0
	local body = veh.body + 0.0

	if engine < 200.0 then engine = 200.0 end
    if engine  > 1000.0 then engine = 950.0 end
	if body < 150.0 then body = 150.0 end
	if body < 950.0 then smash = true end
	if body < 920.0 then damageOutside = true end
	if body < 920.0 then damageOutside2 = true end

    Citizen.Wait(100)
    SetVehicleEngineHealth(currentVehicle, engine)

	if smash then
		SmashVehicleWindow(currentVehicle, 0)
		SmashVehicleWindow(currentVehicle, 1)
		SmashVehicleWindow(currentVehicle, 2)
		SmashVehicleWindow(currentVehicle, 3)
		SmashVehicleWindow(currentVehicle, 4)
	end

	if damageOutside then
		SetVehicleDoorBroken(currentVehicle, 1, true)
		SetVehicleDoorBroken(currentVehicle, 6, true)
		SetVehicleDoorBroken(currentVehicle, 4, true)
	end

	if damageOutside2 then
		SetVehicleTyreBurst(currentVehicle, 1, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 2, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 3, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 4, false, 990.0)
	end

	if body < 1000 then
		SetVehicleBodyHealth(currentVehicle, 985.1)
	end
end

local function TakeOutImpound(vehicle)
    local coords = Config.ImpoundLocations[currentGarage]
    if coords then
        -- ESX vehicle spawning system
        ESX.Game.SpawnVehicle(vehicle.vehicle, coords, coords.w, function(veh)
            -- Get vehicle properties for ESX
            ESX.TriggerServerCallback('esx_vehicleshop:getVehicleProperties', function(properties)
                if properties then
                    ESX.Game.SetVehicleProperties(veh, properties)
                end
                
                SetVehicleNumberPlateText(veh, vehicle.plate)
                SetEntityHeading(veh, coords.w)
                
                -- Set fuel based on your fuel system
                if GetResourceState(Config.Fuel) == 'started' then
                    exports[Config.Fuel]:SetFuel(veh, vehicle.fuel or 100)
                end
                
                doCarDamage(veh, vehicle)
                TriggerServerEvent('police:server:TakeOutImpound', vehicle.plate)
                
                -- ESX vehicle keys system (adjust based on your key system)
                if GetResourceState('esx_vehiclelock') == 'started' then
                    TriggerEvent('esx_vehiclelock:giveKey', veh)
                elseif GetResourceState('wasabi_carlock') == 'started' then
                    exports.wasabi_carlock:GiveKey(GetVehicleNumberPlateText(veh))
                elseif GetResourceState('cd_garage') == 'started' then
                    TriggerEvent('cd_garage:AddKeys', exports['cd_garage']:GetPlate(veh))
                end
                
                SetVehicleEngineOn(veh, true, true)
            end, vehicle.plate)
        end)
    end
end

RegisterNetEvent('ps-mdt:client:TakeOutImpound', function(data)
    local pos = GetEntityCoords(PlayerPedId())
    currentGarage = data.currentSelection
    local takeDist = Config.ImpoundLocations[data.currentSelection]
    takeDist = vector3(takeDist.x, takeDist.y, takeDist.z)
    if #(pos - takeDist) <= 15.0 then
        TakeOutImpound(data)
    else
        ESX.ShowNotification("You are too far away from the impound location!")
    end
end)

RegisterNetEvent('mdt:client:getImpoundVehicles', function(vehicles)
    SendNUIMessage({
        type = "getImpoundVehicles",
        data = vehicles
    })
end)

RegisterNetEvent('mdt:client:statusImpound', function(data, plate)
    SendNUIMessage({
        type = "statusImpound", 
        data = data,
        plate = plate
    })
end)

-- ESX specific impound handling
RegisterNetEvent('mdt:client:impoundVehicle', function(data)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local vehicle = GetClosestVehicle(coords, 5.0, 0, 71)
    
    if vehicle ~= 0 then
        local plate = GetVehicleNumberPlateText(vehicle)
        TriggerServerEvent('mdt:server:impoundVehicle', data, VehToNet(vehicle))
    else
        ESX.ShowNotification("No vehicle found nearby!")
    end
end)