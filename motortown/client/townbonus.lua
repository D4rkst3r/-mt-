-- ============================================================
--  client/townbonus.lua
--  Verfolgt in welcher Bonus-Zone der Spieler sich befindet,
--  cached den letzten Bonus-Table und informiert das HUD.
-- ============================================================

local TownBonusModule = {}

-- Letzter bekannter Bonus-Table vom Server
-- [zoneKey] = bonus (1.0 – 2.0)
local bonusTable = {}

-- Aktuelle Zone des Spielers (zoneKey oder nil)
local currentBonusZone = nil

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

-- Gibt den Bonus der aktuellen Zone zurück (1.0 wenn keine)
local function GetCurrentBonus()
    if not currentBonusZone then return 1.0 end
    return bonusTable[currentBonusZone] or 1.0
end

-- Formatiert Bonus als lesbaren String: 1.35 → "+35%"
local function FormatBonus(bonus)
    local pct = math.floor((bonus - 1.0) * 100)
    if pct <= 0 then return "Kein Bonus" end
    return ("+%d%%"):format(pct)
end

-- ────────────────────────────────────────────────────────────
--  Zone-Tracking (reagiert auf MT.ZONE_ENTER / ZONE_EXIT)
-- ────────────────────────────────────────────────────────────

local function OnZoneEnter(zoneName, zoneData)
    if not zoneData or not zoneData.bonusZone then return end

    currentBonusZone = zoneData.zoneKey
    local bonus = bonusTable[currentBonusZone] or 1.0

    -- HUD über neue Zone informieren
    TriggerEvent(MT.BONUS_UPDATE, bonusTable, currentBonusZone, bonus)

    -- Notify nur wenn Bonus signifikant (> 1.10)
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
    -- Nur zurücksetzen wenn die aktive Bonus-Zone verlassen wird
    local zone = Config.Zones[zoneName]
    if zone and zone.bonusZone and zone.zoneKey == currentBonusZone then
        currentBonusZone = nil
        TriggerEvent(MT.BONUS_UPDATE, bonusTable, nil, 1.0)
    end
end

-- ────────────────────────────────────────────────────────────
--  Server-Update empfangen
-- ────────────────────────────────────────────────────────────

local function OnBonusUpdate(newBonusTable)
    bonusTable = newBonusTable

    -- Aktuellen Zonen-Bonus neu berechnen falls Spieler in Zone ist
    local currentBonus = GetCurrentBonus()

    -- HUD-Modul informieren
    TriggerEvent(MT.BONUS_UPDATE, bonusTable, currentBonusZone, currentBonus)
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function TownBonusModule.GetCurrentBonus()
    return GetCurrentBonus()
end

function TownBonusModule.GetCurrentZone()
    return currentBonusZone
end

function TownBonusModule.GetBonusTable()
    return bonusTable
end

function TownBonusModule.FormatBonus(bonus)
    return FormatBonus(bonus or GetCurrentBonus())
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function TownBonusModule.Init()
    RegisterNetEvent(MT.BONUS_UPDATE, OnBonusUpdate)

    AddEventHandler(MT.ZONE_ENTER, OnZoneEnter)
    AddEventHandler(MT.ZONE_EXIT, OnZoneExit)

    exports("GetCurrentBonus", TownBonusModule.GetCurrentBonus)
    exports("GetCurrentZone", TownBonusModule.GetCurrentZone)
    exports("GetBonusTable", TownBonusModule.GetBonusTable)
    exports("FormatBonus", TownBonusModule.FormatBonus)

    print("[MT] TownBonusModule (Client) initialisiert")
end

_TownBonusModule = TownBonusModule
