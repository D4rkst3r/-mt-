-- ============================================================
--  client/hud.lua
--  Tacho-HUD mit Geschwindigkeit, Kraftstoff, Kilometerstand,
--  Blinker, Warnblinker, Licht und Fernlicht.
--
--  Panels:
--  - Oben links:    Geld | Level | XP
--  - Oben mitte:    Aktiver Job
--  - Unten mitte:   Tacho-Panel (nur im Fahrzeug)
--  - Unten links:   Town Bonus (wenn aktiv)
-- ============================================================

local HudModule     = {}

-- ────────────────────────────────────────────────────────────
--  State
-- ────────────────────────────────────────────────────────────

local hudState      = {
    -- Spieler
    money        = 0,
    level        = 1,
    xp           = 0,
    xpNeeded     = 100,
    -- Job
    jobLabel     = nil,
    jobStep      = nil,
    -- Bonus
    bonusValue   = 1.0,
    bonusZone    = nil,
    -- Fahrzeug
    inVehicle    = false,
    speed        = 0,
    fuel         = 100,
    damage       = 0.0,
    odometer     = 0.0, -- km dieser Session
    odometerBase = 0.0, -- km aus DB beim Spawn
    -- Fahrzeuglichter / Blinker
    lightOn      = false,
    highbeam     = false,
    indLeft      = false,
    indRight     = false,
    hazard       = false,
    -- Sichtbarkeit
    visible      = true,
}

-- Blinker-Animation (250ms on/off)
local blinkOn       = false
local lastBlinkTime = 0

-- Kilometerstand-Tracking
local lastOdoCoords = nil
local odoCooldown   = 0

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen Draw
-- ────────────────────────────────────────────────────────────

local function Txt(text, x, y, r, g, b, a, scale, font, justify)
    SetTextFont(font or 4)
    SetTextScale(0.0, scale or 0.27)
    SetTextColour(r or 255, g or 255, b or 255, a or 230)
    SetTextJustification(justify or 0) -- 0=links, 1=zentriert, 2=rechts
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function Box(x, y, w, h, r, g, b, a)
    DrawRect(x, y, w, h, r or 0, g or 0, b or 0, a or 160)
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeugdaten lesen
-- ────────────────────────────────────────────────────────────

local function ReadVehicleData()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        hudState.inVehicle = false
        hudState.speed     = 0
        hudState.fuel      = 100
        hudState.damage    = 0.0
        hudState.lightOn   = false
        hudState.highbeam  = false
        hudState.indLeft   = false
        hudState.indRight  = false
        hudState.hazard    = false
        lastOdoCoords      = nil
        return
    end

    hudState.inVehicle          = true
    hudState.speed              = GetEntitySpeed(vehicle) * 3.6
    hudState.fuel               = GetVehicleFuelLevel(vehicle)
    local bh                    = GetVehicleBodyHealth(vehicle)
    hudState.damage             = Utils.Round(1.0 - (bh / 1000.0), 2)

    -- Lichter
    local lightsOn, highbeamsOn = GetVehicleLightsState(vehicle)
    hudState.lightOn            = lightsOn
    hudState.highbeam           = highbeamsOn

    -- Blinker  0=aus  1=links  2=rechts  3=hazard
    local ind                   = GetVehicleIndicatorLights(vehicle)
    hudState.indLeft            = (ind == 1 or ind == 3)
    hudState.indRight           = (ind == 2 or ind == 3)
    hudState.hazard             = (ind == 3)

    -- Kilometerstand (akkumuliert über Session)
    local now                   = GetGameTimer()
    if now - odoCooldown > 200 then -- alle 200ms
        odoCooldown = now
        local coords = GetEntityCoords(vehicle)
        if lastOdoCoords and hudState.speed > 2.0 then
            local dist = #(coords - lastOdoCoords)
            hudState.odometer = hudState.odometer + (dist / 1000.0)
        end
        lastOdoCoords = coords
    end
end

-- ────────────────────────────────────────────────────────────
--  Blinker-Takt
-- ────────────────────────────────────────────────────────────

local function UpdateBlink()
    local now = GetGameTimer()
    if now - lastBlinkTime > 500 then
        blinkOn       = not blinkOn
        lastBlinkTime = now
    end
end

-- ────────────────────────────────────────────────────────────
--  Tacho-Panel zeichnen
-- ────────────────────────────────────────────────────────────

