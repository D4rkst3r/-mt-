-- ============================================================
--  config/deliverypoints.lua
--  Konfiguriert welche Zonen welche Items ANBIETEN (Pickup)
--  und welche Items ANNEHMEN (Delivery).
--
--  Separate Datei damit zones.lua (Geometrie) nicht angefasst
--  werden muss. Admin kann diese via NUI überschreiben
--  (Overrides landen in mt_config category='deliverypoint').
--
--  offeredItems:   Was hier geladen werden kann
--    item          = Key aus Config.Items
--    maxStock      = Maximales Lager (respawnt alle stockRefillMin)
--    stockRefillMin= Minuten bis Stock wieder voll
--
--  acceptedItems:  Was hier abgeliefert werden kann
--    item          = Key aus Config.Items
--    maxPerDeliv   = Max. Einheiten pro Lieferung
--    pricePerUnit  = $ pro gelieferter Einheit (Basis)
--    factoryKey    = Optional: erhöht inputStock dieser Fabrik
-- ============================================================

Config                = Config or {}

Config.DeliveryPoints = {

    -- ────────────────────────────────────────────────────────
    --  HAFEN – Container, Rohöl rein
    -- ────────────────────────────────────────────────────────
    ladezone_hafen_container = {
        type         = "pickup",
        label        = "Hafenkai – Laderampe",
        offeredItems = {
            { item = "container",  maxStock = 20, stockRefillMin = 15 },
            { item = "elektronik", maxStock = 40, stockRefillMin = 20 },
            { item = "maschinen",  maxStock = 15, stockRefillMin = 25 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  HOLZLAGER
    -- ────────────────────────────────────────────────────────
    ladezone_holz = {
        type         = "pickup",
        label        = "Holzlager",
        offeredItems = {
            { item = "holz",    maxStock = 80, stockRefillMin = 10 },
            { item = "schrott", maxStock = 30, stockRefillMin = 20 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  KOHLEMINE
    -- ────────────────────────────────────────────────────────
    ladezone_kohle = {
        type         = "pickup",
        label        = "Kohlemine",
        offeredItems = {
            { item = "kohle", maxStock = 100, stockRefillMin = 8 },
            { item = "erz",   maxStock = 50,  stockRefillMin = 12 },
            { item = "sand",  maxStock = 60,  stockRefillMin = 5 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  TANKSTATION (Ölfelder)
    -- ────────────────────────────────────────────────────────
    ladezone_tank = {
        type         = "pickup",
        label        = "Ölfeld – Pumpenstation",
        offeredItems = {
            { item = "rohoel", maxStock = 60, stockRefillMin = 10 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  MÜLLHOF
    -- ────────────────────────────────────────────────────────
    ladezone_muell = {
        type         = "pickup",
        label        = "Müllhof – Sammeldepot",
        offeredItems = {
            { item = "schrott",      maxStock = 50, stockRefillMin = 8 },
            { item = "verpackungen", maxStock = 40, stockRefillMin = 6 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  SCHLACHTHOF / FLEISCHLIEFERANT
    -- ────────────────────────────────────────────────────────
    ladezone_fleisch = {
        type         = "pickup",
        label        = "Schlachthof",
        offeredItems = {
            { item = "fleisch",   maxStock = 50, stockRefillMin = 15 },
            { item = "gefluegel", maxStock = 40, stockRefillMin = 12 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  MILCHHOF
    -- ────────────────────────────────────────────────────────
    ladezone_milch = {
        type         = "pickup",
        label        = "Milchhof",
        offeredItems = {
            { item = "milch", maxStock = 60, stockRefillMin = 10 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  SUPERMARKT NORD – nimmt Lebensmittel & Tiefkühl
    -- ────────────────────────────────────────────────────────
    ablieferzone_supermarkt_north = {
        type          = "delivery",
        label         = "Supermarkt LS Nord",
        acceptedItems = {
            { item = "fleisch",       maxPerDeliv = 20, pricePerUnit = 280 },
            { item = "gefluegel",     maxPerDeliv = 20, pricePerUnit = 260 },
            { item = "fisch",         maxPerDeliv = 15, pricePerUnit = 300 },
            { item = "tiefkuehlware", maxPerDeliv = 25, pricePerUnit = 210 },
            { item = "gemuese",       maxPerDeliv = 30, pricePerUnit = 155 },
            { item = "mehl",          maxPerDeliv = 20, pricePerUnit = 135 },
            { item = "milch",         maxPerDeliv = 20, pricePerUnit = 175 },
        },
    },

    ablieferzone_supermarkt_east = {
        type          = "delivery",
        label         = "Supermarkt LS Ost",
        acceptedItems = {
            { item = "fleisch",       maxPerDeliv = 20, pricePerUnit = 270 },
            { item = "tiefkuehlware", maxPerDeliv = 20, pricePerUnit = 200 },
            { item = "gemuese",       maxPerDeliv = 25, pricePerUnit = 150 },
            { item = "mehl",          maxPerDeliv = 25, pricePerUnit = 130 },
            { item = "milch",         maxPerDeliv = 25, pricePerUnit = 165 },
            { item = "verpackungen",  maxPerDeliv = 15, pricePerUnit = 90 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  KRAFTWERK – nimmt Kohle
    -- ────────────────────────────────────────────────────────
    ablieferzone_kraftwerk = {
        type          = "delivery",
        label         = "Kraftwerk – Kohlebunker",
        acceptedItems = {
            { item = "kohle", maxPerDeliv = 50, pricePerUnit = 95, factoryKey = "kraftwerk" },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  FLEISCHFABRIK – nimmt Container (Rohware), liefert Fleisch
    -- ────────────────────────────────────────────────────────
    ablieferzone_fleischfabrik = {
        type          = "delivery",
        label         = "Fleischfabrik – Anlieferung",
        acceptedItems = {
            { item = "container", maxPerDeliv = 5,  pricePerUnit = 450, factoryKey = "fleischfabrik" },
            { item = "fleisch",   maxPerDeliv = 20, pricePerUnit = 200, factoryKey = "fleischfabrik" },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  SÄGEWERK – nimmt Holz, produziert Bretter
    -- ────────────────────────────────────────────────────────
    fabrik_saegerei = {
        type          = "delivery",
        label         = "Sägewerk – Anlieferung",
        acceptedItems = {
            { item = "holz", maxPerDeliv = 30, pricePerUnit = 100, factoryKey = "saegerei" },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  RAFFINERIE – nimmt Rohöl
    -- ────────────────────────────────────────────────────────
    ladezone_tank_delivery = {
        type          = "delivery",
        label         = "Raffinerie – Anlieferung",
        acceptedItems = {
            { item = "rohoel", maxPerDeliv = 20, pricePerUnit = 220, factoryKey = "raffinerie" },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  BAUSTOFF-HÄNDLER – nimmt Holzbretter, Stahl, Sand, Beton
    -- ────────────────────────────────────────────────────────
    ablieferzone_baustoff = {
        type          = "delivery",
        label         = "Baustoffhändler",
        acceptedItems = {
            { item = "holzbretter", maxPerDeliv = 30, pricePerUnit = 165 },
            { item = "stahl",       maxPerDeliv = 20, pricePerUnit = 230 },
            { item = "beton",       maxPerDeliv = 15, pricePerUnit = 195 },
            { item = "sand",        maxPerDeliv = 40, pricePerUnit = 50 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  TANKSTELLEN-NETZ – nimmt Benzin
    -- ────────────────────────────────────────────────────────
    ablieferzone_tankstelle = {
        type          = "delivery",
        label         = "Tankstellennetz",
        acceptedItems = {
            { item = "benzin",      maxPerDeliv = 20, pricePerUnit = 240 },
            { item = "chemikalien", maxPerDeliv = 10, pricePerUnit = 380 },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  SCHROTTPLATZ – nimmt Schrott, produziert Stahl
    -- ────────────────────────────────────────────────────────
    ablieferzone_schrottplatz = {
        type          = "delivery",
        label         = "Schrottplatz",
        acceptedItems = {
            { item = "schrott", maxPerDeliv = 40, pricePerUnit = 70, factoryKey = "schrottplatz" },
        },
    },

    -- ────────────────────────────────────────────────────────
    --  ELEKTRONIK-WERK – nimmt Maschinen/Elektronik
    -- ────────────────────────────────────────────────────────
    ablieferzone_elektronik = {
        type          = "delivery",
        label         = "Elektronikwerk",
        acceptedItems = {
            { item = "elektronik", maxPerDeliv = 20, pricePerUnit = 500 },
            { item = "maschinen",  maxPerDeliv = 10, pricePerUnit = 420 },
        },
    },
}
