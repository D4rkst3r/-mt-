-- ============================================================
--  config/vehicles.lua
--  Fahrzeugmodelle, Typen, Kaufpreise und Upgrade-Werte.
--
--  VehicleTypes: Maps jobType → Liste von GTA-Modellnamen
--  Vehicles:     Kaufbare Fahrzeuge mit Preis und Typ
--  Upgrades:     HandlingField-basierte Upgrade-Stufen
-- ============================================================

Config                      = Config or {}

-- ────────────────────────────────────────────────────────────
--  Fahrzeugtypen – müssen mit Config.Jobs[x].vehicleType matchen
-- ────────────────────────────────────────────────────────────
Config.VehicleTypes         = {
    semi         = { "phantom", "phantom2", "hauler", "hauler2" },
    flatbed      = { "flatbed", "flatbed2" },
    kipper       = { "dump", "tipper", "tipper2" },
    tanker       = { "tanker", "tanker2" },
    garbage      = { "trash", "trash2" },
    refrigerated = { "mule", "mule2", "mule3", "mule4",
        "mule5" },
    heavyhaul    = { "cargobob", "handler" },
}

-- ────────────────────────────────────────────────────────────
--  Kaufbare Fahrzeuge (Dealer)
-- ────────────────────────────────────────────────────────────
Config.Vehicles             = {

    -- SEMI / SATTELZUG ------------------------------------------
    phantom = {
        label       = "Jobuilt Phantom",
        model       = "phantom",
        vehicleType = "semi",
        price       = 80000,
        minLevel    = 1,
        description = "Klassischer Sattelzug – solide Allzwecklösung.",
        category    = "semi",
    },
    phantom2 = {
        label       = "Jobuilt Phantom Custom",
        model       = "phantom2",
        vehicleType = "semi",
        price       = 135000,
        minLevel    = 5,
        description = "Verbesserte Version mit mehr Zugkraft.",
        category    = "semi",
    },
    hauler = {
        label       = "Jobuilt Hauler",
        model       = "hauler",
        vehicleType = "semi",
        price       = 95000,
        minLevel    = 3,
        description = "Robuster Arbeitstier für lange Strecken.",
        category    = "semi",
    },
    hauler2 = {
        label       = "Jobuilt Hauler Custom",
        model       = "hauler2",
        vehicleType = "semi",
        price       = 160000,
        minLevel    = 8,
        description = "Hochleistungs-Sattelzug mit verstärktem Rahmen.",
        category    = "semi",
    },

    -- FLATBED / TIEFLADER ---------------------------------------
    flatbed = {
        label       = "MTL Flatbed",
        model       = "flatbed",
        vehicleType = "flatbed",
        price       = 55000,
        minLevel    = 3,
        description = "Offene Ladefläche für Holz und Maschinen.",
        category    = "flatbed",
    },
    flatbed2 = {
        label       = "MTL Flatbed XL",
        model       = "flatbed2",
        vehicleType = "flatbed",
        price       = 85000,
        minLevel    = 6,
        description = "Verlängerte Ladefläche für Schwertransporte.",
        category    = "flatbed",
    },

    -- KIPPER / MULDENKIPPER -------------------------------------
    dump = {
        label       = "Jobuilt S-95",
        model       = "dump",
        vehicleType = "kipper",
        price       = 75000,
        minLevel    = 5,
        description = "Großer Muldenkipper für Tagebau-Einsätze.",
        category    = "kipper",
    },
    tipper = {
        label       = "HVY Tipper",
        model       = "tipper",
        vehicleType = "kipper",
        price       = 60000,
        minLevel    = 4,
        description = "Kompakter Kipper für Kohle und Schüttgut.",
        category    = "kipper",
    },

    -- TANKER ---------------------------------------------------
    tanker = {
        label       = "MTL Tanker",
        model       = "tanker",
        vehicleType = "tanker",
        price       = 110000,
        minLevel    = 8,
        description = "Gefahrguttransporter – Sicherheitstraining erforderlich.",
        category    = "tanker",
    },
    tanker2 = {
        label       = "MTL Tanker LNG",
        model       = "tanker2",
        vehicleType = "tanker",
        price       = 145000,
        minLevel    = 12,
        description = "Doppelkammer-Tanker für maximale Zuladung.",
        category    = "tanker",
    },

    -- MÜLLFAHRZEUG ---------------------------------------------
    trash = {
        label       = "Jobuilt Trashmaster",
        model       = "trash",
        vehicleType = "garbage",
        price       = 45000,
        minLevel    = 2,
        description = "Kompaktes Müllfahrzeug für die städtische Müllabfuhr.",
        category    = "garbage",
    },
    trash2 = {
        label       = "Jobuilt Trashmaster XL",
        model       = "trash2",
        vehicleType = "garbage",
        price       = 65000,
        minLevel    = 5,
        description = "Größere Kapazität, weniger Stopps nötig.",
        category    = "garbage",
    },

    -- KÜHLFAHRZEUG ---------------------------------------------
    mule4 = {
        label       = "Bravado Mule (Kühlung)",
        model       = "mule4",
        vehicleType = "refrigerated",
        price       = 70000,
        minLevel    = 4,
        description = "Isolierter Kühlaufbau für Lebensmittel.",
        category    = "refrigerated",
    },
    mule5 = {
        label       = "Bravado Mule LWB",
        model       = "mule5",
        vehicleType = "refrigerated",
        price       = 95000,
        minLevel    = 7,
        description = "Langversion mit doppelter Kapazität.",
        category    = "refrigerated",
    },
}

