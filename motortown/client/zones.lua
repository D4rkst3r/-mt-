-- ============================================================
--  client/zones.lua
--  Erstellt alle Zonen aus Config.Zones via ox_lib,
--  registriert ox_target Punkte und feuert lokale
--  Enter/Exit Events für andere Module.
--
--  Andere Module hören auf:
--    AddEventHandler(MT.ZONE_ENTER, function(zoneName, zoneData) end)
--    AddEventHandler(MT.ZONE_EXIT,  function(zoneName) end)
-- ============================================================

local ZoneModule = {}

-- Aktive ox_lib Zone-Objekte: [zoneName] = zoneObject
-- Wird beim Resource-Stop zum Aufräumen verwendet
local activeZones = {}

-- ────────────────────────────────────────────────────────────
--  Interne Helfer
-- ────────────────────────────────────────────────────────────

-- Baut die onEnter/onExit Callbacks für eine Zone
local function MakeCallbacks(zoneName, zoneData)
    return {
        onEnter = function(self)
            TriggerEvent(MT.ZONE_ENTER, zoneName, zoneData)

            -- Kleine Marker-Nachricht nur bei interaktiven Zonen
            if zoneData.label and not zoneData.bonusZone then
                lib.showTextUI(("[E] %s"):format(zoneData.label), {
                    position = "left-center",
                    icon     = "fas fa-map-marker-alt",
                })
            end
        end,
        onExit = function(self)
            TriggerEvent(MT.ZONE_EXIT, zoneName)
            lib.hideTextUI()
        end,
    }
end

-- Registriert ox_target Einträge für eine Zone
-- Unterstützt Box-, Sphere- und PolyZonen
local function RegisterTargets(zoneName, zoneData, zoneObj)
    if not zoneData.targets or #zoneData.targets == 0 then return end

    -- Alle ox_target Aktionen dieser Zone zusammensammeln
    local options = {}
    for _, targetKey in ipairs(zoneData.targets) do
        local targetDef = Config.Targets[targetKey]
        if targetDef then
            for _, action in ipairs(targetDef) do
                -- Event-Handler: feuert lokales Event mit Zone-Kontext
                local actionCopy = {
                    name     = action.name .. "_" .. zoneName,
                    label    = action.label,
                    icon     = action.icon,
                    onSelect = function()
                        TriggerEvent(action.event, zoneName, zoneData)
                    end,
                }
                -- Level-Sperre wenn Zone ein minLevel definiert
                if zoneData.minLevel then
                    actionCopy.canInteract = function()
                        local level = exports["motortown"]:GetLevel()
                        return level >= zoneData.minLevel
                    end
                end
                table.insert(options, actionCopy)
            end
        end
    end

    if #options == 0 then return end

    -- ox_target Zone-Target (nutzt intern die Zonen-Grenzen)
    exports.ox_target:addLocalEntity(zoneObj, options)
end

-- ────────────────────────────────────────────────────────────
--  Zonen-Ersteller pro Typ
-- ────────────────────────────────────────────────────────────

local creators = {}

creators["box"] = function(zoneName, zoneData)
    local callbacks = MakeCallbacks(zoneName, zoneData)
    local zone = lib.zones.box({
        coords   = zoneData.coords,
        size     = zoneData.size,
        rotation = zoneData.rotation or 0,
        debug    = false,
        onEnter  = callbacks.onEnter,
        onExit   = callbacks.onExit,
    })
    return zone
end

creators["sphere"] = function(zoneName, zoneData)
    local callbacks = MakeCallbacks(zoneName, zoneData)
    local zone = lib.zones.sphere({
        coords  = zoneData.coords,
        radius  = zoneData.radius,
        debug   = false,
        onEnter = callbacks.onEnter,
        onExit  = callbacks.onExit,
    })
    return zone
end

creators["poly"] = function(zoneName, zoneData)
    local callbacks = MakeCallbacks(zoneName, zoneData)
    local zone = lib.zones.poly({
        points    = zoneData.points,
        thickness = zoneData.thickness or 4.0,
        debug     = false,
        onEnter   = callbacks.onEnter,
        onExit    = callbacks.onExit,
    })
    return zone
