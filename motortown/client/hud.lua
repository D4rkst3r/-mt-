-- ============================================================
--  client/hud.lua
--  Persistentes HUD via ox_lib statuses.
--
--  Zeigt an:
--  - Geld & Bank
--  - Trucking Level + XP-Fortschritt
--  - Aktiver Job (Label + Cargo-Status)
--  - Town Bonus der aktuellen Zone
--  - Fahrzeug: Kraftstoff + Geschwindigkeit + Schadenszustand
--
--  Aktualisiert sich alle Config.HudUpdateMs Millisekunden
--  plus sofort bei relevanten Events (Geld, Level, Job, Bonus).
--
--  ox_lib statuses Dokumentation:
--  lib.showTextUI / lib.hideTextUI für Kontext-Prompts
--  lib.setStatuses für persistente Statusanzeige
-- ============================================================

local HudModule = {}

-- Lokaler Snapshot aller HUD-Werte
local hudState = {
    money         = 0,
    bank          = 0,
    level         = 1,
    xp            = 0,
    xpNeeded      = 100,
    jobLabel      = nil,
    jobStep       = nil, -- "Abholen" | "Liefern" | nil
    bonusZone     = nil,
    bonusValue    = 1.0,
    fuel          = 100,
    speed         = 0,
    vehicleDamage = 0.0, -- 0.0 = perfekt, 1.0 = zerstört
    inVehicle     = false,
}

-- Verhindert Flackern: nur senden wenn sich etwas geändert hat
local lastSentState = {}

-- ────────────────────────────────────────────────────────────
--  ox_lib Statuses aufbauen
--
--  lib.setStatuses erwartet eine geordnete Liste von
--  { id, label, value (0-100), color, icon } Einträgen.
--  Wir mappen unsere Werte auf 0–100 Skalen.
-- ────────────────────────────────────────────────────────────

local function BuildStatuses()
    local statuses = {}

    -- Geld (keine Progress-Bar, nur Text via showTextUI wäre zu flüchtig)
    -- Stattdessen: Level-XP als Bar, Rest als Text-Status

    -- XP-Fortschritt
    if Config.HudDefaults.xp then
        local xpPct = hudState.xpNeeded > 0
            and math.floor((hudState.xp / hudState.xpNeeded) * 100)
            or 0
        table.insert(statuses, {
            id    = "mt_xp",
            label = ("Lvl %d  –  %d / %d XP"):format(
                hudState.level, hudState.xp, hudState.xpNeeded),
            value = Utils.Clamp(xpPct, 0, 100),
            color = { r = 100, g = 180, b = 255 },
        })
    end

    -- Kraftstoff (nur wenn im Fahrzeug)
    if Config.HudDefaults.fuel and hudState.inVehicle then
        local fuelColor
        if hudState.fuel > 50 then
            fuelColor = { r = 80, g = 200, b = 80 }
        elseif hudState.fuel > 20 then
            fuelColor = { r = 255, g = 180, b = 0 }
        else
            fuelColor = { r = 220, g = 50, b = 50 }
        end
        table.insert(statuses, {
            id    = "mt_fuel",
            label = ("⛽ %d%%"):format(math.floor(hudState.fuel)),
            value = Utils.Clamp(math.floor(hudState.fuel), 0, 100),
            color = fuelColor,
        })
    end

    -- Fahrzeugschaden
    if hudState.inVehicle and hudState.vehicleDamage > 0.05 then
        local dmgPct   = math.floor(hudState.vehicleDamage * 100)
        local dmgColor = hudState.vehicleDamage > 0.5
            and { r = 220, g = 50, b = 50 }
            or { r = 255, g = 140, b = 0 }
        table.insert(statuses, {
            id    = "mt_damage",
            label = ("🔧 Schaden %d%%"):format(dmgPct),
            value = Utils.Clamp(dmgPct, 0, 100),
            color = dmgColor,
        })
    end

    -- Town Bonus
    if Config.HudDefaults.bonus and hudState.bonusValue > 1.0 then
        local bonusPct = math.floor((hudState.bonusValue - 1.0) * 100)
        table.insert(statuses, {
            id    = "mt_bonus",
            label = ("📍 +%d%% Bonus"):format(bonusPct),
            value = Utils.Clamp(bonusPct, 0, 100),
            color = { r = 255, g = 215, b = 0 },
        })
    end

    return statuses
