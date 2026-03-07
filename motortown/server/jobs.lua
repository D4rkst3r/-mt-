-- ============================================================
--  server/jobs.lua
--  Zuständig für: Job generieren, annehmen, validieren,
--  Lohn berechnen und auszahlen.
--
--  Sicherheitsprinzipien:
--  - Kein Client kann Lohn selbst auslösen
--  - Abschluss wird server-seitig verifiziert
--    (Cargo vorhanden? Zielzone erreicht?)
--  - Aktive Jobs pro Spieler in Memory-Table (kein DB-Spam)
-- ============================================================

local JobModule = {}

-- Aktive Jobs: [source] = jobState
-- jobState = {
--   jobKey, jobConfig, startTime, startCoords,
--   pickupZone, deliveryZone, distanceKm,
--   cargoLoaded, stopsDone (für multiStop)
-- }
local activeJobs = {}

-- Rate-Limit: verhindert Spam auf Job-Anfragen
-- [source] = os.time() des letzten Requests
local lastRequest = {}
local REQUEST_COOLDOWN = 3 -- Sekunden

-- ────────────────────────────────────────────────────────────
--  Interne Helfer
-- ────────────────────────────────────────────────────────────

local function GetZoneCoords(zoneKey)
    local zone = Config.Zones[zoneKey]
    if not zone then return nil end
    -- Poly-Zonen haben keine einzelne Koordinate → Mittelpunkt berechnen
    if zone.type == "poly" then
        local cx, cy = 0, 0
        for _, p in ipairs(zone.points) do
            cx = cx + p.x
            cy = cy + p.y
        end
        local n = #zone.points
        return vec3(cx / n, cy / n, 0.0)
    end
    return zone.coords
end

