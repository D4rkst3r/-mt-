-- ============================================================
--  client/jobs.lua
--  Zuständig für: Dispatcher-Menü, Cargo laden/abladen,
--  Wegpunkte setzen, Blips, Fortschrittsanzeigen.
--
--  Schreibt NIE direkt Geld oder XP – sendet Events an Server.
-- ============================================================

local JobModule    = {}

-- Lokaler Job-State (gespiegelt vom Server)
local currentJob   = nil
local activeBlips  = {}  -- Aktive Map-Blips: { pickup, delivery }
local activeThread = nil -- Der laufende Proximity-Check Thread

-- ────────────────────────────────────────────────────────────
--  Blip Helfer
-- ────────────────────────────────────────────────────────────

local function CreateBlip(coords, sprite, color, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function ClearBlips()
    for _, blip in pairs(activeBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    activeBlips = {}
end

-- ────────────────────────────────────────────────────────────
--  Wegpunkt setzen (GTA GPS)
-- ────────────────────────────────────────────────────────────

local function SetWaypointToZone(zoneKey)
    local zone = Config.Zones[zoneKey]
    if not zone then return end

    local coords = zone.coords
    if zone.type == "poly" then
        -- Mittelpunkt der Poly-Zone
        local cx, cy = 0, 0
        for _, p in ipairs(zone.points) do
            cx = cx + p.x; cy = cy + p.y
        end
        local n = #zone.points
        coords = vec3(cx / n, cy / n, 0.0)
    end

    SetNewWaypoint(coords.x, coords.y)
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeugtyp des aktuellen Fahrzeugs ermitteln
-- ────────────────────────────────────────────────────────────

local function GetCurrentVehicleType()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end

    local model = GetEntityModel(vehicle)
    local hash  = model

    -- Gegen Config.VehicleTypes mappen (aus config/vehicles.lua)
    if Config.VehicleTypes then
        for vType, models in pairs(Config.VehicleTypes) do
            for _, m in ipairs(models) do
                if GetHashKey(m) == hash then
                    return vType
                end
            end
        end
    end
    return "unknown"
end

-- ────────────────────────────────────────────────────────────
--  Dispatcher Menü (ox_lib context menu)
-- ────────────────────────────────────────────────────────────

local function OpenDispatcherMenu(jobs)
    if not jobs then return end

    local options = {}

    -- Jobs nach Level sortieren
    table.sort(jobs, function(a, b)
        return (a.minLevel or 0) < (b.minLevel or 0)
    end)

    for _, job in ipairs(jobs) do
        if job.locked then
            table.insert(options, {
                title       = ("🔒 %s"):format(job.label),
                disabled    = true,
                description = ("Benötigt Level %d"):format(job.minLevel),
            })
        else
            table.insert(options, {
                title       = job.label,
                description = ("%s\nBasislohn: %s | Fahrzeug: %s"):format(
                    job.description or "",
                    Utils.FormatMoney(job.baseWage),
                    job.vehicleType or "beliebig"
                ),
                onSelect    = function()
                    -- Fahrzeugtyp prüfen bevor an Server schicken
                    local vType = GetCurrentVehicleType()
                    TriggerServerEvent(MT.JOB_REQUEST, {
                        jobKey      = job.key,
                        vehicleType = vType,
                    })
                end,
            })
        end
    end

    table.insert(options, {
        title    = "Abbrechen",
        onSelect = function() end,
    })

    lib.registerContext({
        id      = "mt_dispatcher",
        title   = "📋 Job-Auswahl",
        options = options,
    })
    lib.showContext("mt_dispatcher")
end

-- ────────────────────────────────────────────────────────────
--  Job aktiv: Proximity-Thread für automatische Interaktion
--  (Spieler fährt in Zone → Lade/Ablade-Prompt erscheint)
-- ────────────────────────────────────────────────────────────

local function StartJobThread()
    if activeThread then return end

    activeThread = CreateThread(function()
        while currentJob do
            Wait(500)

            local ped   = PlayerPedId()
            local pos   = GetEntityCoords(ped)
            local inVeh = IsPedInAnyVehicle(ped, false)

            if not inVeh then
                -- Kleinen Hinweis zeigen falls nicht im Fahrzeug
            end
        end
        activeThread = nil
    end)
end

-- ────────────────────────────────────────────────────────────
--  Cargo laden (ox_lib progressbar → Server-Event)
-- ────────────────────────────────────────────────────────────

local function StartLoading(zoneName, zoneData)
    if not currentJob then
        lib.notify({ title = "Kein aktiver Job", type = "error" })
        return
    end

    if zoneName ~= currentJob.pickupZone then
        lib.notify({
            title       = "Falsche Zone",
            description = ("Abholpunkt ist: %s"):format(currentJob.pickupZone),
            type        = "error",
        })
        return
    end

    if currentJob.cargoLoaded then
        lib.notify({ title = "Cargo bereits geladen", type = "warning" })
        return
    end

    -- Muss im Fahrzeug sitzen
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        lib.notify({
            title       = "Kein Fahrzeug",
            description = "Steige in dein Fahrzeug ein um zu laden.",
            type        = "error",
        })
        return
    end

    -- Progressbar
    local success = lib.progressBar({
        duration     = Config.LoadProgressMs,
        label        = ("Lade %s..."):format(currentJob.cargo.label),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = false, car = false, combat = true },
        anim         = {
            dict = "anim@heists@box_carry@",
            clip = "idle",
        },
    })

    if not success then
        lib.notify({ title = "Laden abgebrochen", type = "warning" })
        return
    end

    TriggerServerEvent(MT.JOB_CARGO_LOADED, { zone = zoneName })
end

-- ────────────────────────────────────────────────────────────
--  Cargo abladen
-- ────────────────────────────────────────────────────────────

local function StartUnloading(zoneName, zoneData)
    if not currentJob then
        lib.notify({ title = "Kein aktiver Job", type = "error" })
        return
    end

    if zoneName ~= currentJob.deliveryZone then
        lib.notify({
            title       = "Falscher Ablieferort",
            description = ("Liefere zu: %s"):format(currentJob.deliveryZone),
            type        = "error",
        })
        return
    end

    if not currentJob.cargoLoaded then
        lib.notify({
            title       = "Kein Cargo",
            description = "Hole zuerst das Cargo ab.",
            type        = "error",
        })
        return
    end

    local success = lib.progressBar({
        duration     = Config.UnloadProgressMs,
        label        = ("Liefere %s ab..."):format(currentJob.cargo.label),
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = false, car = false, combat = true },
        anim         = {
            dict = "anim@heists@box_carry@",
            clip = "idle",
        },
    })

    if not success then return end

    TriggerServerEvent(MT.JOB_COMPLETE, { zone = zoneName })
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

