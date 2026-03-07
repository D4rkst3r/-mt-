-- ============================================================
--  client/townbonus.lua
--  Verfolgt in welcher Bonus-Zone der Spieler sich befindet,
--  cached den letzten Bonus-Table und informiert das HUD.
--
--  Events:
--    MT.BONUS_UPDATE  (NetEvent, Server→Client) – empfängt neuen bonusTable
--    MT.BONUS_CHANGED (lokales Event, Client)   – informiert HUD über Änderung
--    MT.ZONE_ENTER / MT.ZONE_EXIT               – Zone-Tracking
-- ============================================================

local TownBonusModule  = {}

local bonusTable       = {}  -- [zoneKey] = bonus (1.0 – 2.0)
local currentBonusZone = nil -- zoneKey oder nil

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

local function GetCurrentBonus()
    if not currentBonusZone then return 1.0 end
    return bonusTable[currentBonusZone] or 1.0
end

local function FormatBonus(bonus)
    local pct = math.floor((bonus - 1.0) * 100)
    if pct <= 0 then return "Kein Bonus" end
    return ("+%d%%"):format(pct)
end

-- Informiert HUD via lokalem Event (KEIN NetEvent, kein Loop)
local function NotifyHud()
    TriggerEvent(MT.BONUS_CHANGED, bonusTable, currentBonusZone, GetCurrentBonus())
end

-- ────────────────────────────────────────────────────────────
--  Zone-Tracking
-- ────────────────────────────────────────────────────────────

local function OnZoneEnter(zoneName, zoneData)
    if not zoneData or not zoneData.bonusZone then return end

    currentBonusZone = zoneData.zoneKey
    local bonus = bonusTable[currentBonusZone] or 1.0

    NotifyHud()

    if bonus >= 1.10 then
        lib.notify({
            title       = ("📍 %s"):format(zoneData.label or zoneName),
            description = ("Lohn-Bonus aktiv: **%s** (%.2fx)"):format(
                FormatBonus(bonus), bonus),
            type        = "inform",
            duration    = 5000,
        })
    end
end

local function OnZoneExit(zoneName)
    local zone = Config.Zones[zoneName]
    if zone and zone.bonusZone and zone.zoneKey == currentBonusZone then
        currentBonusZone = nil
        NotifyHud()
    end
end

-- ────────────────────────────────────────────────────────────
--  Server-Update empfangen  (MT.BONUS_UPDATE = NetEvent)
--  WICHTIG: Hier KEIN TriggerEvent(MT.BONUS_UPDATE) → Loop!
-- ────────────────────────────────────────────────────────────

local function OnBonusUpdate(newBonusTable)
    bonusTable = newBonusTable
    NotifyHud() -- MT.BONUS_CHANGED, nicht MT.BONUS_UPDATE!
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function TownBonusModule.GetCurrentBonus() return GetCurrentBonus() end

function TownBonusModule.GetCurrentZone() return currentBonusZone end

function TownBonusModule.GetBonusTable() return bonusTable end

function TownBonusModule.FormatBonus(b) return FormatBonus(b or GetCurrentBonus()) end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function TownBonusModule.Init()
    RegisterNetEvent(MT.BONUS_UPDATE, OnBonusUpdate)

    AddEventHandler(MT.ZONE_ENTER, OnZoneEnter)
    AddEventHandler(MT.ZONE_EXIT, OnZoneExit)

    print("[MT] TownBonusModule (Client) initialisiert")
end

_TownBonusModule = TownBonusModule
