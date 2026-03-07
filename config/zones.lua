-- ============================================================
--  config/zones.lua
--  Alle Zonen-Definitionen für ox_lib zones + ox_target.
--
--  Zonentypen:
--    "box"    → lib.zones.box()    kleine Interaktionspunkte
--    "sphere" → lib.zones.sphere() runde Bereiche (Dealer, Werkstatt)
--    "poly"   → lib.zones.poly()   große Gebiete (Stadtteile, Hafen)
--
--  targets = Liste von Target-Keys, die in client/zones.lua
--            gegen Config.Targets[key] aufgelöst werden.
-- ============================================================

Config = Config or {}

Config.Zones = {

    -- --------------------------------------------------------
    --  DISPATCHER / JOB-VERGABE
    -- --------------------------------------------------------

    dispatcher_hafen = {
        type       = "box",
        coords     = vec3(836.8, -2991.3, 5.9),
        size       = vec3(4.0, 4.0, 2.0),
        rotation   = 0,
        label      = "Hafen Dispatcher",
        targets    = { "dispatcher_menu" },
        debugColor = { 0, 120, 255, 80 },
    },

    dispatcher_industriegebiet = {
        type       = "box",
        coords     = vec3(963.1, -2393.4, 30.6),
        size       = vec3(4.0, 4.0, 2.0),
        rotation   = 0,
        label      = "Industrie Dispatcher",
        targets    = { "dispatcher_menu" },
        debugColor = { 0, 120, 255, 80 },
    },

    dispatcher_stadtmitte = {
        type       = "box",
        coords     = vec3(213.7, -810.5, 30.7),
        size       = vec3(4.0, 4.0, 2.0),
        rotation   = 0,
        label      = "Stadtmitte Dispatcher",
        targets    = { "dispatcher_menu" },
        debugColor = { 0, 120, 255, 80 },
    },

    dispatcher_flughafen = {
        type       = "box",
        coords     = vec3(-1034.8, -2730.1, 20.2),
        size       = vec3(4.0, 4.0, 2.0),
        rotation   = 45,
        label      = "Flughafen Dispatcher",
        targets    = { "dispatcher_menu" },
        debugColor = { 0, 120, 255, 80 },
    },

    -- --------------------------------------------------------
    --  LADE- UND ABLIEFERZONEN
    -- --------------------------------------------------------

    ladezone_hafen_container = {
        type       = "box",
        coords     = vec3(825.2, -3000.1, 5.9),
        size       = vec3(12.0, 8.0, 3.0),
        rotation   = 0,
        label      = "Container laden",
        targets    = { "cargo_laden" },
        debugColor = { 255, 165, 0, 80 },
        jobType    = "container",
    },

    ladezone_holz = {
        type       = "box",
        coords     = vec3(1664.2, 3517.6, 35.8),
        size       = vec3(15.0, 10.0, 3.0),
        rotation   = 0,
        label      = "Holz laden",
        targets    = { "cargo_laden" },
        debugColor = { 255, 165, 0, 80 },
        jobType    = "holz",
    },

    ladezone_kohle = {
        type       = "box",
        coords     = vec3(2706.4, 1573.5, 24.6),
        size       = vec3(15.0, 10.0, 3.0),
        rotation   = 30,
        label      = "Kohle laden",
        targets    = { "cargo_laden" },
        debugColor = { 255, 165, 0, 80 },
        jobType    = "kohle",
    },

    ladezone_tank = {
        type       = "box",
        coords     = vec3(144.0, -1539.7, 29.3),
        size       = vec3(10.0, 6.0, 3.0),
        rotation   = 0,
        label      = "Tanker befüllen",
        targets    = { "cargo_laden" },
        debugColor = { 255, 165, 0, 80 },
        jobType    = "tank",
    },

    ladezone_muell = {
        type       = "box",
        coords     = vec3(-324.5, -1544.3, 27.7),
        size       = vec3(12.0, 8.0, 3.0),
        rotation   = 0,
        label      = "Müll aufnehmen",
        targets    = { "cargo_laden" },
        debugColor = { 255, 165, 0, 80 },
        jobType    = "muell",
    },

    ablieferzone_supermarkt_north = {
        type       = "box",
        coords     = vec3(-57.2, -1743.4, 29.4),
        size       = vec3(10.0, 6.0, 3.0),
        rotation   = 0,
        label      = "Supermarkt beliefern",
        targets    = { "cargo_abladen" },
        debugColor = { 0, 255, 80, 80 },
    },

    ablieferzone_supermarkt_east = {
        type       = "box",
        coords     = vec3(1166.3, -322.5, 69.2),
        size       = vec3(10.0, 6.0, 3.0),
        rotation   = 0,
        label      = "Supermarkt beliefern",
        targets    = { "cargo_abladen" },
        debugColor = { 0, 255, 80, 80 },
    },

    ablieferzone_kraftwerk = {
        type       = "box",
        coords     = vec3(2717.8, 1547.3, 24.6),
        size       = vec3(12.0, 8.0, 3.0),
        rotation   = 30,
        label      = "Kraftwerk beliefern",
        targets    = { "cargo_abladen" },
        debugColor = { 0, 255, 80, 80 },
    },

    -- --------------------------------------------------------
    --  FAHRZEUGHÄNDLER
    -- --------------------------------------------------------

    dealer_lkw = {
        type       = "sphere",
        coords     = vec3(-36.0, -1100.0, 26.4),
        radius     = 25.0,
        label      = "LKW Händler",
        targets    = { "dealer_menu" },
        debugColor = { 180, 0, 255, 60 },
    },

    dealer_spezial = {
        type       = "sphere",
        coords     = vec3(137.3, -1065.5, 29.2),
        radius     = 20.0,
        label      = "Spezialfahrzeuge",
        targets    = { "dealer_menu" },
        debugColor = { 180, 0, 255, 60 },
    },

    -- --------------------------------------------------------
    --  GARAGEN
    -- --------------------------------------------------------

    garage_hafen = {
        type         = "box",
        coords       = vec3(704.0, -2832.0, 6.0),
        spawnCoords  = vec3(710.0, -2832.0, 6.0), -- Straße vor der Garage
        spawnHeading = 270.0,
        size         = vec3(5.0, 5.0, 2.5),
        rotation     = 0,
        label        = "Garage (Hafen)",
        targets      = { "garage_menu" },
        debugColor   = { 255, 255, 0, 80 },
    },

    garage_industrie = {
        type         = "box",
        coords       = vec3(992.0, -2283.0, 29.0),
        spawnCoords  = vec3(998.0, -2283.0, 29.0), -- Straße vor der Garage
        spawnHeading = 270.0,
        size         = vec3(5.0, 5.0, 2.5),
        rotation     = 0,
        label        = "Garage (Industrie)",
        targets      = { "garage_menu" },
        debugColor   = { 255, 255, 0, 80 },
    },

    garage_stadtmitte = {
        type         = "box",
        coords       = vec3(215.7, -808.5, 30.7),
        spawnCoords  = vec3(215.7, -800.0, 30.7), -- Straße vor der Garage
        spawnHeading = 0.0,
        size         = vec3(5.0, 5.0, 2.5),
        rotation     = 0,
        label        = "Garage (Stadtmitte)",
        targets      = { "garage_menu" },
        debugColor   = { 255, 255, 0, 80 },
    },

    -- --------------------------------------------------------
    --  WERKSTÄTTEN
    -- --------------------------------------------------------

    werkstatt_hafen = {
        type       = "sphere",
        coords     = vec3(726.5, -2875.3, 6.1),
        radius     = 8.0,
        label      = "Werkstatt",
        targets    = { "werkstatt_menu" },
        debugColor = { 255, 60, 60, 70 },
    },

    werkstatt_north = {
        type       = "sphere",
        coords     = vec3(326.0, -204.8, 54.4),
        radius     = 8.0,
        label      = "Werkstatt",
        targets    = { "werkstatt_menu" },
        debugColor = { 255, 60, 60, 70 },
    },

    -- --------------------------------------------------------
    --  COMPANY BÜRO
    -- --------------------------------------------------------

    company_buero = {
        type       = "box",
        coords     = vec3(-135.3, -627.5, 168.9),
        size       = vec3(5.0, 4.0, 2.5),
        rotation   = 0,
        label      = "Firmen-Verwaltung",
        targets    = { "company_menu" },
        debugColor = { 0, 200, 200, 80 },
    },

    -- --------------------------------------------------------
    --  SUPPLY CHAIN – FABRIKEN
    -- --------------------------------------------------------

    fabrik_fleisch = {
        type       = "box",
        coords     = vec3(971.5, -2043.0, 30.7),
        size       = vec3(8.0, 6.0, 3.0),
        rotation   = 0,
        label      = "Fleischfabrik",
        targets    = { "fabrik_menu" },
        debugColor = { 200, 80, 80, 80 },
        factoryKey = "fleischfabrik",
    },

    fabrik_saegerei = {
        type       = "box",
        coords     = vec3(1634.7, 3519.2, 35.9),
        size       = vec3(8.0, 6.0, 3.0),
        rotation   = 0,
        label      = "Sägewerk",
        targets    = { "fabrik_menu" },
        debugColor = { 200, 80, 80, 80 },
        factoryKey = "saegerei",
    },

    -- --------------------------------------------------------
    --  STADTTEILE – PolyZones für Town Bonus
    --  ox_lib erwartet vector3[] – Z-Wert ist die Bodenhöhe
    -- --------------------------------------------------------

    stadt_downtown = {
        type      = "poly",
        points    = {
            vec3(-800.0, -600.0, 30.0),
            vec3(200.0, -600.0, 30.0),
            vec3(200.0, 300.0, 30.0),
            vec3(-800.0, 300.0, 30.0),
        },
        thickness = 80.0,
        label     = "Downtown LS",
        bonusZone = true,
        zoneKey   = "downtown",
    },

    stadt_hafen = {
        type      = "poly",
        points    = {
            vec3(500.0, -3300.0, 6.0),
            vec3(1200.0, -3300.0, 6.0),
            vec3(1200.0, -2500.0, 6.0),
            vec3(500.0, -2500.0, 6.0),
        },
        thickness = 80.0,
        label     = "Hafenviertel",
        bonusZone = true,
        zoneKey   = "hafen",
    },

    stadt_industriegebiet = {
        type      = "poly",
        points    = {
            vec3(600.0, -2500.0, 30.0),
            vec3(1400.0, -2500.0, 30.0),
            vec3(1400.0, -1600.0, 30.0),
            vec3(600.0, -1600.0, 30.0),
        },
        thickness = 80.0,
        label     = "Industriegebiet",
        bonusZone = true,
        zoneKey   = "industriegebiet",
    },

    stadt_sandy = {
        type      = "poly",
        points    = {
            vec3(1700.0, 3300.0, 30.0),
            vec3(2600.0, 3300.0, 30.0),
            vec3(2600.0, 4200.0, 30.0),
            vec3(1700.0, 4200.0, 30.0),
        },
        thickness = 80.0,
        label     = "Sandy Shores",
        bonusZone = true,
        zoneKey   = "sandy",
    },

    stadt_paleto = {
        type      = "poly",
        points    = {
            vec3(-950.0, 5500.0, 30.0),
            vec3(-100.0, 5500.0, 30.0),
            vec3(-100.0, 6200.0, 30.0),
            vec3(-950.0, 6200.0, 30.0),
        },
        thickness = 80.0,
        label     = "Paleto Bay",
        bonusZone = true,
        zoneKey   = "paleto",
    },
}

