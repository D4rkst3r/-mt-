-- ============================================================
--  config/supplychain.lua
--  Fabriken, ihre Input/Output-Waren, Produktionszeiten
--  und Verbraucher-Definitionen.
--
--  Wie die Supply Chain funktioniert:
--
--  1. Spieler liefern Input-Items zu Fabriken (via Jobs)
--  2. Server-Loop prüft alle 5 Min ob genug Input vorhanden
--  3. Wenn ja: Input abziehen, Output erhöhen
--  4. Neue Liefer-Jobs werden generiert wenn Output-Stock hoch
--  5. Verbraucher (Supermärkte etc.) reduzieren Output-Stock
--     langsam alle 10 Min → erzeugt dauerhaften Bedarf
-- ============================================================

Config                      = Config or {}

Config.Factories            = {

    -- --------------------------------------------------------
    --  Fleischfabrik
    --  Input:  Container (Rohware aus Hafen)
    --  Output: Fleisch   (für Supermärkte / Restaurants)
    -- --------------------------------------------------------
    fleischfabrik = {
        label             = "Fleischfabrik",
        zone              = "fabrik_fleisch",
        input             = { item = "container", amount = 2 },
        output            = { item = "lebensmittel", amount = 8 },
        productionTime    = 300, -- Sekunden zwischen Produktionen
        maxInputStock     = 20,
        maxOutputStock    = 40,
        -- Wenn Output-Stock > threshold → neuer Liefer-Job
        deliveryThreshold = 10,
        -- container_anlieferung-Job liefert Container TO fabrik_fleisch → erhöht inputStock
        deliveryJobKey    = "container_anlieferung",
    },

    -- --------------------------------------------------------
    --  Sägewerk
    --  Input:  Holzladung  (frisch aus dem Wald)
    --  Output: Holzbretter (für Bauprojekte / Export)
    -- --------------------------------------------------------
    saegerei = {
        label             = "Sägewerk",
        zone              = "fabrik_saegerei",
        input             = { item = "holzladung", amount = 3 },
        output            = { item = "holzbretter", amount = 12 },
        productionTime    = 240,
        maxInputStock     = 15,
        maxOutputStock    = 50,
        deliveryThreshold = 15,
        deliveryJobKey    = "holz",
    },

    -- --------------------------------------------------------
    --  Kraftwerk
    --  Input:  Kohle     (aus Tagebau)
    --  Output: Strom     (kein lieferbares Item –
    --                     erhöht stattdessen Town Bonus aller Zonen)
    -- --------------------------------------------------------
    kraftwerk = {
        label             = "Kraftwerk",
        zone              = "ablieferzone_kraftwerk",
        input             = { item = "kohle", amount = 5 },
        output            = { item = "strom", amount = 1 }, -- internes Token
        productionTime    = 600,
        maxInputStock     = 30,
        maxOutputStock    = 5, -- niedrig: Strom wird sofort "verbraucht"
        deliveryThreshold = 3,
        deliveryJobKey    = "kohle",
        -- Sondereffekt: Produktion erhöht Town Bonus aller Städte
        townBonusEffect   = 0.10,
    },

    -- --------------------------------------------------------
    --  Raffinerie
    --  Input:  Kraftstofftank (Tanker-Lieferung)
    --  Output: Kraftstoff     (für Tankstellen & Flughafen)
    -- --------------------------------------------------------
    raffinerie = {
        label             = "Raffinerie",
        zone              = "ladezone_tank",
        input             = { item = "kraftstoff", amount = 2 },
        output            = { item = "treibstoff", amount = 10 },
        productionTime    = 450,
        maxInputStock     = 10,
        maxOutputStock    = 30,
        deliveryThreshold = 8,
        -- rohoel_anlieferung-Job liefert Rohöl TO ladezone_tank → erhöht inputStock
        deliveryJobKey    = "rohoel_anlieferung",
    },
}

-- ────────────────────────────────────────────────────────────
--  Verbraucher – reduzieren Output-Stock passiv
--  rate = Items pro Tick (alle 10 Min)
-- ────────────────────────────────────────────────────────────
Config.Consumers            = {
    {
        label      = "Supermärkte LS",
        factoryKey = "fleischfabrik",
        item       = "lebensmittel",
        rate       = 3, -- verbraucht 3 Lebensmittel alle 10 Min
    },
    {
        label      = "Bauwirtschaft",
        factoryKey = "saegerei",
        item       = "holzbretter",
        rate       = 2,
    },
    {
        label      = "Stadtversorgung",
        factoryKey = "kraftwerk",
        item       = "strom",
        rate       = 1,
    },
    {
        label      = "Tankstellen-Netz",
        factoryKey = "raffinerie",
        item       = "treibstoff",
        rate       = 4,
    },
}

-- Minimaler Stock-Level unter dem DRINGEND neue Jobs generiert werden
Config.UrgentStockThreshold = 5
