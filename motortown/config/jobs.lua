-- ============================================================
--  config/jobs.lua
--  Alle Job-Typen mit Lohn, Level-Anforderungen,
--  Fahrzeug-Typ-Anforderungen und Cargo-Definitionen.
--
--  vehicleType-Keys müssen mit Config.VehicleTypes in
--  config/vehicles.lua übereinstimmen.
--
--  ladezone / ablieferzonen sind Keys aus Config.Zones.
-- ============================================================

Config                  = Config or {}

-- Wie viel XP ein Job pro Kilometer einbringt (Basis)
Config.XPPerKm          = 10
Config.XPBaseDelivery   = 50 -- Fixbonus pro Ablieferung
Config.MaxJobDistance   = 80.0 -- Meter: wie nah muss Spieler an Zielzone sein?
Config.LoadProgressMs   = 5000 -- Millisekunden für Lade-Progressbar
Config.UnloadProgressMs = 4000

Config.Jobs             = {

    -- --------------------------------------------------------
    --  CONTAINERTRANSPORT  (Level 1 – Einstiegs-Job)
    -- --------------------------------------------------------
    container = {
        label         = "Containertransport",
        description   = "Transportiere Seefracht-Container vom Hafen zu Lagerhallen.",
        minLevel      = 1,
        vehicleType   = "semi",
        baseWage      = 3500,
        wagePerKm     = 100,
        wagePerTon    = 60,
        timeBonus     = true, -- Zeitbonus wenn schnell geliefert
        timeLimitMin  = 30,  -- Minuten bis Zeitbonus verfällt
        cargo         = {
            item   = "container",
            label  = "Seecontainer",
            weight = 8000,   -- kg (für wagePerTon-Berechnung)
            amount = 1,
        },
        -- Mögliche Abholzonen (wird zufällig gewählt)
        pickupZones   = { "ladezone_hafen_container" },
        -- Mögliche Ablieferzonen (wird zufällig gewählt)
        deliveryZones = {
            "ablieferzone_supermarkt_north",
            "ablieferzone_supermarkt_east",
        },
        -- Wegpunkt-Blip-Farbe (GTA blip color ID)
        blipColor     = 3,
        blipSprite    = 477,
    },

    -- --------------------------------------------------------
    --  HOLZTRANSPORT  (Level 3)
    -- --------------------------------------------------------
    holz = {
        label         = "Holztransport",
        description   = "Frisch geschlagenes Holz vom Sägewerk zur Verarbeitungsfabrik.",
        minLevel      = 3,
        vehicleType   = "flatbed",
        baseWage      = 4000,
        wagePerKm     = 110,
        wagePerTon    = 70,
        timeBonus     = true,
        timeLimitMin  = 25,
        cargo         = {
            item   = "holzladung",
            label  = "Holzstämme",
            weight = 12000,
            amount = 1,
        },
        pickupZones   = { "ladezone_holz" },
        deliveryZones = { "fabrik_saegerei" },
        blipColor     = 52,
        blipSprite    = 478,
    },

    -- --------------------------------------------------------
    --  KOHLETRANSPORT  (Level 5)
    -- --------------------------------------------------------
    kohle = {
        label         = "Kohletransport",
        description   = "Kohle aus dem Tagebau zum Kraftwerk liefern.",
        minLevel      = 5,
        vehicleType   = "kipper",
        baseWage      = 4500,
        wagePerKm     = 115,
        wagePerTon    = 75,
        timeBonus     = false,
        cargo         = {
            item   = "kohle",
            label  = "Kohleladung",
            weight = 20000,
            amount = 1,
        },
        pickupZones   = { "ladezone_kohle" },
        deliveryZones = { "ablieferzone_kraftwerk" },
        blipColor     = 0,
        blipSprite    = 479,
    },

    -- --------------------------------------------------------
    --  TANKERTRANSPORT  (Level 8)
    -- --------------------------------------------------------
    tank = {
        label         = "Tankertransport",
        description   = "Gefahrgut – Kraftstoff zu Tankstellen und Flughafen liefern.",
        minLevel      = 8,
        vehicleType   = "tanker",
        baseWage      = 6000,
        wagePerKm     = 140,
        wagePerTon    = 90,
        timeBonus     = true,
        timeLimitMin  = 20,
        -- Gefahrgut-Bonus: +20% auf Basislohn
        dangerBonus   = 1.20,
        cargo         = {
            item   = "kraftstoff",
            label  = "Kraftstofftank",
            weight = 25000,
            amount = 1,
        },
        pickupZones   = { "ladezone_tank" },
        deliveryZones = {
            "ablieferzone_supermarkt_north",
            "dispatcher_flughafen",
        },
        blipColor     = 1,
        blipSprite    = 480,
    },

    -- --------------------------------------------------------
    --  MÜLLABFUHR  (Level 2)
    -- --------------------------------------------------------
    muell = {
        label         = "Müllabfuhr",
        description   = "Müllcontainer aus Wohngebieten zur Deponie bringen.",
        minLevel      = 2,
        vehicleType   = "garbage",
        baseWage      = 2500,
        wagePerKm     = 80,
        wagePerTon    = 50,
        timeBonus     = false,
        -- Mehrere Stopps – Cargo wird an mehreren Punkten geladen
        multiStop     = true,
        stopCount     = 3,
        cargo         = {
            item   = "muell",
            label  = "Müllladung",
            weight = 5000,
            amount = 3, -- pro Stop eines
        },
        pickupZones   = { "ladezone_muell" },
        deliveryZones = { "ablieferzone_supermarkt_north" },
        blipColor     = 40,
        blipSprite    = 481,
    },

    -- --------------------------------------------------------
    --  LEBENSMITTELTRANSPORT  (Level 4)
    -- --------------------------------------------------------
    lebensmittel = {
        label         = "Lebensmittellieferung",
        description   = "Kühlware pünktlich zu Supermärkten und Restaurants liefern.",
        minLevel      = 4,
        vehicleType   = "refrigerated",
        baseWage      = 4800,
        wagePerKm     = 120,
        wagePerTon    = 80,
        timeBonus     = true,
        timeLimitMin  = 20,
        -- Qualitätsbonus: wenn unter Zeitlimit → +15%
        qualityBonus  = 1.15,
        cargo         = {
            item   = "lebensmittel",
            label  = "Kühlcontainer",
            weight = 6000,
            amount = 1,
        },
        pickupZones   = { "fabrik_fleisch" },
        deliveryZones = {
            "ablieferzone_supermarkt_north",
            "ablieferzone_supermarkt_east",
        },
        blipColor     = 69,
        blipSprite    = 482,
    },

    -- --------------------------------------------------------
    --  SCHWERTRANSPORT  (Level 15 – High-End Job)
    -- --------------------------------------------------------
    schwer = {
        label          = "Schwertransport",
        description    = "Überbreite Maschinen mit Polizeibegleitung durch die Stadt.",
        minLevel       = 15,
        vehicleType    = "heavyhaul",
        baseWage       = 12000,
        wagePerKm      = 220,
        wagePerTon     = 130,
        timeBonus      = false,
        -- Escort-Fahrzeug muss dabei sein (Company-Feature)
        requiresEscort = false, -- aktuell optional
        cargo          = {
            item   = "schwerlast",
            label  = "Schwerlastgut",
            weight = 40000,
            amount = 1,
        },
        pickupZones    = { "dispatcher_industriegebiet" },
        deliveryZones  = { "ablieferzone_kraftwerk" },
        blipColor      = 49,
        blipSprite     = 477,
    },
}

-- ────────────────────────────────────────────────────────────
--  Lohn-Berechnungs-Formel (zur Dokumentation)
--
--  rawWage = baseWage
--           + (distanzKm * wagePerKm)
--           + (gewichtTon * wagePerTon)
--
--  finalWage = rawWage
--             * townBonus          (1.0 – 2.0)
--             * zeitMultiplikator  (1.0 – 1.3, wenn timeBonus)
--             * dangerBonus        (nur tank: 1.2)
--             * qualityBonus       (nur lebensmittel: 1.15)
-- ────────────────────────────────────────────────────────────
