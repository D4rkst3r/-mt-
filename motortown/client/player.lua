-- ============================================================
--  client/player.lua
--  Verantwortlich für: lokalen Spielerdaten-Cache,
--  Reaktion auf Server-Updates (Geld, XP, Level).
--
--  Schreibt NIEMALS direkt in die DB – sendet Events an Server.
-- ============================================================

local PlayerModule = {}

-- Lokaler Cache – wird beim Login vom Server befüllt
PlayerModule.data = nil
PlayerModule.loaded = false

-- ────────────────────────────────────────────────────────────
--  Öffentliche API (für andere Client-Module via exports)
-- ────────────────────────────────────────────────────────────

function PlayerModule.GetData()
    return PlayerModule.data
end

function PlayerModule.IsLoaded()
    return PlayerModule.loaded
end

function PlayerModule.GetLevel()
    if not PlayerModule.data then return 1 end
    return PlayerModule.data.trucking_level
end

function PlayerModule.GetMoney()
    if not PlayerModule.data then return 0 end
    return PlayerModule.data.money
end

-- ────────────────────────────────────────────────────────────
--  Event-Handler
-- ────────────────────────────────────────────────────────────

local function OnPlayerLoaded(data)
    PlayerModule.data   = data
    PlayerModule.loaded = true

    -- Andere Module über fertigen Ladezustand informieren
    TriggerEvent(MT.PLAYER_LOADED, data)

    -- Willkommensnachricht via ox_lib notify
    lib.notify({
        title       = "Motor Town",
        description = ("Willkommen, %s! Level %d"):format(data.name, data.trucking_level),
        type        = "success",
        duration    = 5000,
    })
end

local function OnMoneyUpdate(cash, bank)
    if not PlayerModule.data then return end
    PlayerModule.data.money = cash
    PlayerModule.data.bank  = bank

    -- HUD-Modul informieren (über Event, nicht direkten Aufruf)
    TriggerEvent(MT.PLAYER_MONEY_UPDATE, cash, bank)
end

local function OnXPUpdate(xp, level)
    if not PlayerModule.data then return end
    PlayerModule.data.trucking_xp    = xp
    PlayerModule.data.trucking_level = level
    TriggerEvent(MT.PLAYER_XP_UPDATE, xp, level)
end

local function OnLevelUp(newLevel)
    if not PlayerModule.data then return end
    PlayerModule.data.trucking_level = newLevel

    -- Großes Level-Up Feedback
    lib.notify({
        title       = "🎉 Level Up!",
        description = ("Du bist jetzt Level %d – neue Jobs verfügbar!"):format(newLevel),
        type        = "success",
        duration    = 8000,
    })

    TriggerEvent(MT.PLAYER_LEVEL_UP, newLevel)
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function PlayerModule.Init()
    RegisterNetEvent(MT.PLAYER_LOADED, OnPlayerLoaded)
    RegisterNetEvent(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    RegisterNetEvent(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    RegisterNetEvent(MT.PLAYER_LEVEL_UP, OnLevelUp)

    AddEventHandler(MT.PLAYER_LOADED, OnPlayerLoaded)
    AddEventHandler(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    AddEventHandler(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    AddEventHandler(MT.PLAYER_LEVEL_UP, OnLevelUp)

    exports("GetPlayerData", PlayerModule.GetData)
    exports("IsPlayerLoaded", PlayerModule.IsLoaded)
    exports("GetLevel", PlayerModule.GetLevel)
    exports("GetMoney", PlayerModule.GetMoney)

    print("[MT] Client PlayerModule initialisiert")
end

_PlayerModule = PlayerModule
