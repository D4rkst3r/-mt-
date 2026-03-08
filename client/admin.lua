-- ============================================================
--  client/admin.lua
--  Ingame Admin-Menü für: Zonen, Jobs, Fahrzeuge, Fabriken
--
--  Befehl: /mtadmin
--  Nur für Spieler mit Admin-Rank in mt_admins.
-- ============================================================

local AdminClient    = {}

local myRank         = false -- false | 'admin' | 'superadmin'
local pendingZoneKey = nil   -- Für "Zone an aktueller Position erstellen"
local previewZone    = nil   -- ox_lib Zone-Objekt für Live-Preview

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

local function Notify(title, desc, ntype)
    lib.notify({ title = title, description = desc, type = ntype or "inform", duration = 5000 })
end

local function RemovePreview()
    if previewZone then
        previewZone:remove()
        previewZone = nil
    end
end

-- Zeigt eine temporäre Debug-Box (Preview beim Erstellen/Bearbeiten)
local function ShowPreview(coords, size, rotation)
    RemovePreview()
    previewZone = lib.zones.box({
        coords   = coords,
        size     = size or vec3(4, 4, 2),
        rotation = rotation or 0,
        debug    = true,
    })
end

-- Serialisiert vec3 zu plain table für JSON
local function Vec3ToTable(v)
    if not v then return nil end
    return { x = v.x, y = v.y, z = v.z }
end

-- ────────────────────────────────────────────────────────────
--  Zone Menüs
-- ────────────────────────────────────────────────────────────

local function OpenZoneEditMenu(zoneKey, zoneData)
    -- Formular mit den wichtigsten Feldern
    local result = lib.inputDialog("Zone bearbeiten: " .. zoneKey, {
        { type = "input",  label = "Label",           default = zoneData.label or "",                   required = true },
        { type = "number", label = "Größe X",         default = zoneData.size and zoneData.size.x or 4, min = 1,        max = 100 },
        { type = "number", label = "Größe Y",         default = zoneData.size and zoneData.size.y or 4, min = 1,        max = 100 },
        { type = "number", label = "Größe Z",         default = zoneData.size and zoneData.size.z or 2, min = 1,        max = 20 },
        { type = "number", label = "Rotation (Grad)", default = zoneData.rotation or 0,                 min = 0,        max = 360 },
    })
    if not result then return end

    local newData = {}
    for k, v in pairs(zoneData) do newData[k] = v end -- Kopie

    newData.label    = result[1]
    newData.size     = { x = result[2], y = result[3], z = result[4] }
    newData.rotation = result[5]

    -- Preview anzeigen
    local coords     = zoneData.coords
    ShowPreview(coords, vec3(result[2], result[3], result[4]), result[5])

    -- Bestätigen
    local confirm = lib.alertDialog({
        header   = "Zone speichern?",
        content  = ("Label: %s\nGröße: %.0fx%.0fx%.0f\nRotation: %d°"):format(
            result[1], result[2], result[3], result[4], result[5]),
        centered = true,
        cancel   = true,
    })
    RemovePreview()
    if confirm ~= "confirm" then return end

    -- Koordinaten serialisieren
    newData.coords = Vec3ToTable(coords)
    if newData.size then
        newData.size = { x = result[2], y = result[3], z = result[4] }
    end

    TriggerServerEvent("mt:admin:saveZone", { key = zoneKey, zoneData = newData })
    Notify("✅ Zone gespeichert", zoneKey, "success")
end