local function DrawTacho()
    -- Haupt-Panel: unten Mitte
    -- Breite 0.36, Höhe 0.11, zentriert bei x=0.50
    local px, py = 0.50, 0.945
    local pw, ph = 0.38, 0.11

    -- Hintergrund
    Box(px, py, pw, ph, 10, 10, 10, 185)
    -- Oberer Trennstrich
    Box(px, py - ph * 0.5 + 0.002, pw, 0.003, 60, 60, 60, 200)

    -- ── Geschwindigkeit (groß, links-mitte) ──────────────────
    local speedInt = math.floor(hudState.speed)
    local speedStr = tostring(speedInt)

    -- Zahl
    SetTextFont(7) -- Schriftart 7 = Zahlen
    SetTextScale(0.0, 0.72)
    SetTextColour(255, 255, 255, 240)
    SetTextJustification(2) -- rechts
    SetTextEntry("STRING")
    AddTextComponentString(speedStr)
    DrawText(0.44, 0.905)

    -- Einheit
    Txt("km/h", 0.446, 0.930, 160, 160, 160, 200, 0.22, 4, 0)

    -- ── Kraftstoff-Balken (Mitte) ─────────────────────────────
    local fuelPct = math.max(0, math.min(100, hudState.fuel)) / 100.0
    local barX    = 0.500
    local barY    = 0.910
    local barW    = 0.085
    local barH    = 0.018

    -- Label
    Txt("⛽ KRAFTSTOFF", barX, 0.896, 140, 140, 140, 200, 0.20, 4, 1)

    -- Hintergrund Balken
    Box(barX, barY, barW, barH, 30, 30, 30, 220)

    -- Füllstand-Farbe
    local fr, fg, fb = 50, 200, 80
    if fuelPct < 0.25 then
        fr, fg, fb = 220, 50, 50
    elseif fuelPct < 0.5 then
        fr, fg, fb = 255, 160, 30
    end
    if fuelPct > 0 then
        Box(barX - barW * 0.5 + (barW * fuelPct) * 0.5,
            barY, barW * fuelPct, barH, fr, fg, fb, 220)
    end

    -- Prozentzahl
    Txt(("%d%%"):format(math.floor(hudState.fuel)), barX, 0.921, 200, 200, 200, 210, 0.21, 4, 1)

    -- ── Schaden (unter Kraftstoff) ────────────────────────────
    if hudState.damage > 0.05 then
        local dr, dg, db = 255, 200, 50
        if hudState.damage > 0.5 then dr, dg, db = 220, 50, 50 end
        local dmgPct = math.floor(hudState.damage * 100)
        Txt(("🔧 %d%%"):format(dmgPct), barX, 0.936, dr, dg, db, 220, 0.22, 4, 1)
    end

    -- ── Kilometerstand (rechts) ───────────────────────────────
    local totalKm = hudState.odometerBase + hudState.odometer
    local odoStr  = ("%.1f km"):format(totalKm)
    Txt("ODO", 0.590, 0.896, 140, 140, 140, 200, 0.20, 4, 1)
    Txt(odoStr, 0.590, 0.910, 220, 220, 220, 230, 0.26, 4, 1)

    -- ── Licht-Icons (rechts unten) ────────────────────────────
    local lightColor = hudState.lightOn and { 80, 200, 80, 240 } or { 70, 70, 70, 160 }
    local hbeamColor = hudState.highbeam and { 80, 180, 255, 240 } or { 70, 70, 70, 160 }

    Txt("💡", 0.567, 0.930,
        lightColor[1], lightColor[2], lightColor[3], lightColor[4], 0.24, 4, 1)
    Txt("🔆", 0.592, 0.930,
        hbeamColor[1], hbeamColor[2], hbeamColor[3], hbeamColor[4], 0.24, 4, 1)

    -- ── Blinker (links und rechts außen am Panel) ─────────────
    UpdateBlink()

    -- Linker Blinker
    if hudState.indLeft then
        local r, g, b = blinkOn and 255 or 80, blinkOn and 165 or 80, 0
        local a       = blinkOn and 255 or 100
        Txt("◄◄", 0.333, 0.914, r, g, b, a, 0.36, 4, 0)
    else
        Txt("◄◄", 0.333, 0.914, 50, 50, 50, 120, 0.36, 4, 0)
    end

    -- Rechter Blinker
    if hudState.indRight then
        local r, g, b = blinkOn and 255 or 80, blinkOn and 165 or 80, 0
        local a       = blinkOn and 255 or 100
        Txt("►►", 0.660, 0.914, r, g, b, a, 0.36, 4, 0)
    else
        Txt("►►", 0.660, 0.914, 50, 50, 50, 120, 0.36, 4, 0)
    end

    -- Warnblinker-Label (mittig über Blinker wenn aktiv)
    if hudState.hazard and blinkOn then
        Txt("⚠ WARNBLINKER", 0.500, 0.876, 255, 165, 0, 255, 0.22, 4, 1)
    end
end

-- ────────────────────────────────────────────────────────────
--  Spieler-Panel oben links
-- ────────────────────────────────────────────────────────────