end

-- ────────────────────────────────────────────────────────────
--  Persistente Info-Zeile oben links via DrawText
--  (ox_lib hat kein nativer "immer sichtbar"-Text,
--   wir nutzen deshalb einen eigenen Draw-Thread)
-- ────────────────────────────────────────────────────────────

local drawThread = nil

local function StartDrawThread()
    if drawThread then return end
    drawThread = CreateThread(function()
        while true do
            Wait(0)

            -- Geld-Anzeige oben links
            if Config.HudDefaults.money and hudState.money ~= nil then
                -- Hintergrund-Box
                DrawRect(0.08, 0.025, 0.155, 0.030, 0, 0, 0, 140)

                -- Geld-Text
                SetTextFont(4)
                SetTextScale(0.0, 0.30)
                SetTextColour(80, 220, 80, 255)
                SetTextEntry("STRING")
                AddTextComponentString(("💵 %s"):format(Utils.FormatMoney(hudState.money)))
                DrawText(0.010, 0.012)
            end

            -- Job-Status Mitte oben (nur wenn aktiver Job)
            if Config.HudDefaults.job and hudState.jobLabel then
                local stepIcon = hudState.jobStep == "Abholen" and "📦" or "📍"
                local jobText  = ("%s %s  –  %s"):format(
                    stepIcon, hudState.jobLabel, hudState.jobStep or "")

                DrawRect(0.50, 0.025, 0.32, 0.030, 0, 0, 0, 140)

                SetTextFont(4)
                SetTextScale(0.0, 0.28)
                SetTextColour(255, 220, 50, 255)
                SetTextJustification(0) -- Zentriert
                SetTextEntry("STRING")
                AddTextComponentString(jobText)
                DrawText(0.50, 0.012)
            end

            -- Geschwindigkeit (rechts unten, nur im Fahrzeug)
            if Config.HudDefaults.speed and hudState.inVehicle then
                DrawRect(0.92, 0.92, 0.10, 0.030, 0, 0, 0, 140)

                SetTextFont(4)
                SetTextScale(0.0, 0.32)
                SetTextColour(255, 255, 255, 220)
                SetTextJustification(2) -- Rechtsbündig
                SetTextEntry("STRING")
                AddTextComponentString(("%d km/h"):format(math.floor(hudState.speed)))
                DrawText(0.968, 0.908)
            end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug-Werte lesen (läuft im Update-Tick)
-- ────────────────────────────────────────────────────────────

local function ReadVehicleData()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        hudState.inVehicle     = false
        hudState.fuel          = 100
        hudState.speed         = 0
        hudState.vehicleDamage = 0.0
        return
    end

    hudState.inVehicle     = true
    hudState.fuel          = GetVehicleFuelLevel(vehicle)
    hudState.speed         = GetEntitySpeed(vehicle) * 3.6 -- m/s → km/h

    local bodyHealth       = GetVehicleBodyHealth(vehicle) -- 0–1000
    hudState.vehicleDamage = Utils.Round(1.0 - (bodyHealth / 1000.0), 2)
end

-- ────────────────────────────────────────────────────────────
--  Update-Tick
-- ────────────────────────────────────────────────────────────

local function UpdateHud()
    ReadVehicleData()

    -- Player-Daten aus Cache holen
    local playerData = exports["motortown"]:GetPlayerData()
    if playerData then
        hudState.money    = playerData.money
        hudState.bank     = playerData.bank
        hudState.level    = playerData.trucking_level
        hudState.xp       = playerData.trucking_xp
        hudState.xpNeeded = Utils.XPForLevel(playerData.trucking_level + 1)
    end

    -- Job-Status aus JobModule
    local currentJob = exports["motortown"]:GetCurrentJob()
    if currentJob then
        hudState.jobLabel = currentJob.label
        hudState.jobStep  = currentJob.cargoLoaded and "Liefern" or "Abholen"
    else
        hudState.jobLabel = nil
        hudState.jobStep  = nil
    end

    -- Town Bonus
    hudState.bonusValue = exports["motortown"]:GetCurrentBonus()
    hudState.bonusZone  = exports["motortown"]:GetCurrentZone()

    -- ox_lib Statuses aktualisieren
    local statuses      = BuildStatuses()
    if #statuses > 0 then
        lib.setStatuses(statuses)
    end
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (sofortige Reaktion ohne Warten auf Tick)
-- ────────────────────────────────────────────────────────────

local function OnMoneyUpdate(cash, bank)
    hudState.money = cash
    hudState.bank  = bank
    -- Kein voller UpdateHud() nötig – DrawThread zeigt es sofort
end

local function OnXPUpdate(xp, level)
    hudState.xp       = xp
    hudState.level    = level
    hudState.xpNeeded = Utils.XPForLevel(level + 1)
    lib.setStatuses(BuildStatuses())
end

local function OnLevelUp(newLevel)
    -- Kurze animierte Level-Up Anzeige
    CreateThread(function()
        for i = 1, 6 do
            Wait(300)
            -- Blink-Effekt: XP-Bar voll anzeigen dann reset
            lib.setStatuses({ {
                id    = "mt_xp",
                label = ("🎉 LEVEL UP! → %d"):format(newLevel),
                value = (i % 2 == 0) and 100 or 0,
                color = { r = 255, g = 215, b = 0 },
            } })
        end
        -- Danach normal weiter
        UpdateHud()
    end)
end

local function OnJobStart()
    UpdateHud()
end

local function OnJobComplete()
    hudState.jobLabel = nil
    hudState.jobStep  = nil
    lib.setStatuses(BuildStatuses())
end

local function OnJobCancel()
    hudState.jobLabel = nil
    hudState.jobStep  = nil
    lib.setStatuses(BuildStatuses())
end

local function OnBonusUpdate(bonusTable, zoneKey, bonus)
    hudState.bonusValue = bonus or 1.0
    hudState.bonusZone  = zoneKey
    lib.setStatuses(BuildStatuses())
end

local function OnVehicleDamage(data)
    hudState.vehicleDamage = data.damage or 0.0
    lib.setStatuses(BuildStatuses())
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function HudModule.Init()
    -- Auf Spieler-Laden warten bevor HUD startet
    AddEventHandler(MT.PLAYER_LOADED, function(data)
        if not data then return end

        hudState.money    = data.money
        hudState.bank     = data.bank
        hudState.level    = data.trucking_level
        hudState.xp       = data.trucking_xp
        hudState.xpNeeded = Utils.XPForLevel(data.trucking_level + 1)

        -- Draw-Thread starten
        StartDrawThread()

        -- Periodischer Update-Tick
        SetInterval(UpdateHud, Config.HudUpdateMs)

        lib.notify({
            title       = Config.ServerName,
            description = "HUD aktiv. Viel Erfolg auf der Straße! 🚛",
            type        = "inform",
            duration    = 4000,
        })
    end)

    -- Sofort-Updates bei relevanten Events
    AddEventHandler(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    AddEventHandler(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    AddEventHandler(MT.PLAYER_LEVEL_UP, OnLevelUp)
    AddEventHandler(MT.JOB_START, OnJobStart)
    AddEventHandler(MT.JOB_COMPLETE, OnJobComplete)
    AddEventHandler(MT.JOB_CANCEL, OnJobCancel)
    AddEventHandler(MT.BONUS_UPDATE, OnBonusUpdate)
    AddEventHandler(MT.VEHICLE_DAMAGE_SYNC, OnVehicleDamage)

    -- /hud Befehl zum Ein-/Ausblenden
    RegisterCommand("hud", function()
        -- Alle Statuses leeren = verstecken
        lib.setStatuses({})
        lib.notify({ title = "HUD versteckt – /hud zum Einblenden", type = "inform" })
    end, false)

    print("[MT] HudModule initialisiert")
end

_HudModule = HudModule
