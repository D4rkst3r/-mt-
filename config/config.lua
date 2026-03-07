-- ============================================================
--  config/config.lua
--  Globale Einstellungen – läuft shared (Client + Server).
--  Alle Werte die irgendwo im Code gebraucht werden,
--  aber keinem spezifischen Modul gehören, landen hier.
-- ============================================================

Config                      = Config or {}

-- ────────────────────────────────────────────────────────────
--  Server-Identität
-- ────────────────────────────────────────────────────────────
Config.ServerName           = "Motor Town"
Config.DiscordWebhook       = "" -- optional: Transaktions-Log via Discord

-- ────────────────────────────────────────────────────────────
--  Spieler-Start
-- ────────────────────────────────────────────────────────────
Config.StartMoney           = 500
Config.StartBank            = 2000
Config.StartLevel           = 1

-- ────────────────────────────────────────────────────────────
--  Job-System
-- ────────────────────────────────────────────────────────────
Config.XPPerKm              = 10   -- XP pro Kilometer gefahren
Config.XPBaseDelivery       = 50   -- Fix-XP pro abgeschlossener Lieferung
Config.MaxJobDistance       = 80.0 -- Meter: Abstand zur Zielzone für Ablieferung
Config.LoadProgressMs       = 5000 -- Millisekunden Ladevorgang
Config.UnloadProgressMs     = 4000 -- Millisekunden Abliefervorgang
Config.JobRequestCooldown   = 3    -- Sekunden zwischen Job-Anfragen (Rate-Limit)

-- ────────────────────────────────────────────────────────────
--  Fahrzeug-System
-- ────────────────────────────────────────────────────────────
Config.MaxVehiclesPerPlayer = 5
Config.RepairCostPerDamage  = 8 -- $ pro Schadenspunkt (0–1000)
Config.RepairMinCost        = 500
Config.RepairProgressMs     = 8000
Config.SpawnOffset          = vec3(0, 5, 0)

-- Kraftstoffverbrauch pro Kilometer (Prozent-Punkte)
Config.FuelConsumptionPerKm = 2.5

-- ────────────────────────────────────────────────────────────
--  Town Bonus
-- ────────────────────────────────────────────────────────────
Config.BonusPerDelivery     = 0.05 -- +5% pro Lieferung in Zone
Config.BonusDecayRate       = 0.02 -- -2% Decay alle 10 Min
Config.BonusMin             = 1.0
Config.BonusMax             = 2.0
Config.BonusDecayMs         = 10 * 60 * 1000

-- ────────────────────────────────────────────────────────────
--  Supply Chain
-- ────────────────────────────────────────────────────────────
Config.ProductionTickMs     = 5 * 60 * 1000
Config.ConsumerTickMs       = 10 * 60 * 1000
Config.UrgentStockThreshold = 5

-- ────────────────────────────────────────────────────────────
--  Company
-- ────────────────────────────────────────────────────────────
Config.CompanyFoundCost     = 50000
Config.RoutePayoutMin       = 800
Config.RoutePayoutMax       = 2500
Config.RouteMaintenanceCost = 300
Config.RouteTickMs          = 30 * 60 * 1000

-- ────────────────────────────────────────────────────────────
--  HUD
-- ────────────────────────────────────────────────────────────
Config.HudUpdateMs          = 2000 -- Wie oft HUD-Daten aktualisiert werden
Config.HudPosition          = "bottom-right"

-- Welche HUD-Elemente standardmäßig sichtbar sind
Config.HudDefaults          = {
    money = true,
    level = true,
    xp    = true,
    job   = true,
    bonus = true,
    fuel  = true,
    speed = true,
}

-- ────────────────────────────────────────────────────────────
--  Debug
-- ────────────────────────────────────────────────────────────
Config.Debug                = true -- Zusätzliche Print-Ausgaben
Config.DebugZones           = true -- Zonen-Grenzen in der Welt anzeigen