local function DrawPlayerPanel()
    Box(0.093, 0.025, 0.182, 0.064, 10, 10, 10, 175)

    Txt(("💵 %s"):format(Utils.FormatMoney(hudState.money)),
        0.010, 0.010, 80, 220, 80, 255, 0.29, 4, 0)

    local xpPct = hudState.xpNeeded > 0
        and math.floor((hudState.xp / hudState.xpNeeded) * 100) or 0
    Txt(("Lvl %d  |  %d / %d XP  (%d%%)"):format(
            hudState.level, hudState.xp, hudState.xpNeeded, xpPct),
        0.010, 0.034, 100, 180, 255, 210, 0.22, 4, 0)
end

-- ────────────────────────────────────────────────────────────
--  Job-Panel oben mitte
-- ────────────────────────────────────────────────────────────

local function DrawJobPanel()
    if not hudState.jobLabel then return end
    local icon = hudState.jobStep == "Abholen" and "📦" or "📍"
    Box(0.500, 0.025, 0.32, 0.032, 10, 10, 10, 160)
    Txt(("%s  %s  –  %s"):format(icon, hudState.jobLabel, hudState.jobStep or ""),
        0.500, 0.013, 255, 220, 50, 255, 0.27, 4, 1)
end

-- ────────────────────────────────────────────────────────────
--  Bonus-Panel unten links
-- ────────────────────────────────────────────────────────────

local function DrawBonusPanel()
    if hudState.bonusValue <= 1.0 then return end
    local pct = math.floor((hudState.bonusValue - 1.0) * 100)
    Box(0.068, 0.933, 0.132, 0.028, 10, 10, 10, 160)
    Txt(("📍 Bonus +%d%%"):format(pct),
        0.010, 0.921, 255, 215, 0, 255, 0.26, 4, 0)
end

-- ────────────────────────────────────────────────────────────
--  Draw-Thread
-- ────────────────────────────────────────────────────────────

local function StartDrawThread()
    CreateThread(function()
        while true do
            Wait(0)
            if not hudState.visible then goto continue end

            DrawPlayerPanel()
            DrawJobPanel()
            if hudState.inVehicle then DrawTacho() end
            DrawBonusPanel()

            ::continue::
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  Update-Tick
-- ────────────────────────────────────────────────────────────

local function UpdateHud()
    ReadVehicleData()

    local playerData = exports["motortown"]:GetPlayerData()
    if playerData then
        hudState.money    = playerData.money or 0
        hudState.level    = playerData.trucking_level or 1
        hudState.xp       = playerData.trucking_xp or 0
        hudState.xpNeeded = Utils.XPForLevel((playerData.trucking_level or 1) + 1)
    end

    local currentJob = exports["motortown"]:GetCurrentJob()
    if currentJob then
        hudState.jobLabel = currentJob.label
        hudState.jobStep  = currentJob.cargoLoaded and "Liefern" or "Abholen"
    else
        hudState.jobLabel = nil
        hudState.jobStep  = nil
    end

    hudState.bonusValue = exports["motortown"]:GetCurrentBonus()
    hudState.bonusZone  = exports["motortown"]:GetCurrentZone()
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

-- Wird von vehicles.lua aufgerufen wenn Fahrzeug gespawnt wird
function HudModule.SetOdometerBase(km)
    hudState.odometerBase = km or 0
    hudState.odometer     = 0
    lastOdoCoords         = nil
end

-- Gibt aktuellen Gesamtkilometerstand zurück (für Einlagern)
function HudModule.GetOdometer()
    return Utils.Round(hudState.odometerBase + hudState.odometer, 1)
end

-- ────────────────────────────────────────────────────────────
--  Event-Handler
-- ────────────────────────────────────────────────────────────

local function OnMoneyUpdate(cash) hudState.money = cash end
local function OnXPUpdate(xp, level)
    hudState.xp       = xp
    hudState.level    = level
    hudState.xpNeeded = Utils.XPForLevel(level + 1)
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
    hudState.bonusValue = bonus or 1.0
    hudState.bonusZone  = zoneKey
end
local function OnVehicleDamage(data)
    hudState.damage = data and data.damage or 0.0
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function HudModule.Init()
    AddEventHandler("mt:player:ready", function(data)
        if not data then return end

        hudState.money    = data.money or 0
        hudState.level    = data.trucking_level or 1
        hudState.xp       = data.trucking_xp or 0
        hudState.xpNeeded = Utils.XPForLevel((data.trucking_level or 1) + 1)

        StartDrawThread()
        SetInterval(UpdateHud, Config.HudUpdateMs)

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
    AddEventHandler(MT.VEHICLE_DAMAGE_SYNC, OnVehicleDamage)

    RegisterCommand("hud", function()
        hudState.visible = not hudState.visible
        lib.notify({
            title = hudState.visible and "HUD eingeblendet" or "HUD ausgeblendet",
            type  = "inform",
        })
    end, false)

    exports("GetOdometer", HudModule.GetOdometer)

    print("[MT] HudModule initialisiert")
end

_HudModule = HudModule
