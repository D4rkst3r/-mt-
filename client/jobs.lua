-- ============================================================
--  client/jobs.lua
-- ============================================================

local JobModule       = {}
local currentJob      = nil
local activeBlips     = {}
local spawnedTrailers = {} -- [vehicleType] = trailerHandle (gespawnte Trailer)

-- ────────────────────────────────────────────────────────────
--  Trailer-Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

-- Gibt den angekoppelten Trailer zurück (oder nil)
local function GetAttachedTrailer(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    local found, trailer = GetVehicleTrailerVehicle(vehicle)
    if found and trailer and trailer ~= 0 then
        return trailer
    end
    return nil
end

-- Prüft ob der angekoppelte Trailer zum Job-Typ passt
local function IsCorrectTrailerAttached(vehicle, vehicleType)
    -- Kein Trailer nötig für diesen Typ
    if not Config.RequiresTrailer or not Config.RequiresTrailer[vehicleType] then
        return true
    end

    local trailer = GetAttachedTrailer(vehicle)
    if not trailer then return false end

    local allowedModels = Config.TrailerModels and Config.TrailerModels[vehicleType]
    if not allowedModels then return true end -- kein Filter → alles ok

    local trailerModel = GetEntityModel(trailer)
    for _, modelName in ipairs(allowedModels) do
        if trailerModel == GetHashKey(modelName) then
            return true
        end
    end
    return false
end

-- Spawnt einen Trailer hinter dem Spieler
local function SpawnTrailer(vehicleType, callback)
    local models = Config.TrailerModels and Config.TrailerModels[vehicleType]
    if not models or #models == 0 then
        callback(nil, nil)
        return
    end

    CreateThread(function()
        local modelName = models[1]
        local modelHash = GetHashKey(modelName)

        RequestModel(modelHash)
        local t = 0
        while not HasModelLoaded(modelHash) do
            Wait(100)
            t = t + 1
            if t > 50 then
                print("[MT] Trailer model timeout: " .. modelName)
                SetModelAsNoLongerNeeded(modelHash)
                callback(nil, nil)
                return
            end
        end

        -- Trailer 15m hinter dem Spieler spawnen
        local ped     = PlayerPedId()
        local heading = GetEntityHeading(ped)
        local pos     = GetEntityCoords(ped)
        local rad     = math.rad(heading + 180.0)
        local spawnX  = pos.x + math.sin(rad) * 15.0
        local spawnY  = pos.y + math.cos(rad) * 15.0
        local spawnZ  = pos.z

        local trailer = CreateVehicle(modelHash, spawnX, spawnY, spawnZ, heading, false, false)
        SetEntityAsMissionEntity(trailer, true, true)
        SetModelAsNoLongerNeeded(modelHash)

        -- Prüfen ob Entity gültig
        if not DoesEntityExist(trailer) or trailer == 0 then
            print("[MT] Trailer spawn fehlgeschlagen: " .. modelName)
            callback(nil, nil)
            return
        end

        spawnedTrailers[vehicleType] = trailer
        print(("[MT] Trailer gespawnt: %s handle=%d"):format(modelName, trailer))
        callback(trailer, modelName)
    end)
end

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
--  Wegpunkt
-- ────────────────────────────────────────────────────────────

local function SetWaypointToZone(zoneKey)
    local zone = Config.Zones[zoneKey]
    if not zone then return end
    local coords = zone.coords
    if zone.type == "poly" then
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
--  Fahrzeugtyp des aktuellen Fahrzeugs
-- ────────────────────────────────────────────────────────────

local function GetCurrentVehicleType()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end
    local hash = GetEntityModel(vehicle)
    if Config.VehicleTypes then
        for vType, models in pairs(Config.VehicleTypes) do
            for _, m in ipairs(models) do
                if GetHashKey(m) == hash then return vType end
            end
        end
    end
    return "unknown"
end

-- ────────────────────────────────────────────────────────────
--  Dispatcher Menü
-- ────────────────────────────────────────────────────────────

local function OpenDispatcherMenu(jobs)
    if not jobs then return end
    table.sort(jobs, function(a, b) return (a.minLevel or 0) < (b.minLevel or 0) end)

    local options = {}
    for _, job in ipairs(jobs) do
        if job.locked then
            table.insert(options, {
                title       = ("🔒 %s"):format(job.label),
                disabled    = true,
                description = ("Benötigt Level %d"):format(job.minLevel),
            })
        else
            local trailerHint = ""
            if job.vehicleType and Config.RequiresTrailer and Config.RequiresTrailer[job.vehicleType] then
                trailerHint = " | 🚛 Trailer erforderlich"
            end
            table.insert(options, {
                title       = job.label,
                description = ("%s\nBasislohn: %s | Fahrzeug: %s%s"):format(
                    job.description or "", Utils.FormatMoney(job.baseWage),
                    job.vehicleType or "beliebig", trailerHint),
                onSelect    = function()
                    local vType = GetCurrentVehicleType()
                    TriggerServerEvent(MT.JOB_REQUEST, {
                        jobKey      = job.key,
                        vehicleType = vType,
                    })
                end,
            })
        end
    end
    table.insert(options, { title = "Abbrechen", onSelect = function() end })

    lib.registerContext({ id = "mt_dispatcher", title = "📋 Job-Auswahl", options = options })
    lib.showContext("mt_dispatcher")
end

-- ────────────────────────────────────────────────────────────
--  Cargo laden
-- ────────────────────────────────────────────────────────────

local function StartLoading(zoneName, zoneData)
    if not currentJob then
        lib.notify({ title = "Kein aktiver Job", type = "error" })
        return
    end
    if zoneName ~= currentJob.pickupZone then
        lib.notify({
            title = "Falsche Zone",
            description = ("Abholpunkt: %s"):format(currentJob.pickupZone),
            type = "error"
        })
        return
    end
    if currentJob.cargoLoaded then
        lib.notify({ title = "Cargo bereits geladen", type = "warning" })
        return
    end

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        lib.notify({ title = "Kein Fahrzeug", description = "Steige in dein Fahrzeug ein.", type = "error" })
        return
    end

    -- ── Trailer-Check ────────────────────────────────────────
    local vType = currentJob.vehicleType

    if vType and Config.RequiresTrailer and Config.RequiresTrailer[vType] then
        local trailerOk = IsCorrectTrailerAttached(vehicle, vType)

        if not trailerOk then
            -- Trailer spawnen anbieten
            -- WICHTIG: lib.alertDialog braucht eigenen Thread wenn aus Event-Handler aufgerufen
            CreateThread(function()
                local confirm = lib.alertDialog({
                    header   = "Kein Trailer angekoppelt",
                    content  = ("Dieser Job (%s) erfordert einen **%s-Trailer**.\n\nSoll ein Trailer gespawnt werden?")
                        :format(currentJob.label, vType),
                    centered = true,
                    cancel   = true,
                })
                if confirm == "confirm" then
                    SpawnTrailer(vType, function(trailer, modelName)
                        if trailer then
                            lib.notify({
                                title       = "🚛 Trailer gespawnt",
                                description = "Er steht hinter dir – koppel ihn an und komm zurück.",
                                type        = "inform",
                                duration    = 7000,
                            })
                            local tc = GetEntityCoords(trailer)
                            if activeBlips.trailer and DoesBlipExist(activeBlips.trailer) then
                                RemoveBlip(activeBlips.trailer)
                            end
                            activeBlips.trailer = CreateBlip(tc, 479, 4, "Dein Trailer")
                        else
                            lib.notify({
                                title = "Spawn fehlgeschlagen",
                                description = "Trailer konnte nicht gespawnt werden.",
                                type = "error"
                            })
                        end
                    end)
                end
            end)
            return
        end
    end

    local success = lib.progressBar({
        duration     = Config.LoadProgressMs,
        label        = ("Lade %s..."):format(currentJob.cargo.label),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = false, car = false, combat = true },
        anim         = { dict = "anim@heists@box_carry@", clip = "idle" },
    })

    if not success then
        lib.notify({ title = "Laden abgebrochen", type = "warning" })
        return
    end

    -- Trailer-Blip entfernen
    if activeBlips.trailer and DoesBlipExist(activeBlips.trailer) then
        RemoveBlip(activeBlips.trailer)
        activeBlips.trailer = nil
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
            title = "Falscher Ablieferort",
            description = ("Liefere zu: %s"):format(currentJob.deliveryZone),
            type = "error"
        })
        return
    end
    if not currentJob.cargoLoaded then
        lib.notify({ title = "Kein Cargo", description = "Hole zuerst das Cargo ab.", type = "error" })
        return
    end

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        lib.notify({ title = "Kein Fahrzeug", type = "error" })
        return
    end

    -- Trailer muss noch dran sein beim Abliefern
    local vType = currentJob.vehicleType
    if vType and Config.RequiresTrailer and Config.RequiresTrailer[vType] then
        if not IsCorrectTrailerAttached(vehicle, vType) then
            lib.notify({
                title       = "Trailer nicht angekoppelt",
                description = "Der Trailer muss beim Abliefern angekoppelt sein.",
                type        = "error",
            })
            return
        end
    end

    local success = lib.progressBar({
        duration     = Config.UnloadProgressMs,
        label        = ("Liefere %s ab..."):format(currentJob.cargo.label),
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = false, car = false, combat = true },
        anim         = { dict = "anim@heists@box_carry@", clip = "idle" },
    })
    if not success then return end

    -- Trailer nach Ablieferung entkoppeln + löschen
    local vType2 = currentJob.vehicleType
    if vType2 and Config.RequiresTrailer and Config.RequiresTrailer[vType2] then
        local trailer = GetAttachedTrailer(vehicle)
        if trailer then
            DetachVehicleFromTrailer(vehicle)
            Wait(500)
            DeleteVehicle(trailer)
        end
        -- Gespawnten Trailer aus Cache entfernen
        spawnedTrailers[vType2] = nil
    end

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
        vehicleType  = data.vehicleType,
        cargoLoaded  = false,
        multiStop    = data.multiStop,
        stopCount    = data.stopCount,
    }

    local pickupZone = Config.Zones[data.pickupZone]
    if pickupZone and pickupZone.coords then
        activeBlips.pickup = CreateBlip(pickupZone.coords,
            data.blipSprite or 477, data.blipColor or 3,
            ("Abholen: %s"):format(data.label))
        SetWaypointToZone(data.pickupZone)
    end

    -- Trailer-Hinweis bei Job-Start
    local trailerMsg = ""
    if data.vehicleType and Config.RequiresTrailer and Config.RequiresTrailer[data.vehicleType] then
        trailerMsg = "\n🚛 Trailer ankoppeln nicht vergessen!"
    end

    lib.notify({
        title       = ("📦 Job: %s"):format(data.label),
        description = ("Fahre zur Abholzone (%s).%s"):format(data.pickupZone, trailerMsg),
        type        = "inform",
        duration    = 7000,
    })
