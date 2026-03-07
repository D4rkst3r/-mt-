-- ============================================================
--  client/main.lua
--  Bootstrap: initialisiert alle Client-Module.
--
--  PlayerModule immer zuerst – es definiert ob der Spieler
--  "geladen" ist. Andere Module können darauf warten via:
--    if not exports['motortown']:IsPlayerLoaded() then return end
-- ============================================================

AddEventHandler("onClientResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    -- Kurz warten bis ox_lib & ox_target bereit sind
    Wait(500)

    _PlayerModule.Init()
    _ZoneModule.Init()
    _JobModule.Init()
    _VehicleModule.Init()
    _CompanyModule.Init()
    _SupplyChainModule.Init()
    _TownBonusModule.Init()
    _HudModule.Init()

    print("[MT] ✓ Alle Client-Module gestartet")
end)