local function OnJobStart(data)
    currentJob = {
        jobKey       = data.jobKey,
        label        = data.label,
        pickupZone   = data.pickupZone,
        deliveryZone = data.deliveryZone,
        distanceKm   = data.distanceKm,
        cargo        = data.cargo,
        cargoLoaded  = false,
        multiStop    = data.multiStop,
        stopCount    = data.stopCount,
    }

    -- Blip für Abholpunkt
    local pickupZone = Config.Zones[data.pickupZone]
    if pickupZone and pickupZone.coords then
        activeBlips.pickup = CreateBlip(
            pickupZone.coords,
            data.blipSprite or 477,
            data.blipColor or 3,
            ("Abholen: %s"):format(data.label)
        )
        -- Wegpunkt setzen
        SetWaypointToZone(data.pickupZone)
    end

    lib.notify({
        title       = ("📦 Job: %s"):format(data.label),
        description = ("Fahre zur Abholzone (%s)."):format(data.pickupZone),
        type        = "inform",
        duration    = 7000,
    })

    StartJobThread()
end

local function OnCargoLoaded(data)
    if not currentJob then return end
    currentJob.cargoLoaded = data.cargoLoaded

    if data.multiStop and not data.cargoLoaded then
        -- Zwischenstopp: Spieler muss zurück zur Pickup-Zone für den nächsten Stop
        lib.notify({
            title       = ("✅ Stop %d/%d erledigt"):format(data.stopsDone, data.stopCount),
            description = "Fahre zurück zur Ladezone für den nächsten Stop.",
            type        = "success",
            duration    = 5000,
        })
        -- Pickup-Blip bleibt, Wegpunkt zurück zur Pickup-Zone setzen
        SetWaypointToZone(currentJob.pickupZone)
        return
    end

    -- Letzter Stop (oder kein multiStop): Pickup-Blip entfernen, Delivery setzen
    if activeBlips.pickup and DoesBlipExist(activeBlips.pickup) then
        RemoveBlip(activeBlips.pickup)
        activeBlips.pickup = nil
    end

    local deliveryZone = Config.Zones[currentJob.deliveryZone]
    if deliveryZone and deliveryZone.coords then
        activeBlips.delivery = CreateBlip(
            deliveryZone.coords,
            477,
            5,
            ("Liefern: %s"):format(currentJob.label)
        )
        SetWaypointToZone(currentJob.deliveryZone)
    end

    local msg = data.multiStop
        and ("Alle %d Stops erledigt – fahre zum Ablieferort!"):format(data.stopCount)
        or "Cargo geladen – fahre zum Ablieferort!"

    lib.notify({ title = "✅ Cargo geladen", description = msg, type = "success" })
