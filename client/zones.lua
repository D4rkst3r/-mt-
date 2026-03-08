-- ============================================================
--  client/zones.lua
--  Erstellt alle Zonen aus Config.Zones via ox_lib.
--
--  Interaktion: E-Taste via eigenem Key-Thread (kein ox_target
--  für Flächen-Zonen – addLocalEntity erwartet ein Entity, nicht
--  ein Zone-Objekt).
--
--  Andere Module hören auf:
--    AddEventHandler(MT.ZONE_ENTER, function(zoneName, zoneData) end)
--    AddEventHandler(MT.ZONE_EXIT,  function(zoneName) end)
-- ============================================================

local ZoneModule  = {}

local activeZones = {}   -- [zoneName] = zoneObject (zum Aufräumen)

-- Aktuell betretene Zone (für E-Key-Thread)
local inZone      = false
local inZoneName  = nil
local inZoneData  = nil

-- ────────────────────────────────────────────────────────────
--  E-Key Thread
--  Läuft immer, ist aber fast kostenlos wenn keine Zone aktiv.
-- ────────────────────────────────────────────────────────────

-- Sammelt alle verfügbaren Aktionen einer Zone
local function CollectZoneActions(zoneData)
    local actions = {}
    if not zoneData.targets then return actions end
    for _, targetKey in ipairs(zoneData.targets) do
        local targetDef = Config.Targets[targetKey]
        if targetDef then
            for _, action in ipairs(targetDef) do
                table.insert(actions, action)
            end
        end
    end
    return actions
end

CreateThread(function()
    while true do
        if inZone and inZoneData and inZoneData.targets then
            -- E = Control 38
            if IsControlJustPressed(0, 38) then
                local actions = CollectZoneActions(inZoneData)

                if #actions == 1 then
                    -- Nur eine Aktion → direkt feuern
                    TriggerEvent(actions[1].event, inZoneName, inZoneData)
                elseif #actions > 1 then
                    -- Mehrere Aktionen → Menü anzeigen
                    local options = {}
                    for _, action in ipairs(actions) do
                        local ev    = action.event
                        local zName = inZoneName
                        local zData = inZoneData
                        table.insert(options, {
                            title    = action.label or ev,
                            icon     = action.icon or "fas fa-hand-pointer",
                            onSelect = function()
                                TriggerEvent(ev, zName, zData)
                            end,
                        })
                    end
                    lib.registerContext({
                        id      = "mt_zone_actions",
                        title   = inZoneData.label or "Aktion wählen",
                        options = options,
                    })
                    lib.showContext("mt_zone_actions")
                end
            end
            Wait(0)   -- aktiv wenn in Zone
        else
            Wait(300) -- idle wenn nicht in Zone
        end
    end
end)

-- ────────────────────────────────────────────────────────────
--  Zone-Callbacks
-- ────────────────────────────────────────────────────────────

local function MakeCallbacks(zoneName, zoneData)
    return {
        onEnter = function(self)
            inZone     = true
            inZoneName = zoneName
            inZoneData = zoneData

            TriggerEvent(MT.ZONE_ENTER, zoneName, zoneData)

            -- TextUI nur bei interaktiven Zonen (mit Targets)
            if zoneData.targets and #zoneData.targets > 0 and not zoneData.bonusZone then
                local allActions = {}
                for _, tk in ipairs(zoneData.targets) do
                    local td = Config.Targets[tk]
                    if td then for _, a in ipairs(td) do table.insert(allActions, a) end end
                end
                local label
                if #allActions == 1 then
                    label = allActions[1].label or zoneData.label or "Interagieren"
                else
                    label = zoneData.label or "Interagieren"
                end
                lib.showTextUI(("[E] %s"):format(label), {
                    position = "left-center",
                    icon     = "fas fa-hand-pointer",
                })
            end
        end,
        onExit = function(self)
            inZone     = false
            inZoneName = nil
            inZoneData = nil

            TriggerEvent(MT.ZONE_EXIT, zoneName)
            lib.hideTextUI()
        end,
    }
end

-- ────────────────────────────────────────────────────────────
--  Zonen-Ersteller pro Typ
-- ────────────────────────────────────────────────────────────

local creators = {}

creators["box"] = function(zoneName, zoneData)
    local cb = MakeCallbacks(zoneName, zoneData)
    return lib.zones.box({
        coords   = zoneData.coords,
        size     = zoneData.size,
        rotation = zoneData.rotation or 0,
        debug    = false,
        onEnter  = cb.onEnter,
        onExit   = cb.onExit,
    })
