-- ============================================================
--  client/hud.lua  –  NUI-basiertes HUD
--  Alle Panels werden via SendNUIMessage an die UI geschickt.
--
--  NUI-Actions:
--    vehicle_show / vehicle_hide
--    player_update
--    job_show / job_hide
--    bonus_show / bonus_hide
-- ============================================================

local HudModule     = {}

-- ────────────────────────────────────────────────────────────
--  State
-- ────────────────────────────────────────────────────────────

local state         = {
    -- Spieler
    money        = 0,
    level        = 1,
    xp           = 0,
    xpNeeded     = 100,
    -- Job
    jobLabel     = nil,
    jobStep      = nil,
    -- Bonus
    bonus        = 1.0,
    -- Fahrzeug
    inVehicle    = false,
    seatbeltOn   = false,
    cruiseOn     = false,
    -- Kilometerstand
    odometerBase = 0.0,
    odometer     = 0.0,
}

-- Interner Kilometerstand-Tracker
local lastOdoCoords = nil
local odoCooldown   = 0

-- ────────────────────────────────────────────────────────────
--  Tastenbelegung (im Fahrzeug)
-- ────────────────────────────────────────────────────────────

local function StartInputThread()
    CreateThread(function()
        while true do
            local sleep = 500
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                sleep = 0
                -- K = Sicherheitsgurt
                if IsControlJustReleased(0, 311) then
                    state.seatbeltOn = not state.seatbeltOn
                    lib.notify({
                        title    = state.seatbeltOn and "🟢 Gurt angelegt" or "🔴 Gurt abgelegt",
                        type     = state.seatbeltOn and "success" or "error",
                        duration = 2000,
                    })
                end
                -- Y = Tempomat
                if IsControlJustReleased(0, 246) then
                    state.cruiseOn = not state.cruiseOn
                    lib.notify({
                        title    = state.cruiseOn and "⚙️ Tempomat AN" or "⚙️ Tempomat AUS",
                        type     = "inform",
                        duration = 2000,
                    })
                end
            else
                state.seatbeltOn = false
                state.cruiseOn   = false
            end
            Wait(sleep)
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  TCS-Erkennung
-- ────────────────────────────────────────────────────────────

local function IsTCSActive(veh, entitySpeed)
    if not IsVehicleEngineOn(veh) or entitySpeed < 1.0 then return false end
    if IsVehicleInBurnout(veh) then return true end
    local wheelSpeed = GetVehicleWheelSpeed(veh, 0)
    if wheelSpeed > (entitySpeed * 1.4) then return true end
    local lat = GetEntitySpeedVector(veh, true).x
    if math.abs(lat) > (entitySpeed * 0.35) then return true end
    return false
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug-Update-Thread (80ms)
-- ────────────────────────────────────────────────────────────

local function StartVehicleThread()
    CreateThread(function()
        while true do
            local sleep = 500
            local ped   = PlayerPedId()

            if IsPedInAnyVehicle(ped, false) then
                sleep             = 80
                local veh         = GetVehiclePedIsIn(ped, false)
                local entitySpeed = GetEntitySpeed(veh)

                -- Kilometerstand
                local now         = GetGameTimer()
                if now - odoCooldown > 200 then
                    odoCooldown = now
                    local coords = GetEntityCoords(veh)
                    if lastOdoCoords and entitySpeed > 0.5 then
                        state.odometer = state.odometer + (#(coords - lastOdoCoords) / 1000.0)
                    end
                    lastOdoCoords = coords
                end

                -- Lichter
                local lightsOn, highbeamsOn = GetVehicleLightsState(veh)
                local ind = GetVehicleIndicatorLights(veh)
                local engineHealth = GetVehicleEngineHealth(veh)

                SendNUIMessage({
                    action        = "vehicle_show",
                    speed         = math.floor(entitySpeed * 3.6),
                    rpm           = math.floor(GetVehicleCurrentRpm(veh) * 100),
                    rpmRaw        = math.floor(GetVehicleCurrentRpm(veh) * 8000),
                    gear          = GetVehicleCurrentGear(veh) == 0 and "R" or GetVehicleCurrentGear(veh),
                    fuel          = math.floor(GetVehicleFuelLevel(veh)),
                    engine        = math.floor(engineHealth / 10),
                    odometer      = Utils.Round(state.odometerBase + state.odometer, 1),
                    -- Lichter
                    lightsLow     = lightsOn,
                    lightsHigh    = highbeamsOn,
                    -- Blinker
                    leftSignal    = (ind == 1 or ind == 3),
                    rightSignal   = (ind == 2 or ind == 3),
                    -- Warnleuchten
                    handbrake     = GetVehicleHandbrake(veh) == 1,
                    isOilCritical = engineHealth < 250,
                    tcs           = IsTCSActive(veh, entitySpeed),
                    -- Status
                    seatbelt      = state.seatbeltOn,
                    cruise        = state.cruiseOn,
                })
            else
                if state.inVehicle then
                    SendNUIMessage({ action = "vehicle_hide" })
                    state.inVehicle  = false
                    state.seatbeltOn = false
                    state.cruiseOn   = false
                    lastOdoCoords    = nil
                end
                sleep = 500
            end

            state.inVehicle = IsPedInAnyVehicle(ped, false)
            Wait(sleep)
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  Spieler-Update (via Interval)
-- ────────────────────────────────────────────────────────────

local function SendPlayerUpdate()
    local xpPct = state.xpNeeded > 0
        and math.floor((state.xp / state.xpNeeded) * 100) or 0
    SendNUIMessage({
        action = "player_update",
        money  = Utils.FormatMoney(state.money),
        level  = state.level,
        xp     = state.xp,
        xpPct  = xpPct,
    })
end

local function SendJobUpdate()
    if state.jobLabel then
        SendNUIMessage({
            action = "job_show",
            label  = state.jobLabel,
            step   = state.jobStep,
        })
    else
        SendNUIMessage({ action = "job_hide" })
    end
end

local function SendBonusUpdate()
    if state.bonus > 1.0 then
        SendNUIMessage({
            action = "bonus_show",
            pct    = math.floor((state.bonus - 1.0) * 100),
        })
    else
        SendNUIMessage({ action = "bonus_hide" })
    end
end

local function UpdateAll()
    local playerData = exports["motortown"]:GetPlayerData()
    if playerData then
        state.money    = playerData.money or 0
        state.level    = playerData.trucking_level or 1
        state.xp       = playerData.trucking_xp or 0
        state.xpNeeded = Utils.XPForLevel((playerData.trucking_level or 1) + 1)
    end

    local currentJob = exports["motortown"]:GetCurrentJob()
    if currentJob then
        state.jobLabel = currentJob.label
        state.jobStep  = currentJob.cargoLoaded and "Liefern" or "Abholen"
    else
        state.jobLabel = nil
        state.jobStep  = nil
    end

    state.bonus = exports["motortown"]:GetCurrentBonus()

    SendPlayerUpdate()
    SendJobUpdate()
    SendBonusUpdate()
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API (für vehicles.lua)
-- ────────────────────────────────────────────────────────────

function HudModule.SetOdometerBase(km)
    state.odometerBase = km or 0
    state.odometer     = 0
    lastOdoCoords      = nil
end

function HudModule.GetOdometer()
    return Utils.Round(state.odometerBase + state.odometer, 1)
end

-- ────────────────────────────────────────────────────────────
--  Event-Handler
-- ────────────────────────────────────────────────────────────

local function OnMoneyUpdate(cash)
    state.money = cash
    SendPlayerUpdate()
end

local function OnXPUpdate(xp, level)
    state.xp       = xp
    state.level    = level
    state.xpNeeded = Utils.XPForLevel(level + 1)
    SendPlayerUpdate()
end

local function OnLevelUp(newLevel)
    lib.notify({
        title       = "🎉 Level Up!",
        description = ("Du bist jetzt Level %d!"):format(newLevel),
        type        = "success",
        duration    = 6000,
    })
end

local function OnBonusChanged(bt, zoneKey, bonus)
    state.bonus = bonus or 1.0
    SendBonusUpdate()
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function HudModule.Init()
    AddEventHandler("mt:player:ready", function(data)
        if not data then return end

        state.money    = data.money or 0
        state.level    = data.trucking_level or 1
        state.xp       = data.trucking_xp or 0
        state.xpNeeded = Utils.XPForLevel((data.trucking_level or 1) + 1)

        -- NUI anzeigen
        SetNuiFocus(false, false)
        SendPlayerUpdate()
        SendBonusUpdate()

        StartVehicleThread()
        StartInputThread()
        CreateThread(function()
            while true do
                Wait(Config.HudUpdateMs)
                UpdateAll()
            end
        end)

        lib.notify({
            title       = Config.ServerName,
            description = "Viel Erfolg auf der Straße! 🚛",
            type        = "inform",
            duration    = 4000,
        })
    end)

    AddEventHandler(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    AddEventHandler(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    AddEventHandler(MT.PLAYER_LEVEL_UP, OnLevelUp)
    AddEventHandler(MT.BONUS_CHANGED, OnBonusChanged)

    -- Job-Änderungen sofort pushen
    AddEventHandler(MT.JOB_START, function(data)
        state.jobLabel = data and data.label
        state.jobStep  = "Abholen"
        SendJobUpdate()
    end)
    AddEventHandler(MT.JOB_CARGO_LOADED, function()
        state.jobStep = "Liefern"
        SendJobUpdate()
    end)
    AddEventHandler(MT.JOB_COMPLETE, function()
        state.jobLabel = nil
        SendJobUpdate()
    end)
    AddEventHandler(MT.JOB_CANCEL, function()
        state.jobLabel = nil
        SendJobUpdate()
    end)

    RegisterCommand("hud", function()
        -- Toggle: vehicle-hud via NUI verstecken
        SendNUIMessage({ action = "vehicle_hide" })
        lib.notify({ title = "HUD ausgeblendet", type = "inform" })
    end, false)

    exports("GetOdometer", HudModule.GetOdometer)

    print("[MT] HudModule initialisiert (NUI)")
end

_HudModule = HudModule
