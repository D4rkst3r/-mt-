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

    -- Spawn in eigenem Thread
    CreateThread(function()
        exports.spawnmanager:setAutoSpawn(false)

        local spawnCoords  = vec3(213.7, -810.5, 30.7)
        local spawnHeading = 0.0
        local modelName    = "mp_m_freemode_01"
        local modelHash    = GetHashKey(modelName)

        -- 1. Model laden und warten
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) do
            Wait(100)
            timeout = timeout + 1
            if timeout > 50 then
                print("[MT] WARNUNG: Model " .. modelName .. " Timeout")
                break
            end
        end

        -- 2. Spieler-Model setzen
        SetPlayerModel(PlayerId(), modelHash)
        SetPedDefaultComponentVariation(PlayerPedId())
        SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)
        SetModelAsNoLongerNeeded(modelHash)

        -- 3. Zur Spawn-Position teleportieren
        local ped = PlayerPedId()
        SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, false)
        SetEntityHeading(ped, spawnHeading)
        Wait(200)

        -- 4. Ladebildschirm schließen (beide Varianten für Kompatibilität)
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()

        -- 5. Sichtbarkeit sicherstellen
        SetEntityVisible(ped, true, false)
        SetEntityAlpha(ped, 255, false)
        FreezeEntityPosition(ped, false)
        NetworkSetEntityInvisibleToNetwork(ped, false)

        -- 6. Fertig
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
    RegisterNetEvent(MT.PLAYER_LOADED, OnPlayerLoaded)
    RegisterNetEvent(MT.PLAYER_MONEY_UPDATE, OnMoneyUpdate)
    RegisterNetEvent(MT.PLAYER_XP_UPDATE, OnXPUpdate)
    RegisterNetEvent(MT.PLAYER_LEVEL_UP, OnLevelUp)

    exports("GetPlayerData", PlayerModule.GetData)
    exports("IsPlayerLoaded", PlayerModule.IsLoaded)
    exports("GetLevel", PlayerModule.GetLevel)
    exports("GetMoney", PlayerModule.GetMoney)

    -- Server nach Daten fragen
    TriggerServerEvent("mt:player:requestLoad")

    -- Fallback: Falls PLAYER_LOADED nach 10s noch nicht kam → nochmal anfragen
    -- (passiert wenn Server-DB beim ersten Request noch nicht bereit war)
    CreateThread(function()
        Wait(10000)
        if not PlayerModule.loaded then
            print("[MT] WARNUNG: PLAYER_LOADED nicht empfangen – zweiter Versuch")
            TriggerServerEvent("mt:player:requestLoad")

            -- Letzter Ausweg nach 20s: Loading Screen trotzdem schließen
            Wait(10000)
            if not PlayerModule.loaded then
                print("[MT] FEHLER: PLAYER_LOADED nie empfangen – erzwinge ShutdownLoadingScreen")
                ShutdownLoadingScreen()
                ShutdownLoadingScreenNui()
            end
        end
    end)

    print("[MT] PlayerModule (Client) initialisiert")
end

_PlayerModule = PlayerModule