-- ────────────────────────────────────────────────────────────
--  Upgrades – HandlingField-Werte pro Stufe
--
--  field     = GTA SetVehicleHandlingField Feldname
--  fieldType = "float" | "bool" | "int"
--  Stufen: [1] = günstigstes, [3] = bestes Upgrade
-- ────────────────────────────────────────────────────────────
Config.Upgrades             = {

    motor = {
        label       = "Motor",
        description = "Erhöht Antriebskraft und Beschleunigung.",
        icon        = "fas fa-tachometer-alt",
        levels      = {
            [1] = {
                label  = "Sport (Stufe 1)",
                price  = 5000,
                fields = { fInitialDriveForce = 0.35 },
            },
            [2] = {
                label  = "Race (Stufe 2)",
                price  = 15000,
                fields = { fInitialDriveForce = 0.45 },
            },
            [3] = {
                label  = "Elite (Stufe 3)",
                price  = 35000,
                fields = { fInitialDriveForce = 0.60 },
            },
        },
    },

    getriebe = {
        label       = "Getriebe",
        description = "Verbessert Schaltzeiten und Endgeschwindigkeit.",
        icon        = "fas fa-cogs",
        levels      = {
            [1] = {
                label  = "Sport (Stufe 1)",
                price  = 4000,
                fields = {
                    fInitialDriveMaxFlatVel         = 100.0,
                    fClutchChangeRateScaleUpShift   = 2.5,
                    fClutchChangeRateScaleDownShift = 2.5,
                },
            },
            [2] = {
                label  = "Race (Stufe 2)",
                price  = 12000,
                fields = {
                    fInitialDriveMaxFlatVel         = 120.0,
                    fClutchChangeRateScaleUpShift   = 3.5,
                    fClutchChangeRateScaleDownShift = 3.5,
                },
            },
            [3] = {
                label  = "Elite (Stufe 3)",
                price  = 28000,
                fields = {
                    fInitialDriveMaxFlatVel         = 140.0,
                    fClutchChangeRateScaleUpShift   = 4.5,
                    fClutchChangeRateScaleDownShift = 4.5,
                },
            },
        },
    },

    federung = {
        label       = "Federung",
        description = "Stabilisiert das Fahrzeug bei voller Beladung.",
        icon        = "fas fa-arrows-alt-v",
        levels      = {
            [1] = {
                label  = "Verstärkt (Stufe 1)",
                price  = 3000,
                fields = {
                    fSuspensionForce       = 3.5,
                    fSuspensionCompDamp    = 1.2,
                    fSuspensionReboundDamp = 1.4,
                },
            },
            [2] = {
                label  = "Heavy-Duty (Stufe 2)",
                price  = 9000,
                fields = {
                    fSuspensionForce       = 5.0,
                    fSuspensionCompDamp    = 1.8,
                    fSuspensionReboundDamp = 2.0,
                },
            },
            [3] = {
                label  = "Profi (Stufe 3)",
                price  = 20000,
                fields = {
                    fSuspensionForce       = 7.0,
                    fSuspensionCompDamp    = 2.5,
                    fSuspensionReboundDamp = 2.8,
                },
            },
        },
    },

    bremsen = {
        label       = "Bremsen",
        description = "Kürzere Bremswege, besonders bei schwerem Cargo.",
        icon        = "fas fa-stop-circle",
        levels      = {
            [1] = {
                label  = "Sport (Stufe 1)",
                price  = 4500,
                fields = {
                    fBrakeForce     = 0.75,
                    fHandBrakeForce = 0.9,
                },
            },
            [2] = {
                label  = "Race (Stufe 2)",
                price  = 13000,
                fields = {
                    fBrakeForce     = 1.0,
                    fHandBrakeForce = 1.2,
                },
            },
            [3] = {
                label  = "Carbon (Stufe 3)",
                price  = 30000,
                fields = {
                    fBrakeForce     = 1.35,
                    fHandBrakeForce = 1.5,
                },
            },
        },
    },

    diffsperre = {
        label       = "Differenzialsperre",
        description = "Verbessert Traktion auf rutschigem Untergrund.",
        icon        = "fas fa-circle-notch",
        -- Boolean-Upgrade: nur Stufe 1 (an/aus)
        levels      = {
            [1] = {
                label  = "Einbauen",
                price  = 18000,
                fields = {
                    fTractionBiasFront = 0.48, -- näher an 0.5 = gleichmäßiger
                    fTractionLossMult  = 0.6,
                },
            },
        },
    },

    turbo = {
        label       = "Turbolader",
        description = "Erhöht die maximale Drehzahl und Leistungsabgabe.",
        icon        = "fas fa-wind",
        levels      = {
            [1] = {
                label  = "Seriell (Stufe 1)",
                price  = 8000,
                fields = {
                    fInitialDriveForce = 0.05, -- additiv zu Motor-Upgrade
                    fDriveInertia      = 0.8,
                },
            },
            [2] = {
                label  = "Twin-Turbo (Stufe 2)",
                price  = 22000,
                fields = {
                    fInitialDriveForce = 0.10,
                    fDriveInertia      = 0.65,
                },
            },
        },
    },
}

