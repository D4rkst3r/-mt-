-- ============================================================
--  server/townbonus.lua
--  Verwaltet den Town-Bonus jeder Stadtteil-Zone.
--
--  Mechanik:
--  - Lieferung in Zone:  +0.05 Bonus (max 2.0)
--  - Decay alle 10 Min:  -0.02 pro Zone (min 1.0)
--  - Kraftwerk-Boost:    +X auf alle Zonen
--  - Broadcast an alle Clients bei jeder Änderung
-- ============================================================

local TownBonusModule    = {}

-- Live-State: [zoneKey] = bonus (1.0 – 2.0)
local bonusTable         = {}

-- Konstanten aus Config (Fallbacks falls Config noch nicht gesetzt)
local BONUS_PER_DELIVERY = 0.05
local BONUS_DECAY_RATE   = 0.02
local BONUS_MIN          = 1.0
local BONUS_MAX          = 2.0
local DECAY_INTERVAL_MS  = 10 * 60 * 1000

-- ────────────────────────────────────────────────────────────
--  DB: Laden & Speichern
-- ────────────────────────────────────────────────────────────

local function GetBonusZones()
    local zones = {}
    for zoneName, zoneData in pairs(Config.Zones) do
        if zoneData.bonusZone and zoneData.zoneKey then
            zones[zoneData.zoneKey] = zoneName
        end
    end
    return zones
end

local function LoadBonuses(cb)
    -- Alle Bonus-Zonen aus Config sammeln
    local bonusZones = GetBonusZones()

    -- Mit 1.0 initialisieren
    for zoneKey, _ in pairs(bonusZones) do
        bonusTable[zoneKey] = 1.0
    end

    -- DB-Werte überschreiben
    MySQL.query("SELECT * FROM mt_town_bonus", {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                if bonusTable[row.zone_key] ~= nil then
                    bonusTable[row.zone_key] = tonumber(row.bonus) or 1.0
                end
            end
        end
        if cb then cb() end
    end)
end

local function SaveBonuses()
    for zoneKey, bonus in pairs(bonusTable) do
        MySQL.update(
            [[INSERT INTO mt_town_bonus (zone_key, bonus)
              VALUES (?, ?)
              ON DUPLICATE KEY UPDATE bonus = VALUES(bonus)]],
            { zoneKey, Utils.Round(bonus, 2) }
        )
    end
end

-- ────────────────────────────────────────────────────────────
--  Broadcast an alle Clients
-- ────────────────────────────────────────────────────────────

local function BroadcastBonuses()
    TriggerClientEvent(MT.BONUS_UPDATE, -1, bonusTable)
end

-- ────────────────────────────────────────────────────────────
--  Decay-Tick (alle 10 Min)
-- ────────────────────────────────────────────────────────────

local function RunDecayTick()
    local changed = false
    for zoneKey, bonus in pairs(bonusTable) do
        if bonus > BONUS_MIN then
            bonusTable[zoneKey] = Utils.Round(
                math.max(BONUS_MIN, bonus - BONUS_DECAY_RATE), 2
            )
            changed = true
        end
    end

    if changed then
        SaveBonuses()
        BroadcastBonuses()
    end
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

-- Wird von server/jobs.lua nach jeder Lieferung aufgerufen
function TownBonusModule.OnDelivery(deliveryZoneKey)
    -- deliveryZoneKey ist der Config.Zones-Key (z.B. "ablieferzone_supermarkt_north")
    -- Wir müssen herausfinden zu welcher Bonus-Zone das gehört

    -- Prüfe ob die Ablieferzone innerhalb einer Bonus-Zone liegt
    -- Vereinfachung: Zone-Namen-Match (z.B. "supermarkt_north" liegt in "downtown")
    local deliveryZone = Config.Zones[deliveryZoneKey]
    if not deliveryZone then return end

    -- Koordinaten der Ablieferzone holen
    local coords = deliveryZone.coords
    if not coords then return end

    -- Nearest Bonus-Zone finden
    local nearestKey  = nil
    local nearestDist = math.huge

    for zoneName, zoneData in pairs(Config.Zones) do
        if zoneData.bonusZone and zoneData.zoneKey and zoneData.points then
            -- Mittelpunkt der Poly-Zone berechnen
            local cx, cy = 0, 0
            for _, p in ipairs(zoneData.points) do
                cx = cx + p.x
                cy = cy + p.y
            end
            local n    = #zoneData.points
            local dist = Utils.Distance2D(
                coords,
                { x = cx / n, y = cy / n }
            )
            if dist < nearestDist then
                nearestDist = dist
                nearestKey  = zoneData.zoneKey
            end
        end
    end

    if nearestKey and bonusTable[nearestKey] then
        bonusTable[nearestKey] = Utils.Round(
            math.min(BONUS_MAX, bonusTable[nearestKey] + BONUS_PER_DELIVERY), 2
        )
        print(("[MT][Bonus] %s: %.2f (Lieferung +%.2f)"):format(
            nearestKey, bonusTable[nearestKey], BONUS_PER_DELIVERY
        ))
        SaveBonuses()
        BroadcastBonuses()
    end
end

-- Wird vom Kraftwerk-Sondereffekt aufgerufen
function TownBonusModule.BoostAll(amount)
    for zoneKey, bonus in pairs(bonusTable) do
        bonusTable[zoneKey] = Utils.Round(
            math.min(BONUS_MAX, bonus + amount), 2
        )
    end
    print(("[MT][Bonus] Kraftwerk-Boost: alle Zonen +%.2f"):format(amount))
    SaveBonuses()
    BroadcastBonuses()
end

function TownBonusModule.GetBonusTable()
    return bonusTable
end

function TownBonusModule.GetBonus(zoneKey)
    return bonusTable[zoneKey] or 1.0
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function TownBonusModule.Init()
    LoadBonuses(function()
        print("[MT][Bonus] Boni geladen:")
        for k, v in pairs(bonusTable) do
            print(("  %s: %.2fx"):format(k, v))
        end

        -- Decay-Loop starten
        SetInterval(RunDecayTick, DECAY_INTERVAL_MS)

        -- Neuen Spielern sofort Bonus-Table schicken
        AddEventHandler("playerJoining", function()
            local src = source
            SetTimeout(2000, function()
                TriggerClientEvent(MT.BONUS_UPDATE, src, bonusTable)
            end)
        end)
    end)

    exports("GetBonusTable", TownBonusModule.GetBonusTable)
    exports("GetBonus", TownBonusModule.GetBonus)

    print("[MT] TownBonusModule (Server) initialisiert")
end

_TownBonusModule = TownBonusModule