end

creators["sphere"] = function(zoneName, zoneData)
    local cb = MakeCallbacks(zoneName, zoneData)
    return lib.zones.sphere({
        coords  = zoneData.coords,
        radius  = zoneData.radius or 3.0,
        debug   = false,
        onEnter = cb.onEnter,
        onExit  = cb.onExit,
    })
end

creators["poly"] = function(zoneName, zoneData)
    local cb = MakeCallbacks(zoneName, zoneData)
    return lib.zones.poly({
        points    = zoneData.points,
        thickness = zoneData.thickness or 4.0,
        debug     = false,
        onEnter   = cb.onEnter,
        onExit    = cb.onExit,
    })
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function ZoneModule.GetZoneData(zoneName)
    return Config.Zones[zoneName]
end

function ZoneModule.GetZonesByFlag(flag)
    local result = {}
    for name, data in pairs(Config.Zones) do
        if data[flag] then result[name] = data end
    end
    return result
end

function ZoneModule.GetZoneForJobType(jobType)
    for name, data in pairs(Config.Zones) do
        if data.jobType == jobType then return name, data end
    end
    return nil, nil
end

function ZoneModule.GetCurrentZone()
    return inZoneName, inZoneData
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function ZoneModule.Init()
    local count = 0

    for zoneName, zoneData in pairs(Config.Zones) do
        local creator = creators[zoneData.type]
        if creator then
            local ok, zoneOrErr = pcall(creator, zoneName, zoneData)
            if ok and zoneOrErr then
                activeZones[zoneName] = zoneOrErr
                count = count + 1
            else
                print(("[MT] WARNUNG: Zone '%s' konnte nicht erstellt werden: %s")
                    :format(zoneName, tostring(zoneOrErr)))
            end
        else
            print(("[MT] WARNUNG: Unbekannter Zonentyp '%s' für Zone '%s'")
                :format(tostring(zoneData.type), zoneName))
        end
    end

    -- ── Live Zone-Update vom Admin-System ──────────────────
    RegisterNetEvent("mt:admin:zoneUpdate", function(payload)
        if not payload or not payload.key then return end
        local key = payload.key

        -- Alte Zone entfernen falls vorhanden
        if activeZones[key] then
            activeZones[key]:remove()
            activeZones[key] = nil
        end

        -- Falls gerade in dieser Zone → raus
        if inZoneName == key then
            inZone     = false
            inZoneName = nil
            inZoneData = nil
            lib.hideTextUI()
        end

        if payload.deleted then
            -- Zone wurde gelöscht → Config ebenfalls entfernen
            if Config.Zones then Config.Zones[key] = nil end
            print(("[MT][Admin] Zone '%s' live entfernt"):format(key))
            return
        end

        -- Neue/geänderte Zone erstellen
        local zd = payload.data
        if not zd then return end

        -- JSON-Koordinaten zurück in vec3
        if zd.coords and type(zd.coords) == "table" then
            zd.coords = vec3(zd.coords.x, zd.coords.y, zd.coords.z)
        end
        if zd.size and type(zd.size) == "table" then
            zd.size = vec3(zd.size.x, zd.size.y, zd.size.z)
        end

        -- In lokale Config schreiben
        if Config.Zones then Config.Zones[key] = zd end

        local creator = creators[zd.type]
        if creator then
            local ok, zoneOrErr = pcall(creator, key, zd)
            if ok and zoneOrErr then
                activeZones[key] = zoneOrErr
                print(("[MT][Admin] Zone '%s' live aktualisiert"):format(key))
            else
                print(("[MT][Admin] Zone '%s' Live-Update fehlgeschlagen: %s"):format(key, tostring(zoneOrErr)))
            end
        end
    end)

    AddEventHandler("onResourceStop", function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end
        for _, zone in pairs(activeZones) do zone:remove() end
        activeZones = {}
        lib.hideTextUI()
    end)

    exports("GetZoneData", ZoneModule.GetZoneData)
    exports("GetZonesByFlag", ZoneModule.GetZonesByFlag)
    exports("GetZoneForJobType", ZoneModule.GetZoneForJobType)
    exports("GetCurrentZone", ZoneModule.GetCurrentZone)

    print(("[MT] ZoneModule initialisiert – %d Zonen erstellt"):format(count))
end

_ZoneModule = ZoneModule
