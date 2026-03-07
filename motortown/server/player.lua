-- ============================================================
--  server/player.lua
--  Verantwortlich für: Laden/Speichern von Spielerdaten,
--  Geld-Transaktionen, XP & Level-Ups.
--
--  Kommunikation nach außen NUR über Events oder exports.
--  Interner State: PlayerModule.cache (source → data)
-- ============================================================

local PlayerModule = {}

-- Live-Cache aller verbundenen Spieler: [source] = playerData
PlayerModule.cache = {}

-- ────────────────────────────────────────────────────────────
--  Interne Helfer
-- ────────────────────────────────────────────────────────────

local function GetIdentifier(source)
    for _, v in ipairs(GetPlayerIdentifiers(source)) do
        if v:sub(1, 8) == "license:" then
            return v
        end
    end
    return nil
end

local function DefaultPlayerData(identifier, name)
    return {
        identifier       = identifier,
        name             = name,
        money            = 500,
        bank             = 2000,
        trucking_level   = 1,
        trucking_xp      = 0,
        total_deliveries = 0,
        total_earned     = 0,
    }
end

-- Schreibt eine Zeile in mt_transactions (fire-and-forget)
local function LogTransaction(identifier, amount, txType, reason)
    MySQL.insert(
        "INSERT INTO mt_transactions (identifier, amount, type, reason) VALUES (?,?,?,?)",
        { identifier, amount, txType, reason }
    )
end

-- ────────────────────────────────────────────────────────────
--  Lade / Speichere
-- ────────────────────────────────────────────────────────────

local function LoadPlayer(source)
    local identifier = GetIdentifier(source)
    if not identifier then
        DropPlayer(source, "Kein gültiger License-Identifier.")
        return
    end

    local name = GetPlayerName(source) or "Unknown"

    MySQL.single(
        "SELECT * FROM mt_players WHERE identifier = ?",
        { identifier },
        function(row)
            local data
            if row then
                data = {
                    identifier       = row.identifier,
                    name             = name,
                    money            = row.money,
                    bank             = row.bank,
                    trucking_level   = row.trucking_level,
                    trucking_xp      = row.trucking_xp,
                    total_deliveries = row.total_deliveries,
                    total_earned     = row.total_earned,
                }
                -- Name immer aktualisieren
                MySQL.update(
                    "UPDATE mt_players SET name=?, last_seen=NOW() WHERE identifier=?",
                    { name, identifier }
                )
            else
                data = DefaultPlayerData(identifier, name)
                MySQL.insert(
                    [[INSERT INTO mt_players
                      (identifier,name,money,bank,trucking_level,trucking_xp,
                       total_deliveries,total_earned)
                      VALUES (?,?,?,?,?,?,?,?)]],
                    { data.identifier, data.name, data.money, data.bank,
                        data.trucking_level, data.trucking_xp,
                        data.total_deliveries, data.total_earned }
                )
            end

            PlayerModule.cache[source] = data
            TriggerClientEvent(MT.PLAYER_LOADED, source, data)
        end
    )
end

local function SavePlayer(source)
    local data = PlayerModule.cache[source]
    if not data then return end

    MySQL.update(
        [[UPDATE mt_players
          SET money=?, bank=?, trucking_level=?, trucking_xp=?,
              total_deliveries=?, total_earned=?, last_seen=NOW()
          WHERE identifier=?]],
        { data.money, data.bank, data.trucking_level, data.trucking_xp,
            data.total_deliveries, data.total_earned, data.identifier }
    )
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API (via exports und Events)
-- ────────────────────────────────────────────────────────────

function PlayerModule.GetData(source)
    return PlayerModule.cache[source]
end

-- Alle Geldoperationen laufen hier durch – niemals direkt cache manipulieren
function PlayerModule.AddMoney(source, amount, reason)
    local data = PlayerModule.cache[source]
    if not data or amount <= 0 then return false end

    data.money = data.money + amount
    data.total_earned = data.total_earned + amount
    LogTransaction(data.identifier, amount, "cash", reason or "")
    TriggerClientEvent(MT.PLAYER_MONEY_UPDATE, source, data.money, data.bank)
    return true
end

function PlayerModule.RemoveMoney(source, amount, reason)
    local data = PlayerModule.cache[source]
    if not data or amount <= 0 then return false end
    if data.money < amount then return false end -- kein Minus-Geld

    data.money = data.money - amount
    LogTransaction(data.identifier, -amount, "cash", reason or "")
    TriggerClientEvent(MT.PLAYER_MONEY_UPDATE, source, data.money, data.bank)
    return true
end

function PlayerModule.GetMoney(source)
    local data = PlayerModule.cache[source]
    return data and data.money or 0
end

-- XP hinzufügen; gibt true zurück wenn Level-Up
function PlayerModule.AddXP(source, amount)
    local data = PlayerModule.cache[source]
    if not data then return false end

    data.trucking_xp = data.trucking_xp + amount
    local needed = Utils.XPForLevel(data.trucking_level + 1)

    if data.trucking_xp >= needed then
        data.trucking_level = data.trucking_level + 1
        data.trucking_xp    = data.trucking_xp - needed
        TriggerClientEvent(MT.PLAYER_LEVEL_UP, source, data.trucking_level)
    end

    TriggerClientEvent(MT.PLAYER_XP_UPDATE, source, data.trucking_xp, data.trucking_level)
    return true
end

function PlayerModule.IncrementDeliveries(source)
    local data = PlayerModule.cache[source]
    if data then
        data.total_deliveries = data.total_deliveries + 1
    end
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function PlayerModule.Init()
    -- Spieler verbindet sich
    AddEventHandler("playerConnecting", function(name, _, d)
        -- Validierung (Platzhalter – hier z.B. Bans prüfbar)
        d.done()
    end)

    AddEventHandler("playerJoining", function()
        local source = source      -- Closures brauchen lokale Kopie
        SetTimeout(500, function() -- kurze Verzögerung für Identifier-Verfügbarkeit
            LoadPlayer(source)
        end)
    end)

    -- Spieler trennt sich: speichern & aus Cache entfernen
    AddEventHandler("playerDropped", function()
        local source = source
        SavePlayer(source)
        PlayerModule.cache[source] = nil
    end)

    -- Periodisches Speichern alle 5 Minuten (crash-safety)
    SetInterval(function()
        for src, _ in pairs(PlayerModule.cache) do
            SavePlayer(src)
        end
    end, 5 * 60 * 1000)

    -- Exports für andere Server-Module
    exports("GetPlayerData", PlayerModule.GetData)
    exports("AddMoney", PlayerModule.AddMoney)
    exports("RemoveMoney", PlayerModule.RemoveMoney)
    exports("GetMoney", PlayerModule.GetMoney)
    exports("AddXP", PlayerModule.AddXP)
    exports("IncrementDeliveries", PlayerModule.IncrementDeliveries)

    print("[MT] PlayerModule initialisiert")
end

-- Modul nach außen zugänglich machen (für server/main.lua)
_PlayerModule = PlayerModule
