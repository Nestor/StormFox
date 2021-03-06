
--[[-------------------------------------------------------------------------
	Time functions
		StormFox.GetTimeSpeed()
		StormFox.GetTime(pure)	Gets the current time. Pure returns the "whole" number
		StormFox.SetTime(var)	Sets the time (Serverside only ofc)
		StormFox.GetRealTime()	Gets the time in a string-format
		StormFox.GetDaylightAmount(num) Returns the day/night amount from 1-0
 ---------------------------------------------------------------------------]]
local mmin,clamp = math.min,math.Clamp
local BASE_TIME = CurTime() -- The base time we will use to calculate current time with.
local TIME_SPEED = ( GetConVar("sf_timespeed") and GetConVar("sf_timespeed"):GetFloat() or 1 ) or 1

-- Local functions
local function StringToTime( str )
	if !str then return 0 end
	local a = string.Explode( ":", str )
	if #a < 2 then return 0 end
	local h,m = string.match(a[1],"%d+"),string.match(a[2],"%d+")
	local ex = string.match(a[2]:lower(),"[ampm]+")
	if not h or not m then return end
		h,m = tonumber(h),tonumber(m)
	if ex then
		-- 12clock to 24clock
		if ex == "am" and h == 12 then
			h = h - 12
		end
		if h < 12 and ex == "pm" then
			h = h + 12
		end
	end
	return ( h * 60 + m ) % 1440
end

if SERVER then
	util.AddNetworkString( "StormFox_SetTimeData" )

	-- Network the current time and time speed to the client so they can calculate a syncronized time value
	hook.Add( "PlayerInitialSpawn", "StormFox_SendInitialTimeData", function( pPlayer )
		net.Start( "StormFox_SetTimeData" )
			net.WriteFloat( StormFox.GetTime() )
			net.WriteFloat( TIME_SPEED )
		net.Send( pPlayer )
	end )

	-- Update all the currently connected clients with the new time speed
	local function updateClientsTimeVars()
		net.Start( "StormFox_SetTimeData" )
			net.WriteFloat( StormFox.GetTime() )
			net.WriteFloat( TIME_SPEED )
		net.Broadcast()
	end

	-- Update our local TIME_SPEED variable if the convar is changed
	cvars.AddChangeCallback( "sf_timespeed", function( sConvarName, sOldValue, sNewValue )
		local flNewValue = tonumber( sNewValue ) or 1
		local flOldTime = StormFox.GetTime()
		if flNewValue > 66 then
			MsgN( "[StormFox] WARNING: Timespeed was set to higer than 66.0. Reverting to a value of 66.0.")
			GetConVar( "sf_timespeed" ):SetFloat( 66.0 )
			TIME_SPEED = 66
		elseif flNewValue > 0 and flNewValue < 0.001 then
			MsgN( "[StormFox] WARNING: Timespeed can't be between 0 and 0.001. Reverting to the value of 0.001.")
			GetConVar( "sf_timespeed" ):SetFloat( 0.001 )
			TIME_SPEED = 0.001
		elseif flNewValue <= 0 then
			if flNewValue < 0 then
				MsgN( "[StormFox] WARNING: Timespeed can't go below 0. Pausing the time.")
			else
				MsgN( "[StormFox] Pausing time.")
			end
			GetConVar( "sf_timespeed" ):SetFloat( 0 )
			TIME_SPEED = 0
		else
			MsgN( "[StormFox] Timespeed changed to: " .. flNewValue )
			TIME_SPEED = flNewValue
		end
		if TIME_SPEED <= 0 then
			timer.Pause("StormFox-tick")
			BASE_TIME = flOldTime
		else
			BASE_TIME = CurTime() - ( flOldTime / TIME_SPEED )
			if tonumber(sOldValue) <= 0 then
				timer.UnPause("StormFox-tick")
			end
			timer.Adjust( "StormFox-tick", 1 / TIME_SPEED,0)
		end
		updateClientsTimeVars() -- Update the vars
	end, "StormFox_TimeSpeedChanged" )

	-- Used to update the current stormfox time
	function StormFox.SetTime( var )
		if not var then return false end
		local flNewTime = nil
		if type( var ) == "string" then
			flNewTime = StringToTime( var )
		elseif type( var ) == "number" then
			flNewTime = var
		else
			return false
		end
		if type(flNewTime) == "nil" then
			return false
		end
		if TIME_SPEED <= 0 then
			BASE_TIME = flNewTime
		else
			BASE_TIME = CurTime() - ( flNewTime / TIME_SPEED )
		end
		hook.Call( "StormFox - Timechange", nil, flNewTime )
		hook.Call( "StormFox - Timeset")
		updateClientsTimeVars()

		return flNewTime
	end
	timer.Simple(1,updateClientsTimeVars)


	local SUN_RISE = 360
	local SUN_SET = 1160
	local SUNRISE_CALLED = false
	local SUNSET_CALLED = false
	local NEWDAY_CALLED = false

	local timerfunction = function()
		if StormFox.GetTimeSpeed() <= 0 then return end
		local time = StormFox.GetTime()
		if not SUNRISE_CALLED and time >= SUN_RISE and time < SUN_SET then
			hook.Call( "StormFox-Sunrise" )
			SUNRISE_CALLED = true
			SUNSET_CALLED = false
		elseif not SUNSET_CALLED and ( time < SUN_RISE or time >= SUN_SET ) then
			hook.Call( "StormFox-Sunset" )
			SUNRISE_CALLED = false
			SUNSET_CALLED = true
			NEWDAY_CALLED = false
		elseif time < StormFox.GetTimeSpeed() and not NEWDAY_CALLED then
			hook.Call( "StormFox-NewDay" )
			NEWDAY_CALLED = true
		end

		hook.Call( "StormFox-Tick", nil, StormFox.GetTime() )
	end
	timer.Create( "StormFox-tick", 1, 0, timerfunction )
	hook.Add("StormFox - Timeset","StormFox-Newdayfix",function()
		NEWDAY_CALLED = false
	end)