local function OpenZoneCreateMenu()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local result = lib.inputDialog("Neue Zone erstellen", {
        { type = "input",  label = "Zone-Key (eindeutig, z.B. ladezone_neu)",                       required = true },
        { type = "input",  label = "Label",                                                         required = true },
        { type = "input",  label = "Typ (box / sphere)",                                            default = "box" },
        { type = "number", label = "Größe X",                                                       default = 4,    min = 1, max = 100 },
        { type = "number", label = "Größe Y",                                                       default = 4,    min = 1, max = 100 },
        { type = "number", label = "Größe Z",                                                       default = 2,    min = 1, max = 20 },
        { type = "input",  label = "Target (dispatcher_menu / cargo_laden / cargo_abladen / leer)", default = "" },
    })
    if not result then return end

    local zoneKey  = result[1]:lower():gsub("%s+", "_")
    local zoneType = (result[3] == "sphere") and "sphere" or "box"

    -- Preview
    ShowPreview(coords, vec3(result[4], result[5], result[6]), 0)

    local confirm = lib.alertDialog({
        header   = "Zone erstellen?",
        content  = ("Key: %s\nPosition: %.1f / %.1f / %.1f\nTyp: %s, Größe: %.0fx%.0fx%.0f"):format(
            zoneKey, coords.x, coords.y, coords.z,
            zoneType, result[4], result[5], result[6]),
        centered = true,
        cancel   = true,
    })
    RemovePreview()
    if confirm ~= "confirm" then return end

    local targets = {}
    if result[7] and result[7] ~= "" then
        targets = { result[7] }
    end

    local newZone = {
        type       = zoneType,
        coords     = Vec3ToTable(coords),
        size       = { x = result[4], y = result[5], z = result[6] },
        rotation   = 0,
        label      = result[2],
        targets    = targets,
        debugColor = { 255, 165, 0, 80 },
    }

    TriggerServerEvent("mt:admin:saveZone", { key = zoneKey, zoneData = newZone })
    Notify("✅ Zone erstellt", zoneKey .. " an aktueller Position", "success")
end

local function OpenZoneListMenu(zones)
    if not zones or next(zones) == nil then
        Notify("Keine Zonen", "Keine Zonen in Config vorhanden", "error")
        return
    end

    local options = {}
    for key, data in pairs(zones) do
        table.insert(options, {
            title       = key,
            description = ("[%s] %s"):format(data.type or "?", data.label or ""),
            onSelect    = function()
                -- Untermenü: Bearbeiten / Teleportieren / Löschen
                lib.registerContext({
                    id      = "mt_admin_zone_action",
                    title   = "Zone: " .. key,
                    options = {
                        {
                            title    = "✏️ Bearbeiten",
                            onSelect = function()
                                -- Koordinaten von JSON zurück in vec3
                                if data.coords and type(data.coords) == "table" then
                                    data.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
                                end
                                if data.size and type(data.size) == "table" then
                                    data.size = vec3(data.size.x, data.size.y, data.size.z)
                                end
                                OpenZoneEditMenu(key, data)
                            end,
                        },
                        {
                            title    = "📍 Teleportieren",
                            onSelect = function()
                                local c = data.coords
                                if c then
                                    SetEntityCoords(PlayerPedId(), c.x, c.y, c.z + 1.0, false, false, false, false)
                                end
                            end,
                        },
                        myRank == "superadmin" and {
                            title    = "🗑️ Löschen",
                            onSelect = function()
                                local confirm = lib.alertDialog({
                                    header = "Zone wirklich löschen?",
                                    content = ("'%s' wird permanent entfernt!"):format(key),
                                    centered = true,
                                    cancel = true,
                                })
                                if confirm ~= "confirm" then return end
                                TriggerServerEvent("mt:admin:deleteZone", { key = key })
                                Notify("🗑️ Zone gelöscht", key, "warning")
                            end,
                        } or nil,
                    },
                })
                lib.showContext("mt_admin_zone_action")
            end,
        })
    end

    table.sort(options, function(a, b) return a.title < b.title end)
    table.insert(options, 1, {
        title    = "➕ Neue Zone (an aktueller Position)",
        onSelect = OpenZoneCreateMenu,
    })

    lib.registerContext({ id = "mt_admin_zones", title = "🗺️ Zonen", options = options })
    lib.showContext("mt_admin_zones")
end

-- ────────────────────────────────────────────────────────────
--  Job Menüs
-- ────────────────────────────────────────────────────────────