end

local function OnJobComplete(data)
    ClearBlips()

    -- Wegpunkt löschen
    SetWaypointOff()

    currentJob = nil

    -- Detaillierte Lohn-Anzeige
    local desc = ("Lohn: %s\nDistanz: %.1f km | Town-Bonus: %.2fx | Zeit: %.2fx"):format(
        Utils.FormatMoney(data.wage),
        data.breakdown.distKm,
        data.breakdown.townBonus,
        data.breakdown.timeMult
    )

    lib.notify({
        title       = "🎉 Job abgeschlossen!",
        description = desc,
        type        = "success",
        duration    = 10000,
    })

    -- HUD-Update triggern
    TriggerEvent("mt:job:localComplete", data)
end

local function OnJobCancel()
    ClearBlips()
    SetWaypointOff()
    currentJob = nil

    lib.notify({ title = "Job abgebrochen", type = "warning" })
    -- KEIN TriggerEvent(MT.JOB_CANCEL) hier! Das wäre ein Infinite Loop,
    -- weil dieser Handler selbst via RegisterNetEvent auf MT.JOB_CANCEL hört.
    -- Das HUD bekommt das NetEvent vom Server direkt via AddEventHandler.
end

-- Server schickt Validierungsfeedback (Fehler oder Job-Liste)
local function OnJobValidate(data)
    if data.error then
        lib.notify({
            title       = "Fehler",
            description = data.error,
            type        = "error",
            duration    = 6000,
        })
        return
    end
    -- Supply-Chain-Alert: Fabrik hat Output verfügbar → Job empfohlen
    if data.supplyAlert then
        lib.notify({
            title       = ("📦 Supply-Job: %s"):format(data.label),
            description = ("Die %s hat Ware bereit – jetzt liefern!"):format(data.factory),
            type        = "inform",
            duration    = 8000,
        })
        return
    end
    if data.jobs then
        OpenDispatcherMenu(data.jobs)
    end
end

-- ────────────────────────────────────────────────────────────
--  Zone-Event Listener (aus client/zones.lua)
-- ────────────────────────────────────────────────────────────

local function OnZoneEnter(zoneName, zoneData)
    -- Automatisch prüfen ob Enter-Zone relevant für aktiven Job
    if not currentJob then return end

    if zoneName == currentJob.pickupZone and not currentJob.cargoLoaded then
        lib.notify({
            title       = "Abholzone erreicht",
            description = ("Nutze [E] um %s zu laden"):format(currentJob.cargo.label),
            type        = "inform",
            duration    = 4000,
        })
    elseif zoneName == currentJob.deliveryZone and currentJob.cargoLoaded then
        lib.notify({
            title       = "Ablieferzone erreicht",
            description = "Nutze [E] um das Cargo abzuliefern.",
            type        = "inform",
            duration    = 4000,
        })
    end
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function JobModule.GetCurrentJob()
    return currentJob
end

function JobModule.HasJob()
    return currentJob ~= nil
end

function JobModule.CancelJob()
    if not currentJob then return end
    TriggerServerEvent(MT.JOB_CANCEL)
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function JobModule.Init()
    -- Net Events registrieren
    RegisterNetEvent(MT.JOB_START, OnJobStart)
    RegisterNetEvent(MT.JOB_CARGO_LOADED, OnCargoLoaded)
    RegisterNetEvent(MT.JOB_COMPLETE, OnJobComplete)
    RegisterNetEvent(MT.JOB_CANCEL, OnJobCancel)
    RegisterNetEvent(MT.JOB_VALIDATE, OnJobValidate)

    -- Lokale Events (von zones.lua und UI)
    AddEventHandler(MT.ZONE_ENTER, OnZoneEnter)
    AddEventHandler("mt:ui:openDispatcher", function(zoneName, zoneData)
        -- Server nach Job-Liste fragen
        TriggerServerEvent("mt:job:listRequest")
    end)
    AddEventHandler("mt:job:startLoad", function(zoneName, zoneData)
        StartLoading(zoneName, zoneData)
    end)
    AddEventHandler("mt:job:startUnload", function(zoneName, zoneData)
        StartUnloading(zoneName, zoneData)
    end)

    -- ESC zum Abbrechen (nur wenn Job aktiv)
    RegisterCommand("jobabbruch", function()
        if JobModule.HasJob() then
            JobModule.CancelJob()
        end
    end, false)

    exports("GetCurrentJob", JobModule.GetCurrentJob)
    exports("HasJob", JobModule.HasJob)
    exports("CancelJob", JobModule.CancelJob)

    print("[MT] JobModule (Client) initialisiert")
end

_JobModule = JobModule
