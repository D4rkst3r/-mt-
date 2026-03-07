-- ============================================================
--  client/blips.lua
--  Statische Map-Blips für alle Motortown-Orte.
--
--  GTA V Blip Sprites:  https://docs.fivem.net/game-references/blips/
--  GTA V Blip Farben:   0=white 1=red 2=green 3=blue 4=white
--                       5=yellow 6=purple 7=green 8=orange 38=pink
--                       59=orange 66=light-blue
-- ============================================================

local BlipsModule = {}

-- ────────────────────────────────────────────────────────────
--  Blip-Definitionen
--  { label, coords, sprite, color, scale }
-- ────────────────────────────────────────────────────────────

local BLIP_DEFS = {

    -- ── Dispatcher (Auftragsstellen) ────────────────────────
    {
        label  = "Dispatcher – Stadtmitte",
        coords = vec3(213.7, -810.5, 30.7),
        sprite = 545, -- Lkw-Symbol
        color  = 3,   -- Blau
        scale  = 0.9,
    },
    {
        label  = "Dispatcher – Hafen",
        coords = vec3(836.8, -2991.3, 5.9),
        sprite = 545,
        color  = 3,
        scale  = 0.9,
    },
    {
        label  = "Dispatcher – Industrie",
        coords = vec3(963.1, -2393.4, 30.6),
        sprite = 545,
        color  = 3,
        scale  = 0.9,
    },
    {
        label  = "Dispatcher – Flughafen",
        coords = vec3(-1034.8, -2730.1, 20.2),
        sprite = 545,
        color  = 3,
        scale  = 0.9,
    },

    -- ── Garagen ─────────────────────────────────────────────
    {
        label  = "Garage – Stadtmitte",
        coords = vec3(215.7, -808.5, 30.7),
        sprite = 357, -- Garage-Symbol
        color  = 2,   -- Grün
        scale  = 0.85,
    },
    {
        label  = "Garage – Hafen",
        coords = vec3(704.0, -2832.0, 6.0),
        sprite = 357,
        color  = 2,
        scale  = 0.85,
    },
    {
        label  = "Garage – Industrie",
        coords = vec3(992.0, -2283.0, 29.0),
        sprite = 357,
        color  = 2,
        scale  = 0.85,
    },

    -- ── Werkstätten ──────────────────────────────────────────
    {
        label  = "Werkstatt",
        coords = vec3(326.0, -204.8, 54.4),
        sprite = 446, -- Schraubenschlüssel
        color  = 59,  -- Orange
        scale  = 0.85,
    },
    {
        label  = "Werkstatt – Hafen",
        coords = vec3(726.5, -2875.3, 6.1),
        sprite = 446,
        color  = 59,
        scale  = 0.85,
    },

    -- ── Fahrzeughändler ──────────────────────────────────────
    {
        label  = "LKW Händler",
        coords = vec3(-36.0, -1100.0, 26.4),
        sprite = 523, -- Auto-Händler-Symbol
        color  = 5,   -- Gelb
        scale  = 0.95,
    },
    {
        label  = "Spezialfahrzeuge",
        coords = vec3(137.3, -1065.5, 29.2),
        sprite = 523,
        color  = 5,
        scale  = 0.95,
    },

    -- ── Firmenbüro ───────────────────────────────────────────
    {
        label  = "Firmen-Verwaltung",
        coords = vec3(-135.3, -627.5, 168.9),
        sprite = 475, -- Koffer / Büro
        color  = 6,   -- Lila
        scale  = 0.90,
    },

    -- ── Ladezonen ────────────────────────────────────────────
    {
        label  = "Container laden",
        coords = vec3(825.2, -3000.1, 5.9),
        sprite = 477, -- Kiste
        color  = 8,   -- Orange
        scale  = 0.75,
    },
    {
        label  = "Holz laden",
        coords = vec3(1664.2, 3517.6, 35.8),
        sprite = 477,
        color  = 8,
        scale  = 0.75,
    },
    {
        label  = "Kohle laden",
        coords = vec3(2706.4, 1573.5, 24.6),
        sprite = 477,
        color  = 8,
        scale  = 0.75,
    },
    {
        label  = "Tanker befüllen",
        coords = vec3(144.0, -1539.7, 29.3),
        sprite = 477,
        color  = 8,
        scale  = 0.75,
    },
    {
        label  = "Müll aufnehmen",
        coords = vec3(-324.5, -1544.3, 27.7),
        sprite = 477,
        color  = 8,
        scale  = 0.75,
    },

    -- ── Ablieferzonen ────────────────────────────────────────
    {
        label  = "Supermarkt (North)",
        coords = vec3(-57.2, -1743.4, 29.4),
        sprite = 52, -- Einkaufswagen
        color  = 2,
        scale  = 0.75,
    },
    {
        label  = "Supermarkt (East)",
        coords = vec3(1166.3, -322.5, 69.2),
        sprite = 52,
        color  = 2,
        scale  = 0.75,
    },
    {
        label  = "Kraftwerk",
        coords = vec3(2717.8, 1547.3, 24.6),
        sprite = 354, -- Blitz / Energie
        color  = 5,
        scale  = 0.75,
    },
}

-- ────────────────────────────────────────────────────────────
--  Blips erstellen
-- ────────────────────────────────────────────────────────────

local createdBlips = {}

local function CreateStaticBlips()
    for _, def in ipairs(BLIP_DEFS) do
        local blip = AddBlipForCoord(def.coords.x, def.coords.y, def.coords.z)
        SetBlipSprite(blip, def.sprite)
        SetBlipColour(blip, def.color)
        SetBlipScale(blip, def.scale or 0.85)
        SetBlipAsShortRange(blip, true) -- nur sichtbar wenn nah → weniger Clutter
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(def.label)
        EndTextCommandSetBlipName(blip)
        table.insert(createdBlips, blip)
    end
    print(("[MT] %d Map-Blips erstellt"):format(#createdBlips))
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function BlipsModule.Init()
    -- Warten bis Spieler geladen ist
    AddEventHandler("mt:player:ready", function()
        CreateStaticBlips()
    end)
end

_BlipsModule = BlipsModule