else -- CLIENT

	net.Receive( "StormFox_SetTimeData", function()
		local flCurrentTime = net.ReadFloat()
		TIME_SPEED = net.ReadFloat()
		if TIME_SPEED > 0 then
			BASE_TIME = CurTime() - ( flCurrentTime / TIME_SPEED )
		else
			BASE_TIME = flCurrentTime
		end
		hook.Call( "StormFox - Timeset")
	end )
end

function StormFox.GetTimeSpeed()
	return TIME_SPEED
end

function StormFox.GetTime( bNearestSecond )
	if TIME_SPEED <= 0 then
		return bNearestSecond and math.Round( BASE_TIME ) or BASE_TIME
	end
	local flTime = ( ( CurTime() - BASE_TIME ) * TIME_SPEED ) % 1440

	return bNearestSecond and math.Round( flTime ) or flTime
end

function StormFox.GetRealTime(num, _12clock )
	local var = num or StormFox.GetTime()
	local h = math.floor(var / 60)
	local m = math.floor(var - (h * 60))
	if not _12clock then return h .. ":" .. (m < 10 and "0" or "") .. m end

	local e = "PM"
	if h < 12 or h == 0 then
		e = "AM"
	end
	if h == 0 then
		h = 12
	elseif h > 12 then
		h = h - 12
	end
	return h .. ":" .. (m < 10 and "0" or "") .. m .. " " .. e
end

function StormFox.CalculateMapLight( flTime, nMin, nMax )
	nMax = nMax or 100
	flTime = flTime or StormFox.GetTime()
	-- Just a function to calc daylight amount based on time. See here https://www.desmos.com/calculator/842tvu0nvq
	local flMapLight = -0.00058 * math.pow( flTime - 750, 2 ) + nMax
	return clamp( flMapLight, nMin or 1, nMax )
end

if SERVER then
	StormFox.SetTime( os.time() % 1440 )
end

-- Setup starvar

if SERVER then
	hook.Add("StormFox - PostInit","StormFox - StartTime",function()
		local con = GetConVar("sf_start_time")
		if con and con:GetString() ~= "" then
			local str = string.Replace(con:GetString()," ","")
			local n = StringToTime(str)
			if not n then print("[StormFox] WARNING. sf_start_time is invalid: " .. str) return end
			print("[StormFox] sf_start_time: Setting time to: " .. str)
			StormFox.SetTime(n)
		else
			local cookie = cookie.GetString("StormFox-ShutDown",nil)
			if cookie then
				local a = string.Explode("|",cookie)
				local diff_time = os.time() - tonumber(a[2])
				if TIME_SPEED > 0 then
					diff_time = diff_time * TIME_SPEED
				end
				local n = tonumber(a[1]) + diff_time
				StormFox.SetTime(n % 1440)
				print("[StormFox] Loaded time.")
			end
		end
		cookie.Delete("StormFox-ShutDown") -- Always delete
	end)
	hook.Add("ShutDown","StormFox - OnShutdown",function()
		cookie.Set("StormFox-ShutDown",StormFox.GetTime() .. "|" .. os.time( ))
		print("[StormFox] Saved time.")
	end)
end