local function OpenJobEditMenu(jobKey, jobData)
    local result = lib.inputDialog("Job bearbeiten: " .. jobKey, {
        { type = "input",  label = "Label",                  default = jobData.label or "",       required = true },
        { type = "number", label = "Min. Level",             default = jobData.minLevel or 1,     min = 1,        max = 50 },
        { type = "number", label = "Basislohn ($)",          default = jobData.baseWage or 1000,  min = 0,        max = 100000 },
        { type = "number", label = "Lohn pro km ($)",        default = jobData.wagePerKm or 100,  min = 0,        max = 5000 },
        { type = "number", label = "Lohn pro Tonne ($)",     default = jobData.wagePerTon or 50,  min = 0,        max = 5000 },
        { type = "number", label = "Zeitlimit (Min, 0=aus)", default = jobData.timeLimitMin or 0, min = 0,        max = 120 },
    })
    if not result then return end

    local newData = {}
    for k, v in pairs(jobData) do newData[k] = v end

    newData.label        = result[1]
    newData.minLevel     = result[2]
    newData.baseWage     = result[3]
    newData.wagePerKm    = result[4]
    newData.wagePerTon   = result[5]
    newData.timeLimitMin = result[6] > 0 and result[6] or nil
    newData.timeBonus    = result[6] > 0

    TriggerServerEvent("mt:admin:saveJob", { key = jobKey, jobData = newData })
    Notify("✅ Job gespeichert",
        ("%s: %d$ Basis, Level %d+"):format(result[1], result[3], result[2]),
        "success")
end

local function OpenJobListMenu(jobs)
    local options = {}
    for key, data in pairs(jobs) do
        table.insert(options, {
            title       = key,
            description = ("%s | Level %d | %d$ Basis"):format(data.label or "", data.minLevel or 1, data.baseWage or 0),
            onSelect    = function() OpenJobEditMenu(key, data) end,
        })
    end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = "mt_admin_jobs", title = "📋 Jobs", options = options })
    lib.showContext("mt_admin_jobs")
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug Menüs
-- ────────────────────────────────────────────────────────────

local function OpenVehicleEditMenu(vKey, vData)
    local result = lib.inputDialog("Fahrzeug bearbeiten: " .. vKey, {
        { type = "input",  label = "Label",     default = vData.label or "",    required = true },
        { type = "number", label = "Preis ($)", default = vData.price or 50000, min = 0,        max = 10000000 },
    })
    if not result then return end

    local newData = {}
    for k, v in pairs(vData) do newData[k] = v end
    newData.label = result[1]
    newData.price = result[2]

    TriggerServerEvent("mt:admin:saveVehicle", { key = vKey, vehicleData = newData })
    Notify("✅ Fahrzeug gespeichert", ("%s: %d$"):format(result[1], result[2]), "success")
end

local function OpenVehicleListMenu(vehicles)
    if not vehicles or next(vehicles) == nil then
        Notify("Keine Fahrzeuge", "Keine Fahrzeuge in Config", "error")
        return
    end
    local options = {}
    for key, data in pairs(vehicles) do
        table.insert(options, {
            title       = key,
            description = ("%s | %d$"):format(data.label or "", data.price or 0),
            onSelect    = function() OpenVehicleEditMenu(key, data) end,
        })
    end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = "mt_admin_vehicles", title = "🚛 Fahrzeuge", options = options })
    lib.showContext("mt_admin_vehicles")
end

-- ────────────────────────────────────────────────────────────
--  Fabrik Menüs
-- ────────────────────────────────────────────────────────────

local function OpenFactoryEditMenu(fKey, fData)
    local result = lib.inputDialog("Fabrik bearbeiten: " .. fKey, {
        { type = "input",  label = "Label",                       default = fData.label or "",      required = true },
        { type = "number", label = "Zykluszeit (Min)",            default = fData.cycleMin or 10,   min = 1,        max = 240 },
        { type = "number", label = "Input benötigt (pro Zyklus)", default = fData.inputNeeded or 1, min = 1,        max = 100 },
        { type = "number", label = "Output pro Zyklus",           default = fData.outputPer or 1,   min = 1,        max = 100 },
    })
    if not result then return end

    local newData = {}
    for k, v in pairs(fData) do newData[k] = v end
    newData.label       = result[1]
    newData.cycleMin    = result[2]
    newData.inputNeeded = result[3]
    newData.outputPer   = result[4]

    TriggerServerEvent("mt:admin:saveFactory", { key = fKey, factoryData = newData })
    Notify("✅ Fabrik gespeichert", ("%s: %d Min/Zyklus"):format(result[1], result[2]), "success")
