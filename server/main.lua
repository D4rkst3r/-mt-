-- ============================================================
--  server/main.lua
--  Bootstrap: initialisiert alle Server-Module in der
--  richtigen Reihenfolge. Keine Logik hier.
--
--  Reihenfolge ist relevant:
--  1. PlayerModule zuerst (andere Module brauchen GetPlayerData)
--  2. VehicleModule braucht PlayerModule (Ownership-Check)
--  3. JobModule braucht PlayerModule + VehicleModule
--  4. Rest kann parallel
-- ============================================================

CreateThread(function()
    Wait(1000)

    -- AdminModule zuerst: lädt Admin-Cache UND Config-Overrides aus DB
    -- Alle anderen Module starten erst danach, damit sie die überschriebene Config sehen
    _AdminModule.Init(function()
        _PlayerModule.Init()
        _VehicleModule.Init()
        _JobModule.Init()
        _CompanyModule.Init()
        _CargoModule.Init() -- NEU: Item-Cargo-System
        _SupplyChainModule.Init()
        _TownBonusModule.Init()

        print("[MT] ✓ Alle Server-Module gestartet")
    end)
end)

-- ────────────────────────────────────────────────────────────
--  Admin-Befehle (nur Serverkonsole / Ace-Permission)
--  Verwendung in der txAdmin/Server-Konsole:
--    mt_givemoney <playerID> <betrag>
--    mt_givexp    <playerID> <xp>
--    mt_setlevel  <playerID> <level>
-- ────────────────────────────────────────────────────────────

RegisterCommand("mt_givemoney", function(source, args)
    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    if not targetId or not amount then
        print("[MT] Verwendung: mt_givemoney <playerID> <betrag>")
        return
    end
    _PlayerModule.AddMoney(targetId, amount, "Admin: Geld erhalten")
    print(("[MT] %d$ an Spieler %d gegeben"):format(amount, targetId))
end, true)

RegisterCommand("mt_givexp", function(source, args)
    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    if not targetId or not amount then
        print("[MT] Verwendung: mt_givexp <playerID> <xp>")
        return
    end
    _PlayerModule.AddXP(targetId, amount)
    print(("[MT] %d XP an Spieler %d gegeben"):format(amount, targetId))
end, true)

RegisterCommand("mt_setlevel", function(source, args)
    local targetId = tonumber(args[1])
    local level    = tonumber(args[2])
    if not targetId or not level then
        print("[MT] Verwendung: mt_setlevel <playerID> <level>")
        return
    end
    local data = _PlayerModule.GetData(targetId)
    if not data then
        print("[MT] Spieler nicht gefunden")
        return
    end
    local xpNeeded = Utils.XPForLevel(level)
    MySQL.update(
        "UPDATE mt_players SET trucking_level = ?, trucking_xp = ? WHERE identifier = ?",
        { level, xpNeeded, data.identifier }
    )
    TriggerClientEvent(MT.PLAYER_LEVEL_UP, targetId, { level = level, xp = xpNeeded })
    print(("[MT] Spieler %d auf Level %d gesetzt"):format(targetId, level))
end, true)

-- ────────────────────────────────────────────────────────────
--  Resource Stop: alle gespawnten Fahrzeuge zurück in Garage
-- ────────────────────────────────────────────────────────────

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    -- Alle Fahrzeuge die als "draußen" (stored=0) markiert sind
    -- werden zurückgesetzt, damit Spieler sie nach Neustart holen können
    MySQL.update(
        "UPDATE mt_vehicles SET `stored` = 1 WHERE `stored` = 0",
        {},
        function(affected)
            print(("[MT] onResourceStop: %d Fahrzeug(e) automatisch eingelagert"):format(affected or 0))
        end
    )

    -- Jobs leben nur im Memory (activeJobs in jobs.lua), kein DB-Cleanup nötig
end)
