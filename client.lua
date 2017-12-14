--------------------------------
--	iEnsomatic Sunday Driver  --
--------------------------------
--
--	Created by Jens Sandalgaard
--
--	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--
--	https://github.com/iEns/SundayDriver
--


local pedInSameVehicleLast=false
local vehicle
local lastVehicle
local vehicleClass
local fBrakeForce = 1.0
local isBrakingForward = false
local isBrakingReverse = false



local function notification(msg)
	SetNotificationTextEntry("STRING")
	AddTextComponentString(msg)
	DrawNotification(false, false)
end



local function isPedDrivingAVehicle()
	local ped = GetPlayerPed(-1)
	vehicle = GetVehiclePedIsIn(ped, false)
	if IsPedInAnyVehicle(ped, false) then
		-- Check if ped is in driver seat
		if GetPedInVehicleSeat(vehicle, -1) == ped then
			local class = GetVehicleClass(vehicle)
			-- We don't want planes, helicopters, bicycles and trains
			if class ~= 15 and class ~= 16 and class ~=21 and class ~=13 and class ~=14 then
				return true
			end
		end
	end
	return false
end



local function fscale(inputValue, originalMin, originalMax, newBegin, newEnd, curve)
	local OriginalRange = 0.0
	local NewRange = 0.0
	local zeroRefCurVal = 0.0
	local normalizedCurVal = 0.0
	local rangedValue = 0.0
	local invFlag = 0

	if (curve > 10.0) then curve = 10.0 end
	if (curve < -10.0) then curve = -10.0 end

	curve = (curve * -.1)
	curve = 10.0 ^ curve

	if (inputValue < originalMin) then
	  inputValue = originalMin
	end
	if inputValue > originalMax then
	  inputValue = originalMax
	end

	OriginalRange = originalMax - originalMin

	if (newEnd > newBegin) then
		NewRange = newEnd - newBegin
	else
	  NewRange = newBegin - newEnd
	  invFlag = 1
	end

	zeroRefCurVal = inputValue - originalMin
	normalizedCurVal  =  zeroRefCurVal / OriginalRange

	if (originalMin > originalMax ) then
	  return 0
	end

	if (invFlag == 0) then
		rangedValue =  ((normalizedCurVal ^ curve) * NewRange) + newBegin
	else
		rangedValue =  newBegin - ((normalizedCurVal ^ curve) * NewRange)
	end

	return rangedValue
end



local function smoothDriving()
	if pedInSameVehicleLast then
		local torqueFactor = 1.0
		local accelerator = GetControlValue(2,71)
		local brake = GetControlValue(2,72)
		local speedVector = GetEntitySpeedVector(vehicle, true)['y']
		local brk = fBrakeForce
		if speedVector >= 1.0 then
			-- Going forward
			if accelerator > 127 then
				-- Forward and accelerating
				local acc = fscale(accelerator, 127.0, 254.0, 0.1, 1.0, 10.0-(cfg.smoothAcceleratorCurve*2.0))
				torqueFactor = torqueFactor * acc
			end
			if brake > 127 then
				-- Forward and braking
				isBrakingForward = true
				brk = fscale(brake, 127.0, 254.0, 0.01, fBrakeForce, 10.0-(cfg.smoothBrakeCurve*2.0))
			end
		elseif speedVector <= -1.0 then
			-- Going reverse
			if brake > 127 then
				-- Reversing and accelerating (using the brake)
				local rev = fscale(brake, 127.0, 254.0, 0.1, 1.0, 10.0-(cfg.smoothAcceleratorCurve*2.0))
				torqueFactor = torqueFactor * rev
			end
			if accelerator > 127 then
				-- Reversing and braking (Using the accelerator)
				isBrakingReverse = true
				brk = fscale(accelerator, 127.0, 254.0, 0.01, fBrakeForce, 10.0-(cfg.smoothBrakeCurve*2.0))
			end
		else
			-- Stopped or almost stopped or sliding sideways
			local entitySpeed = GetEntitySpeed(vehicle)
			if cfg.stopWithoutReversing == true and entitySpeed < 1 then
				-- Not sliding sideways
				if isBrakingForward == true then
					--Stopped or going slightly forward while braking
					DisableControlAction(2,72,true) -- Disable Brake until user lets go of brake
					SetVehicleForwardSpeed(vehicle, speedVector*0.98)
					SetVehicleBrakeLights(vehicle,true)
				end
				if isBrakingReverse == true then
					--Stopped or going slightly in reverse while braking
					DisableControlAction(2,71,true) -- Disable reverse Brake until user lets go of reverse brake (Accelerator)
					SetVehicleForwardSpeed(vehicle, speedVector*0.98)
					SetVehicleBrakeLights(vehicle,true)
				end
				if isBrakingForward == true and GetDisabledControlNormal(2,72) == 0 then
					-- We let go of the brake
					isBrakingForward=false
				end
				if isBrakingReverse == true and GetDisabledControlNormal(2,71) == 0 then
					-- We let go of the reverse brake (Accelerator)
					isBrakingReverse=false
				end
			end
		end
		if brk > fBrakeForce - 0.02 then brk = fBrakeForce end -- Make sure we can brake max.
		SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fBrakeForce', brk)  -- Set new Brake Force multiplier
		SetVehicleEngineTorqueMultiplier(vehicle, torqueFactor)
	end
end


-- Functions called each frame
Citizen.CreateThread(function()
	while true do
		Citizen.Wait(0)
		if cfg.smoothDriving then smoothDriving() end
	end
end)

-- Functions called 20 times a second
Citizen.CreateThread(function()
	while true do
		Citizen.Wait(50)
		local ped = GetPlayerPed(-1)
		if isPedDrivingAVehicle() then
			vehicle = GetVehiclePedIsIn(ped, false)
			vehicleClass = GetVehicleClass(vehicle)
			-- If ped spawned a new vehicle while in a vehicle or teleported from one vehicle to another, handle as if we just entered the car
			if vehicle ~= lastVehicle then
				pedInSameVehicleLast = false
			end

			if pedInSameVehicleLast == false then
				-- Just got in the vehicle. Damage can not be multiplied this round
				-- Set vehicle handling data
				fBrakeForce = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fBrakeForce')
				pedInSameVehicleLast = true
			end

			lastVehicle=vehicle
		else
			if pedInSameVehicleLast == true then
				-- We just got out of the vehicle
				lastVehicle = GetVehiclePedIsIn(ped, true)
				SetVehicleHandlingFloat(lastVehicle, 'CHandlingData', 'fBrakeForce', fBrakeForce)  -- Restore Brake Force multiplier
			end
			pedInSameVehicleLast = false
		end
	end
end)