-- ────────────────────────────────────────────────────────────
--  Werkstatt-Preise
-- ────────────────────────────────────────────────────────────
Config.RepairCostPerDamage  = 8   -- $ pro Schadenpunkt (0–1000 intern)
Config.RepairMinCost        = 500 -- Mindestkosten auch bei Bagatellschaden
Config.RepairProgressMs     = 8000

-- ────────────────────────────────────────────────────────────
--  Garage
-- ────────────────────────────────────────────────────────────
Config.MaxVehiclesPerPlayer = 5             -- Maximale Fahrzeuge pro Spieler
Config.SpawnOffset          = vec3(0, 5, 0) -- Spawn etwas vor dem Garagentor

-- ────────────────────────────────────────────────────────────
--  Trailer-Definitionen
--  Welche Trailer-Modelle gehören zu welchem vehicleType.
--  Der Server/Client prüft ob der richtige Trailer angekoppelt ist.
--
--  requiresTrailer = true → Job kann nur mit angekoppeltem Trailer
--                           geladen/abgeliefert werden
-- ────────────────────────────────────────────────────────────

Config.TrailerModels        = {
    semi         = { "trailers", "trailers2", "trailers3", "trailers4" },
    flatbed      = { "flatbed", "baletrailer" },
    tanker       = { "tanker", "tanker2" },
    refrigerated = { "trailers3" },
    -- kipper, garbage, heavyhaul haben keinen separaten Trailer
}

-- Welche vehicleTypes einen Trailer brauchen
Config.RequiresTrailer      = {
    semi         = true,
    flatbed      = true,
    tanker       = true,
    refrigerated = true,
    kipper       = false,
    garbage      = false,
    heavyhaul    = false,
}

-- ────────────────────────────────────────────────────────────
--  Trailer-Kapazitäten für das Cargo-System
--
--  capacity              = Maximale Item-Einheiten pro Trailer
--  acceptedCategories    = Welche Item-Kategorien passen rein
--  label                 = Anzeigename im NUI
--
--  Fahrzeuge ohne eigenen Trailer (kipper, garbage):
--  Kapazität gilt für das Fahrzeug selbst.
-- ────────────────────────────────────────────────────────────
Config.TrailerCapacity      = {

    -- Standard Sattelauflieger
    trailers    = { capacity = 30, label = "Standard-Auflieger", acceptedCategories = { "rohstoff", "industrie", "lebensmittel" } },
    trailers2   = { capacity = 40, label = "XL-Sattelauflieger", acceptedCategories = { "rohstoff", "industrie", "lebensmittel" } },
    trailers3   = { capacity = 25, label = "Kühlauflieger", acceptedCategories = { "gekuehlt", "lebensmittel", "fluessigkeit" } },
    trailers4   = { capacity = 35, label = "Schwerlastauflieger", acceptedCategories = { "rohstoff", "industrie" } },

    -- Tanker
    tanker      = { capacity = 20, label = "Tankauflieger", acceptedCategories = { "fluessigkeit" } },
    tanker2     = { capacity = 30, label = "Doppelkammer-Tanker", acceptedCategories = { "fluessigkeit" } },

    -- Tieflader
    flatbed     = { capacity = 15, label = "Tieflader", acceptedCategories = { "rohstoff", "industrie" } },
    flatbed2    = { capacity = 20, label = "Tieflader XL", acceptedCategories = { "rohstoff", "industrie" } },
    baletrailer = { capacity = 25, label = "Ballen-Trailer", acceptedCategories = { "rohstoff", "lebensmittel" } },

    -- Kipper (kein eigener Trailer – Fahrzeugladung)
    dump        = { capacity = 35, label = "Muldenkipper", acceptedCategories = { "rohstoff" } },
    tipper      = { capacity = 20, label = "Kipper", acceptedCategories = { "rohstoff" } },
    tipper2     = { capacity = 28, label = "Kipper SX", acceptedCategories = { "rohstoff" } },

    -- Müllfahrzeuge
    trash       = { capacity = 20, label = "Müllfahrzeug", acceptedCategories = { "rohstoff", "industrie" } },
    trash2      = { capacity = 30, label = "Müllfahrzeug XL", acceptedCategories = { "rohstoff", "industrie" } },

    -- Kühlfahrzeuge (Mule-Typen – kein Trailer)
    mule4       = { capacity = 20, label = "Kühlfahrzeug", acceptedCategories = { "gekuehlt", "lebensmittel" } },
    mule5       = { capacity = 28, label = "Kühlfahrzeug LWB", acceptedCategories = { "gekuehlt", "lebensmittel" } },
}