end

local function OnCargoLoaded(data)
    if not currentJob then return end
    currentJob.cargoLoaded = data.cargoLoaded

    if data.multiStop and not data.cargoLoaded then
        lib.notify({
            title = ("✅ Stop %d/%d erledigt"):format(data.stopsDone, data.stopCount),
            description = "Fahre zurück zur Ladezone für den nächsten Stop.",
            type = "success",
            duration = 5000,
        })
        SetWaypointToZone(currentJob.pickupZone)
        return
    end

    if activeBlips.pickup and DoesBlipExist(activeBlips.pickup) then
        RemoveBlip(activeBlips.pickup)
        activeBlips.pickup = nil
    end

    local deliveryZone = Config.Zones[currentJob.deliveryZone]
    if deliveryZone and deliveryZone.coords then
        activeBlips.delivery = CreateBlip(deliveryZone.coords, 477, 5,
            ("Liefern: %s"):format(currentJob.label))
        SetWaypointToZone(currentJob.deliveryZone)
    end

    local msg = data.multiStop
        and ("Alle %d Stops erledigt – fahre zum Ablieferort!"):format(data.stopCount)
        or "Cargo geladen – fahre zum Ablieferort!"
    lib.notify({ title = "✅ Cargo geladen", description = msg, type = "success" })
