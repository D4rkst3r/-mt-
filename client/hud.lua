-- ============================================================
--  client/hud.lua
--  Persistentes HUD via eigene DrawText-Threads.
--  lib.setStatuses wird NICHT verwendet (nicht in dieser ox_lib-Version).
--
--  Anzeige:
--  - Oben links:   Geld | Level | XP
--  - Oben mitte:   Aktiver Job
--  - Unten rechts: km/h | Fuel | Schaden (nur im Fahrzeug)
--  - Unten links:  Town Bonus (wenn aktiv)
-- ============================================================

local HudModule = {}

local hudState = {
    money         = 0,
    bank          = 0,
    level         = 1,
    xp            = 0,
    xpNeeded      = 100,
    jobLabel      = nil,
    jobStep       = nil,
    bonusZone     = nil,
    bonusValue    = 1.0,
    fuel          = 100,
    speed         = 0,
    vehicleDamage = 0.0,
    inVehicle     = false,
    visible       = true,
}

-- ────────────────────────────────────────────────────────────
--  Draw-Thread
-- ────────────────────────────────────────────────────────────

local function DrawLine(text, x, y, r, g, b, a, scale, font, justify)
    scale      = scale or 0.28
    font       = font or 4
    justify    = justify or 1 -- 1 = links
    r, g, b, a = r or 255, g or 255, b or 255, a or 220

    SetTextFont(font)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, a)
    SetTextJustification(justify)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function StartDrawThread()
    CreateThread(function()
        while true do
            Wait(0)
            if not hudState.visible then goto continue end

            -- ── Oben links: Geld / Level / XP ──────────────
            DrawRect(0.09, 0.025, 0.175, 0.064, 0, 0, 0, 150)

            DrawLine(
                ("💵 %s"):format(Utils.FormatMoney(hudState.money)),
                0.010, 0.010, 80, 220, 80, 255, 0.30
            )

            local xpPct = hudState.xpNeeded > 0
                and math.floor((hudState.xp / hudState.xpNeeded) * 100)
                or 0
            DrawLine(
                ("Lvl %d  |  %d / %d XP  (%d%%)"):format(
                    hudState.level, hudState.xp, hudState.xpNeeded, xpPct),
                0.010, 0.034, 100, 180, 255, 220, 0.24
            )

            -- ── Oben Mitte: Aktiver Job ─────────────────────
            if hudState.jobLabel then
                local icon = hudState.jobStep == "Abholen" and "📦" or "📍"
                DrawRect(0.50, 0.025, 0.30, 0.032, 0, 0, 0, 150)
                DrawLine(
                    ("%s  %s  –  %s"):format(icon, hudState.jobLabel, hudState.jobStep or ""),
                    0.50, 0.012, 255, 220, 50, 255, 0.28, 4, 0 -- justify 0 = zentriert
                )
            end

            -- ── Unten rechts: Fahrzeug-Status ───────────────
            if hudState.inVehicle then
                DrawRect(0.935, 0.905, 0.125, 0.075, 0, 0, 0, 150)

                -- Geschwindigkeit
                DrawLine(
                    ("%d km/h"):format(math.floor(hudState.speed)),
                    0.967, 0.878, 255, 255, 255, 220, 0.32, 4, 2
                )

                -- Kraftstoff
                local fr, fg = 80, 200
                if hudState.fuel < 20 then
                    fr, fg = 220, 50
                elseif hudState.fuel < 50 then
                    fr, fg = 255, 160
                end
                DrawLine(
                    ("⛽ %d%%"):format(math.floor(hudState.fuel)),
                    0.967, 0.906, fr, fg, 60, 220, 0.26, 4, 2
                )

                -- Schaden (nur wenn relevant)
                if hudState.vehicleDamage > 0.05 then
                    local dr, dg = 255, 140
                    if hudState.vehicleDamage > 0.5 then dr, dg = 220, 50 end
                    DrawLine(
                        ("🔧 %d%%"):format(math.floor(hudState.vehicleDamage * 100)),
                        0.967, 0.930, dr, dg, 0, 220, 0.26, 4, 2
                    )
                end
            end

            -- ── Unten links: Town Bonus ─────────────────────
            if hudState.bonusValue > 1.0 then
                local bonusPct = math.floor((hudState.bonusValue - 1.0) * 100)
                DrawRect(0.065, 0.930, 0.125, 0.030, 0, 0, 0, 150)
                DrawLine(
                    ("📍 Bonus +%d%%"):format(bonusPct),
                    0.010, 0.918, 255, 215, 0, 255, 0.27
                )
            end

            ::continue::
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeugdaten lesen
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
    hudState.speed         = GetEntitySpeed(vehicle) * 3.6
    local bodyHealth       = GetVehicleBodyHealth(vehicle)
    hudState.vehicleDamage = Utils.Round(1.0 - (bodyHealth / 1000.0), 2)
end

-- ────────────────────────────────────────────────────────────
--  Update-Tick
-- ────────────────────────────────────────────────────────────

local function UpdateHud()
    ReadVehicleData()

    local playerData = exports["motortown"]:GetPlayerData()
    if playerData then
        hudState.money    = playerData.money or 0
        hudState.bank     = playerData.bank or 0
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
--  Event-Handler
-- ────────────────────────────────────────────────────────────

local function OnMoneyUpdate(cash, bank)
    hudState.money = cash
    hudState.bank  = bank
end

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
    hudState.vehicleDamage = data and data.damage or 0.0
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function HudModule.Init()
    AddEventHandler("mt:player:ready", function(data)
        if not data then return end

        hudState.money    = data.money or 0
        hudState.bank     = data.bank or 0
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
    AddEventHandler(MT.BONUS_CHANGED, OnBonusChanged)       -- MT.BONUS_CHANGED, nicht BONUS_UPDATE!
    AddEventHandler(MT.VEHICLE_DAMAGE_SYNC, OnVehicleDamage)

    RegisterCommand("hud", function()
        hudState.visible = not hudState.visible
        lib.notify({
            title = hudState.visible and "HUD eingeblendet" or "HUD ausgeblendet",
            type  = "inform",
        })
    end, false)

    print("[MT] HudModule initialisiert")
end

_HudModule = HudModule