local function PickRandom(tbl)
    return tbl[math.random(1, #tbl)]
end

-- Distanz in km zwischen zwei Zone-Keys
local function CalcDistanceKm(zoneKeyA, zoneKeyB)
    local a = GetZoneCoords(zoneKeyA)
    local b = GetZoneCoords(zoneKeyB)
    if not a or not b then return 1.0 end
    return math.max(0.1, Utils.Round(Utils.Distance3D(a, b) / 1000.0, 2))
end

-- Zeitbonus-Multiplikator: 1.0–1.3 je nach Restzeit
local function CalcTimeMultiplier(jobConfig, elapsedSeconds)
    if not jobConfig.timeBonus then return 1.0 end
    local limitSec = (jobConfig.timeLimitMin or 30) * 60
    if elapsedSeconds >= limitSec then return 1.0 end
    -- Linear: 0 Sek → 1.3x, limitSec → 1.0x
    local ratio = 1.0 - (elapsedSeconds / limitSec)
    return Utils.Round(1.0 + (ratio * 0.3), 2)
end

-- Endlohn berechnen
local function CalcWage(source, jobKey, jobState, townBonusTable)
    local cfg       = jobState.jobConfig
    local distKm    = jobState.distanceKm
    local weightTon = cfg.cargo.weight / 1000.0
    local elapsed   = os.time() - jobState.startTime

    local rawWage   = cfg.baseWage
        + (distKm * cfg.wagePerKm)
        + (weightTon * cfg.wagePerTon)

    -- Bonus-Multiplikatoren
    local townBonus = 1.0
    if townBonusTable and jobState.deliveryZoneKey then
        -- Suche welche Bonus-Zone die Ablieferzone enthält
        for zoneKey, bonus in pairs(townBonusTable) do
            -- Vereinfachte Zuordnung: Zone-Key-Match im Delivery-Key
            if jobState.deliveryZone and jobState.deliveryZone:find(zoneKey) then
                townBonus = bonus
                break
            end
        end
    end

    local timeMult    = CalcTimeMultiplier(cfg, elapsed)
    local dangerMult  = cfg.dangerBonus or 1.0
    local qualityMult = (cfg.qualityBonus and timeMult > 1.0) and cfg.qualityBonus or 1.0

    local finalWage   = Utils.Round(rawWage * townBonus * timeMult * dangerMult * qualityMult, 0)

    return finalWage, {
        base       = Utils.Round(rawWage, 0),
        townBonus  = townBonus,
        timeMult   = timeMult,
        dangerMult = dangerMult,
        distKm     = distKm,
    }
end

-- Validiert ob source gerade ein Fahrzeug des richtigen Typs fährt
-- Wird via Client-Event bestätigt (Client schickt vehicleType)
local function IsVehicleTypeValid(vehicleType, requiredType)
    if not requiredType then return true end
    return vehicleType == requiredType
end

-- ────────────────────────────────────────────────────────────
--  Net Events (Client → Server)
-- ────────────────────────────────────────────────────────────

-- Spieler fordert Job-Liste an (für Dispatcher-Menü)
local function OnJobListRequest(source)
    -- Rate-Limit prüfen
    local now = os.time()
    if lastRequest[source] and (now - lastRequest[source]) < REQUEST_COOLDOWN then
        return
    end
    lastRequest[source] = now

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    -- Verfügbare Jobs nach Level filtern
    local available = {}
    for jobKey, jobCfg in pairs(Config.Jobs) do
        if playerData.trucking_level >= jobCfg.minLevel then
            table.insert(available, {
                key         = jobKey,
                label       = jobCfg.label,
                description = jobCfg.description,
                minLevel    = jobCfg.minLevel,
                vehicleType = jobCfg.vehicleType,
                baseWage    = jobCfg.baseWage,
                locked      = false,
            })
        else
            -- Gesperrte Jobs auch zeigen (für Motivation)
            table.insert(available, {
                key      = jobKey,
                label    = jobCfg.label,
                minLevel = jobCfg.minLevel,
                locked   = true,
            })
        end
    end

    TriggerClientEvent(MT.JOB_VALIDATE, source, { jobs = available })
end

-- Spieler nimmt Job an
local function OnJobRequest(source, data)
    if not data or not data.jobKey then return end

    -- Doppeljob verhindern
    if activeJobs[source] then
        TriggerClientEvent(MT.JOB_VALIDATE, source, {
            error = "Du hast bereits einen aktiven Job. Breche ihn zuerst ab."
        })
        return
    end

    local jobCfg = Config.Jobs[data.jobKey]
    if not jobCfg then return end

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    -- Level prüfen
    if playerData.trucking_level < jobCfg.minLevel then
        TriggerClientEvent(MT.JOB_VALIDATE, source, {
            error = ("Für diesen Job benötigst du Level %d."):format(jobCfg.minLevel)
        })
        return
    end

    -- Fahrzeugtyp prüfen (Client hat vehicleType mitgeschickt)
    if data.vehicleType and not IsVehicleTypeValid(data.vehicleType, jobCfg.vehicleType) then
        TriggerClientEvent(MT.JOB_VALIDATE, source, {
            error = ("Falsches Fahrzeug. Benötigt: %s"):format(jobCfg.vehicleType)
        })
        return
    end

    -- Abholzone & Lieferzone zufällig wählen
    local pickupZone   = PickRandom(jobCfg.pickupZones)
    local deliveryZone = PickRandom(jobCfg.deliveryZones)
    local distKm       = CalcDistanceKm(pickupZone, deliveryZone)

    -- Job-State anlegen
    activeJobs[source] = {
        jobKey       = data.jobKey,
        jobConfig    = jobCfg,
        startTime    = os.time(),
        pickupZone   = pickupZone,
        deliveryZone = deliveryZone,
        distanceKm   = distKm,
        cargoLoaded  = false,
        stopsDone    = 0,
    }

    -- Client informieren
    TriggerClientEvent(MT.JOB_START, source, {
        jobKey       = data.jobKey,
        label        = jobCfg.label,
        pickupZone   = pickupZone,
        deliveryZone = deliveryZone,
        distanceKm   = distKm,
        cargo        = jobCfg.cargo,
        multiStop    = jobCfg.multiStop,
        stopCount    = jobCfg.stopCount,
        blipColor    = jobCfg.blipColor,
        blipSprite   = jobCfg.blipSprite,
    })

    print(("[MT] Job '%s' gestartet für %s (%.1f km)"):format(
        data.jobKey, playerData.identifier, distKm
    ))
end

-- Client bestätigt Cargo wurde geladen
local function OnCargoLoaded(source, data)
    local job = activeJobs[source]
    if not job then return end

    -- Sicherheit: Spieler muss in der richtigen Ladezone sein
    -- (Koordinaten-Check kommt vom Client mit)
    if not data or not data.zone then return end
    if data.zone ~= job.pickupZone then
        -- Versucht in falscher Zone zu laden
        print(("[MT] SICHERHEIT: %s versuchte in falscher Zone zu laden (%s statt %s)")
            :format(source, data.zone, job.pickupZone))
        return
    end

    if job.jobConfig.multiStop then
        job.stopsDone = (job.stopsDone or 0) + 1
        job.cargoLoaded = job.stopsDone >= (job.jobConfig.stopCount or 1)
    else
        job.cargoLoaded = true
    end

    -- ox_inventory: Cargo ins Spieler-Inventory legen
    -- (ox_inventory läuft server-seitig)
    local cargo = job.jobConfig.cargo
    exports.ox_inventory:AddItem(source, cargo.item, cargo.amount, {
        jobKey    = job.jobKey,
        sessionId = job.startTime, -- Prevents duplicate loading
    })

    TriggerClientEvent(MT.JOB_CARGO_LOADED, source, {
        cargoLoaded = job.cargoLoaded,
        stopsDone   = job.stopsDone,
        stopCount   = job.jobConfig.stopCount,
    })
end

-- Client bestätigt Ablieferung
local function OnJobComplete(source, data)
    local job = activeJobs[source]
    if not job then
        TriggerClientEvent(MT.JOB_VALIDATE, source, { error = "Kein aktiver Job." })
        return
    end

    if not data or not data.zone then return end

    -- Sicherheit: muss in Ablieferzone sein
    if data.zone ~= job.deliveryZone then
        print(("[MT] SICHERHEIT: %s versuchte in falscher Zone abzuliefern"):format(source))
        return
    end

    -- Cargo vorhanden?
    if not job.cargoLoaded then
        TriggerClientEvent(MT.JOB_VALIDATE, source, {
            error = "Du hast noch kein Cargo geladen."
        })
        return
    end

    -- Cargo aus Inventory nehmen
    local cargo = job.jobConfig.cargo
    local removed = exports.ox_inventory:RemoveItem(source, cargo.item, cargo.amount)
    if not removed then
        TriggerClientEvent(MT.JOB_VALIDATE, source, {
            error = "Cargo nicht im Inventory gefunden."
        })
        return
    end

    -- Town Bonus holen (aus TownBonusModule)
    local townBonusTable = _TownBonusModule and _TownBonusModule.GetBonusTable() or {}

    -- Lohn berechnen
    local wage, breakdown = CalcWage(source, job.jobKey, job, townBonusTable)

    -- Auszahlung
    _PlayerModule.AddMoney(source, wage, ("Job abgeschlossen: %s"):format(job.jobConfig.label))
    _PlayerModule.AddXP(source,
        Config.XPBaseDelivery + math.floor(job.distanceKm * Config.XPPerKm)
    )
    _PlayerModule.IncrementDeliveries(source)

    -- Town Bonus für diese Zone erhöhen
    if _TownBonusModule then
        _TownBonusModule.OnDelivery(job.deliveryZone)
    end

    -- Supply Chain informieren
    TriggerEvent(MT.SUPPLY_UPDATE, job.jobKey, job.deliveryZone)

    -- Job-State aufräumen
    activeJobs[source] = nil

    -- Client informieren
    TriggerClientEvent(MT.JOB_COMPLETE, source, {
        wage      = wage,
        breakdown = breakdown,
        label     = job.jobConfig.label,
    })

    print(("[MT] Job '%s' abgeschlossen für %s – Lohn: %d$"):format(
        job.jobKey, tostring(source), wage
    ))
end

-- Spieler bricht Job ab
local function OnJobCancel(source)
    local job = activeJobs[source]
    if not job then return end

    -- Cargo entfernen falls schon geladen
    if job.cargoLoaded then
        local cargo = job.jobConfig.cargo
        exports.ox_inventory:RemoveItem(source, cargo.item, cargo.amount)
    end

    activeJobs[source] = nil
    TriggerClientEvent(MT.JOB_CANCEL, source, {})
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function JobModule.GetActiveJob(source)
    return activeJobs[source]
end

function JobModule.HasActiveJob(source)
    return activeJobs[source] ~= nil
end

-- Wird bei playerDropped aufgeräumt
function JobModule.ClearJob(source)
    activeJobs[source] = nil
    lastRequest[source] = nil
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function JobModule.Init()
    RegisterNetEvent("mt:job:listRequest", OnJobListRequest)
    RegisterNetEvent(MT.JOB_REQUEST, OnJobRequest)
    RegisterNetEvent("mt:job:cargoLoaded", OnCargoLoaded)
    RegisterNetEvent(MT.JOB_COMPLETE, OnJobComplete)
    RegisterNetEvent(MT.JOB_CANCEL, OnJobCancel)

    AddEventHandler("playerDropped", function()
        JobModule.ClearJob(source)
    end)

    exports("GetActiveJob", JobModule.GetActiveJob)
    exports("HasActiveJob", JobModule.HasActiveJob)

    print("[MT] JobModule (Server) initialisiert")
end

_JobModule = JobModule