end

local function OnJobComplete(data)
    ClearBlips()
    SetWaypointOff()
    currentJob = nil

    local desc = ("Lohn: %s\nDistanz: %.1f km | Town-Bonus: %.2fx | Zeit: %.2fx"):format(
        Utils.FormatMoney(data.wage),
        data.breakdown.distKm,
        data.breakdown.townBonus,
        data.breakdown.timeMult)

    lib.notify({
        title = "🎉 Job abgeschlossen!",
        description = desc,
        type = "success",
        duration = 10000
    })
    TriggerEvent("mt:job:localComplete", data)
end

local function OnJobCancel()
    ClearBlips()
    SetWaypointOff()
    currentJob = nil
    lib.notify({ title = "Job abgebrochen", type = "warning" })
end

local function OnJobValidate(data)
    if data.error then
        lib.notify({ title = "Fehler", description = data.error, type = "error", duration = 6000 })
        return
    end
    if data.supplyAlert then
        lib.notify({
            title = ("📦 Supply-Job: %s"):format(data.label),
            description = ("Die %s hat Ware bereit!"):format(data.factory),
            type = "inform",
            duration = 8000
        })
        return
    end
    if data.jobs then OpenDispatcherMenu(data.jobs) end
end

local function OnZoneEnter(zoneName, zoneData)
    if not currentJob then return end
    if zoneName == currentJob.pickupZone and not currentJob.cargoLoaded then
        local hint = ""
        local vType = currentJob.vehicleType
        if vType and Config.RequiresTrailer and Config.RequiresTrailer[vType] then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh and veh ~= 0 and not IsCorrectTrailerAttached(veh, vType) then
                hint = "\n⚠️ Kein Trailer angekoppelt!"
            end
        end
        lib.notify({
            title = "Abholzone erreicht",
            description = ("Nutze [E] um %s zu laden%s"):format(currentJob.cargo.label, hint),
            type = "inform",
            duration = 5000
        })
    elseif zoneName == currentJob.deliveryZone and currentJob.cargoLoaded then
        lib.notify({
            title = "Ablieferzone erreicht",
            description = "Nutze [E] um das Cargo abzuliefern.",
            type = "inform",
            duration = 4000
        })
    end
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function JobModule.GetCurrentJob() return currentJob end