end

local function OpenFactoryListMenu(factories)
    if not factories or next(factories) == nil then
        Notify("Keine Fabriken", "Keine Fabriken in Config", "error")
        return
    end
    local options = {}
    for key, data in pairs(factories) do
        table.insert(options, {
            title       = key,
            description = ("%s | %d Min Zyklus"):format(data.label or "", data.cycleMin or 0),
            onSelect    = function() OpenFactoryEditMenu(key, data) end,
        })
    end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = "mt_admin_factories", title = "🏭 Fabriken", options = options })
    lib.showContext("mt_admin_factories")
end

-- ────────────────────────────────────────────────────────────
--  Haupt-Menü
-- ────────────────────────────────────────────────────────────

local function OpenMainMenu()
    lib.registerContext({
        id      = "mt_admin_main",
        title   = ("🛠️ MotorTown Admin [%s]"):format(myRank),
        options = {
            {
                title       = "🗺️ Zonen verwalten",
                description = "Erstellen, bearbeiten, löschen",
                onSelect    = function()
                    TriggerServerEvent("mt:admin:fetchConfig", { category = "zone" })
                end,
            },
            {
                title       = "📋 Jobs verwalten",
                description = "Lohn, Level, Limits anpassen",
                onSelect    = function()
                    TriggerServerEvent("mt:admin:fetchConfig", { category = "job" })
                end,
            },
            {
                title       = "🚛 Fahrzeuge verwalten",
                description = "Preise und Labels anpassen",
                onSelect    = function()
                    TriggerServerEvent("mt:admin:fetchConfig", { category = "vehicle" })
                end,
            },
            {
                title       = "🏭 Fabriken verwalten",
                description = "Zykluszeiten und Output anpassen",
                onSelect    = function()
                    TriggerServerEvent("mt:admin:fetchConfig", { category = "factory" })
                end,
            },
        },
    })
    lib.showContext("mt_admin_main")
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

-- Server schickt Config-Daten zurück
RegisterNetEvent("mt:admin:configData", function(payload)
    if not payload then return end
    local cat  = payload.category
    local data = payload.data

    if cat == "zone" then OpenZoneListMenu(data) end
    if cat == "job" then OpenJobListMenu(data) end
    if cat == "vehicle" then OpenVehicleListMenu(data) end
    if cat == "factory" then OpenFactoryListMenu(data) end
end)

-- Server bestätigt Rank
RegisterNetEvent("mt:admin:rank", function(payload)
    myRank = payload and payload.rank or false
    if myRank then
        OpenMainMenu()
    else
        Notify("Kein Zugriff", "Du bist kein Admin.", "error")
    end
end)

-- Fehlermeldung vom Server
RegisterNetEvent("mt:admin:error", function(msg)
    Notify("Admin-Fehler", msg, "error")
end)

-- ────────────────────────────────────────────────────────────
--  Zonen Live-Update (alle Clients empfangen das)
--  Wird von zones.lua verarbeitet – hier nur Weiterleitung
-- ────────────────────────────────────────────────────────────
-- (Handler in zones.lua registriert, da ZoneModule die Zonen verwaltet)

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function AdminClient.Init()
    RegisterCommand("mtadmin", function()
        -- Rank beim Server anfragen (verhindert clientseitiges Spoofing)
        TriggerServerEvent("mt:admin:whoami")
    end, false)

    print("[MT] AdminClient initialisiert – /mtadmin zum Öffnen")
end

_AdminClient = AdminClient
