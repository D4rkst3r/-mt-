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
    if PlayerModule.loaded then return end

    PlayerModule.data   = data
    PlayerModule.loaded = true

    -- Spieler an Spawn-Position setzen und aus Ladescreen holen
    -- spawnmanager übernimmt die Kontrolle über den eigentlichen Spawn-Vorgang
    exports.spawnmanager:spawnPlayer({
        x       = -1037.0,  -- Truck-Depot Startposition (aus Config.Zones anpassen)
        y       = -2731.0,
        z       = 20.0,
        heading = 0.0,
        model   = "mp_m_freemode_01",
    }, function()
        -- Lokaler Event mit EIGENEM Namen – NICHT MT.PLAYER_LOADED!
        TriggerEvent("mt:player:ready", data)

        lib.notify({
            title       = "Motor Town",
            description = ("Willkommen, %s! Level %d"):format(data.name, data.trucking_level),
            type        = "success",
            duration    = 5000,
        })
    end)
end

local function OnMoneyUpdate(cash, bank)
    if not PlayerModule.data then return end
    PlayerModule.data.money = cash
    PlayerModule.data.bank  = bank

    -- HUD-Modul informieren (über Event, nicht direkten Aufruf)
    TriggerEvent("mt:player:localMoneyUpdate", cash, bank)
end

local function OnXPUpdate(xp, level)
    if not PlayerModule.data then return end
    PlayerModule.data.trucking_xp    = xp
    PlayerModule.data.trucking_level = level
    TriggerEvent("mt:player:localXpUpdate", xp, level)
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
    -- RegisterNetEvent registriert den Handler für Server→Client Events.
    -- AddEventHandler würde denselben Handler ein zweites Mal binden
    -- und alle Callbacks doppelt feuern → hier NUR RegisterNetEvent.
    RegisterNetEvent(MT.PLAYER_LOADED, OnPlayerLoaded)
    RegisterNetEvent(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    RegisterNetEvent(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    RegisterNetEvent(MT.PLAYER_LEVEL_UP, OnLevelUp)

    exports("GetPlayerData", PlayerModule.GetData)
    exports("IsPlayerLoaded", PlayerModule.IsLoaded)
    exports("GetLevel", PlayerModule.GetLevel)
    exports("GetMoney", PlayerModule.GetMoney)

    print("[MT] PlayerModule (Client) initialisiert")
end

_PlayerModule = PlayerModule