function JobModule.HasJob() return currentJob ~= nil end

function JobModule.CancelJob()
    if not currentJob then return end
    TriggerServerEvent(MT.JOB_CANCEL)
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function JobModule.Init()
    RegisterNetEvent(MT.JOB_START, OnJobStart)
    RegisterNetEvent(MT.JOB_CARGO_LOADED, OnCargoLoaded)
    RegisterNetEvent(MT.JOB_COMPLETE, OnJobComplete)
    RegisterNetEvent(MT.JOB_CANCEL, OnJobCancel)
    RegisterNetEvent(MT.JOB_VALIDATE, OnJobValidate)

    AddEventHandler(MT.ZONE_ENTER, OnZoneEnter)
    AddEventHandler("mt:ui:openDispatcher", function()
        TriggerServerEvent("mt:job:listRequest")
    end)
    AddEventHandler("mt:job:startLoad", function(zn, zd) StartLoading(zn, zd) end)
    AddEventHandler("mt:job:startUnload", function(zn, zd) StartUnloading(zn, zd) end)

    RegisterCommand("jobabbruch", function()
        if JobModule.HasJob() then JobModule.CancelJob() end
    end, false)

    exports("GetCurrentJob", JobModule.GetCurrentJob)
    exports("HasJob", JobModule.HasJob)
    exports("CancelJob", JobModule.CancelJob)

    print("[MT] JobModule (Client) initialisiert")
end

_JobModule = JobModule
