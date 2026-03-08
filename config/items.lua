-- ============================================================
--  config/items.lua
--  Alle transportierbaren Waren im Cargo-System.
--
--  category:     Bestimmt welcher Trailer-Typ sie laden kann.
--  weight:       kg pro Einheit (für Lohn-Berechnung via wagePerTon)
--  valuePerUnit: Basis-Kaufpreis / interner Wert
--  icon:         Emoji für die NUI
-- ============================================================

Config                = Config or {}

Config.Items          = {

    -- ────────────────────────────────────────────────────────
    --  ROHSTOFFE  (flatbed, standard-trailer)
    -- ────────────────────────────────────────────────────────
    holz = {
        label        = "Holzstämme",
        icon         = "🪵",
        category     = "rohstoff",
        weight       = 500, -- kg / Einheit
        valuePerUnit = 90,  -- $ Basiswert
    },
    kohle = {
        label        = "Kohle",
        icon         = "⚫",
        category     = "rohstoff",
        weight       = 800,
        valuePerUnit = 70,
    },
    erz = {
        label        = "Eisenerz",
        icon         = "🪨",
        category     = "rohstoff",
        weight       = 1200,
        valuePerUnit = 110,
    },
    schrott = {
        label        = "Metallschrott",
        icon         = "🔩",
        category     = "rohstoff",
        weight       = 900,
        valuePerUnit = 55,
    },
    sand = {
        label        = "Bausand",
        icon         = "🏜️",
        category     = "rohstoff",
        weight       = 1500,
        valuePerUnit = 40,
    },

    -- ────────────────────────────────────────────────────────
    --  FLÜSSIGKEITEN  (tanker only)
    -- ────────────────────────────────────────────────────────
    rohoel = {
        label        = "Rohöl",
        icon         = "🛢️",
        category     = "fluessigkeit",
        weight       = 850,
        valuePerUnit = 180,
    },
    benzin = {
        label        = "Benzin",
        icon         = "⛽",
        category     = "fluessigkeit",
        weight       = 750,
        valuePerUnit = 210,
    },
    chemikalien = {
        label        = "Chemikalien",
        icon         = "⚗️",
        category     = "fluessigkeit",
        weight       = 700,
        valuePerUnit = 320,
        dangerous    = true, -- Gefahrgut → Bonus-Multiplier
    },
    milch = {
        label        = "Frischmilch",
        icon         = "🥛",
        category     = "fluessigkeit",
        weight       = 1030,
        valuePerUnit = 160,
        perishable   = true, -- verdirbt nach 30 Min
        perishMin    = 30,
    },

    -- ────────────────────────────────────────────────────────
    --  LEBENSMITTEL / GEKÜHLT  (refrigerated trailer)
    -- ────────────────────────────────────────────────────────
    fleisch = {
        label        = "Frischfleisch",
        icon         = "🥩",
        category     = "gekuehlt",
        weight       = 300,
        valuePerUnit = 250,
        perishable   = true,
        perishMin    = 45,
    },
    gefluegel = {
        label        = "Geflügel",
        icon         = "🍗",
        category     = "gekuehlt",
        weight       = 200,
        valuePerUnit = 220,
        perishable   = true,
        perishMin    = 40,
    },
    fisch = {
        label        = "Frischfisch",
        icon         = "🐟",
        category     = "gekuehlt",
        weight       = 150,
        valuePerUnit = 280,
        perishable   = true,
        perishMin    = 35,
    },
    tiefkuehlware = {
        label        = "Tiefkühlware",
        icon         = "🧊",
        category     = "gekuehlt",
        weight       = 400,
        valuePerUnit = 190,
    },
    gemuese = {
        label        = "Gemüse & Obst",
        icon         = "🥦",
        category     = "lebensmittel",
        weight       = 250,
        valuePerUnit = 140,
    },
    mehl = {
        label        = "Mehl & Getreide",
        icon         = "🌾",
        category     = "lebensmittel",
        weight       = 600,
        valuePerUnit = 120,
    },

    -- ────────────────────────────────────────────────────────
    --  INDUSTRIEWAREN / FERTIGTEILE  (standard + flatbed)
    -- ────────────────────────────────────────────────────────
    holzbretter = {
        label        = "Holzbretter",
        icon         = "🪵",
        category     = "industrie",
        weight       = 300,
        valuePerUnit = 150,
    },
    stahl = {
        label        = "Stahlträger",
        icon         = "🔩",
        category     = "industrie",
        weight       = 1000,
        valuePerUnit = 200,
    },
    beton = {
        label        = "Betonfertigteile",
        icon         = "🏗️",
        category     = "industrie",
        weight       = 2000,
        valuePerUnit = 170,
    },
    elektronik = {
        label        = "Elektronikteile",
        icon         = "💾",
        category     = "industrie",
        weight       = 100,
        valuePerUnit = 450,
        fragile      = true, -- vorsichtig fahren
    },
    verpackungen = {
        label        = "Verpackungsmaterial",
        icon         = "📦",
        category     = "industrie",
        weight       = 150,
        valuePerUnit = 85,
    },
    maschinen = {
        label        = "Maschinenteile",
        icon         = "⚙️",
        category     = "industrie",
        weight       = 1500,
        valuePerUnit = 380,
    },
    container = {
        label        = "Seecontainer",
        icon         = "🟦",
        category     = "industrie",
        weight       = 8000,
        valuePerUnit = 600,
    },
}

-- ────────────────────────────────────────────────────────────
--  Kategorie-Labels (für NUI und Admin)
-- ────────────────────────────────────────────────────────────
Config.ItemCategories = {
    rohstoff     = { label = "Rohstoffe", icon = "⛏️", color = "#a0845c" },
    fluessigkeit = { label = "Flüssigkeiten", icon = "💧", color = "#4a9eff" },
    gekuehlt     = { label = "Gekühlt / Frisch", icon = "❄️", color = "#7ec8e3" },
    lebensmittel = { label = "Lebensmittel", icon = "🛒", color = "#5fdf78" },
    industrie    = { label = "Industriewaren", icon = "🏭", color = "#f5c518" },
}