end

-- ────────────────────────────────────────────────────────────
--  ox_target für Box / Sphere Typen
--  (PolyZones bekommen kein addZone target – zu groß)
-- ────────────────────────────────────────────────────────────

local function AddZoneTarget(zoneName, zoneData)
    if not zoneData.targets or #zoneData.targets == 0 then return end
    if zoneData.type == "poly" then return end -- Poly: nur Enter/Exit

    local options = {}
    for _, targetKey in ipairs(zoneData.targets) do
        local targetDef = Config.Targets[targetKey]
        if targetDef then
            for _, action in ipairs(targetDef) do
                table.insert(options, {
                    name        = action.name .. "_" .. zoneName,
                    label       = action.label,
                    icon        = action.icon,
                    onSelect    = function()
                        TriggerEvent(action.event, zoneName, zoneData)
                    end,
                    canInteract = zoneData.minLevel and function()
                        return exports["motortown"]:GetLevel() >= zoneData.minLevel
                    end or nil,
                })
            end
        end
    end

    if #options == 0 then return end

    -- Für Box-Zonen: addBoxZone
    if zoneData.type == "box" then
        exports.ox_target:addBoxZone({
            coords   = zoneData.coords,
            size     = zoneData.size,
            rotation = zoneData.rotation or 0,
            debug    = false,
            options  = options,
        })
        -- Für Sphere-Zonen: addSphereZone
    elseif zoneData.type == "sphere" then
        exports.ox_target:addSphereZone({
            coords  = zoneData.coords,
            radius  = math.min(zoneData.radius, 5.0), -- target radius kleiner als zone
            debug   = false,
            options = options,
        })
    end
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

-- Gibt die Zone-Config für einen Namen zurück
function ZoneModule.GetZoneData(zoneName)
    return Config.Zones[zoneName]
end

-- Gibt alle Zonen eines bestimmten Typs zurück (z.B. alle bonusZones)
function ZoneModule.GetZonesByFlag(flag)
    local result = {}
    for name, data in pairs(Config.Zones) do
        if data[flag] then
            result[name] = data
        end
    end
    return result
end

-- Gibt alle Zonen zurück, die einen bestimmten jobType haben
function ZoneModule.GetZoneForJobType(jobType)
    for name, data in pairs(Config.Zones) do
        if data.jobType == jobType then
            return name, data
        end
    end
    return nil, nil
end

-- ────────────────────────────────────────────────────────────
--  Init: Alle Zonen aus Config erstellen
-- ────────────────────────────────────────────────────────────

function ZoneModule.Init()
    local count = 0

    for zoneName, zoneData in pairs(Config.Zones) do
        local creator = creators[zoneData.type]
        if creator then
            local ok, zoneOrErr = pcall(creator, zoneName, zoneData)
            if ok and zoneOrErr then
                activeZones[zoneName] = zoneOrErr
                AddZoneTarget(zoneName, zoneData)
                count = count + 1
            else
                -- Fehler beim Erstellen einer Zone sollen andere nicht blockieren
                print(("[MT] WARNUNG: Zone '%s' konnte nicht erstellt werden: %s")
                    :format(zoneName, tostring(zoneOrErr)))
            end
        else
            print(("[MT] WARNUNG: Unbekannter Zonentyp '%s' für Zone '%s'")
                :format(tostring(zoneData.type), zoneName))
        end
    end

    -- Aufräumen wenn Resource gestoppt wird
    AddEventHandler("onResourceStop", function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end
        for _, zone in pairs(activeZones) do
            zone:remove()
        end
        activeZones = {}
    end)

    exports("GetZoneData", ZoneModule.GetZoneData)
    exports("GetZonesByFlag", ZoneModule.GetZonesByFlag)
    exports("GetZoneForJobType", ZoneModule.GetZoneForJobType)

    print(("[MT] ZoneModule initialisiert – %d Zonen erstellt"):format(count))
end

_ZoneModule = ZoneModule
