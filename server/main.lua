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
    -- Kurze Wartezeit bis oxmysql bereit ist
    Wait(1000)

    _PlayerModule.Init()
    _VehicleModule.Init()
    _JobModule.Init()
    _CompanyModule.Init()
    _SupplyChainModule.Init()
    _TownBonusModule.Init()

    print("[MT] ✓ Alle Server-Module gestartet")
end)