-- ────────────────────────────────────────────────────────────
--  ox_target Aktions-Definitionen
--  Jeder Key entspricht einem targets[]-Eintrag oben.
--  "event" wird als lokales Event gefeuert wenn der Spieler
--  die Aktion auswählt.
-- ────────────────────────────────────────────────────────────
Config.Targets = {

    dispatcher_menu = {
        {
            name  = "mt_dispatcher_open",
            label = "Jobs ansehen",
            icon  = "fas fa-clipboard-list",
            event = "mt:ui:openDispatcher",
        },
    },

    cargo_laden = {
        {
            name  = "mt_cargo_load",
            label = "Cargo laden",
            icon  = "fas fa-dolly",
            event = "mt:job:startLoad",
        },
    },

    cargo_abladen = {
        {
            name  = "mt_cargo_unload",
            label = "Cargo abliefern",
            icon  = "fas fa-box-open",
            event = "mt:job:startUnload",
        },
    },

    dealer_menu = {
        {
            name  = "mt_dealer_open",
            label = "Fahrzeuge kaufen",
            icon  = "fas fa-truck",
            event = "mt:ui:openDealer",
        },
    },

    garage_menu = {
        {
            name  = "mt_garage_fahrzeug",
            label = "Fahrzeug holen",
            icon  = "fas fa-car-side",
            event = "mt:vehicle:retrieveFromGarage",
        },
        {
            name  = "mt_garage_einlagern",
            label = "Fahrzeug einlagern",
            icon  = "fas fa-warehouse",
            event = "mt:vehicle:storeToGarage",
        },
    },

    werkstatt_menu = {
        {
            name  = "mt_werkstatt_reparieren",
            label = "Fahrzeug reparieren",
            icon  = "fas fa-wrench",
            event = "mt:vehicle:repair",
        },
        {
            name  = "mt_werkstatt_upgrades",
            label = "Upgrades kaufen",
            icon  = "fas fa-cogs",
            event = "mt:ui:openUpgrades",
        },
    },

    company_menu = {
        {
            name  = "mt_company_open",
            label = "Firmen-Verwaltung",
            icon  = "fas fa-building",
            event = "mt:ui:openCompany",
        },
    },

    fabrik_menu = {
        {
            name  = "mt_fabrik_status",
            label = "Fabrikstatus ansehen",
            icon  = "fas fa-industry",
            event = "mt:supply:openFactory",
        },
    },
}
