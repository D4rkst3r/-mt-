-- ============================================================
--  server/admin.lua
--  Admin-System: Rank-Prüfung, Config-CRUD, Live-Broadcast
--
--  Admin hinzufügen (Serverkonsole):
--    mt_addadmin license:xxxx admin
--    mt_addadmin license:xxxx superadmin
-- ============================================================

local AdminModule = {}

-- Cache: [identifier] = rank ('admin'|'superadmin'|nil)
local adminCache = {}

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

local function GetIdentifier(source)
    for _, v in ipairs(GetPlayerIdentifiers(source)) do
        if v:sub(1, 8) == "license:" then return v end
    end
    return nil
end

local function IsAdmin(source)
    local id = GetIdentifier(source)
    if not id then return false end
    return adminCache[id] ~= nil
end

local function IsSuperAdmin(source)
    local id = GetIdentifier(source)
    if not id then return false end
    return adminCache[id] == "superadmin"
end

-- Wandelt JSON-String sicher in Lua-Table
local function DecodeJSON(str)
    local ok, result = pcall(json.decode, str)
    return ok and result or nil
end

-- ────────────────────────────────────────────────────────────
--  DB-Operationen
-- ────────────────────────────────────────────────────────────

-- Speichert / überschreibt einen Config-Eintrag in der DB
local function SaveConfig(category, key, data, byIdentifier)
    local encoded = json.encode(data)
    MySQL.rawExecute(
        [[INSERT INTO mt_config (category, `key`, data, deleted, updated_by)
          VALUES (?,?,?,0,?)
          ON DUPLICATE KEY UPDATE data=VALUES(data), deleted=0, updated_by=VALUES(updated_by)]],
        { category, key, encoded, byIdentifier or "system" }
    )
end

-- Markiert einen Config-Eintrag als gelöscht
local function DeleteConfig(category, key, byIdentifier)
    MySQL.rawExecute(
        "UPDATE mt_config SET deleted=1, updated_by=? WHERE category=? AND `key`=?",
        { byIdentifier or "system", category, key }
    )
end

-- ────────────────────────────────────────────────────────────
--  Config-Loader (beim Start: DB-Overrides über Lua-Config)
-- ────────────────────────────────────────────────────────────

local function LoadConfigOverrides(cb)
    MySQL.rawExecute.await("SELECT * FROM mt_config WHERE deleted = 0", {})

    MySQL.query("SELECT * FROM mt_config", {}, function(rows)
        if not rows then
            cb()
            return
        end

        local zoneChanges    = 0
        local jobChanges     = 0
        local vehicleChanges = 0
        local factoryChanges = 0

        for _, row in ipairs(rows) do
            local data = DecodeJSON(row.data)
            if data then
                if row.deleted == 1 then
                    -- Gelöschte Einträge aus Config entfernen
                    if row.category == "zone" then
                        Config.Zones[row.key] = nil; zoneChanges = zoneChanges + 1
                    end
                    if row.category == "job" then
                        Config.Jobs[row.key] = nil; jobChanges = jobChanges + 1
                    end
                    if row.category == "vehicle" then
                        Config.Vehicles[row.key] = nil; vehicleChanges = vehicleChanges + 1
                    end
                    if row.category == "factory" then
                        Config.Factories[row.key] = nil; factoryChanges = factoryChanges + 1
                    end
                else
                    -- Override oder neuer Eintrag
                    if row.category == "zone" then
                        Config.Zones[row.key] = data; zoneChanges = zoneChanges + 1
                    end
                    if row.category == "job" then
                        Config.Jobs[row.key] = data; jobChanges = jobChanges + 1
                    end
                    if row.category == "vehicle" then
                        Config.Vehicles[row.key] = data; vehicleChanges = vehicleChanges + 1
                    end
                    if row.category == "factory" then
                        Config.Factories[row.key] = data; factoryChanges = factoryChanges + 1
                    end
                end
            end
        end

        print(("[MT][Admin] Config geladen: %d Zonen, %d Jobs, %d Fahrzeuge, %d Fabriken überschrieben")
            :format(zoneChanges, jobChanges, vehicleChanges, factoryChanges))
        cb()
    end)
end

-- ────────────────────────────────────────────────────────────
--  Zonen Live-Reload (für alle Clients)
-- ────────────────────────────────────────────────────────────

local function BroadcastZoneUpdate(zoneKey, zoneData, deleted)
    TriggerClientEvent("mt:admin:zoneUpdate", -1, {
        key     = zoneKey,
        data    = zoneData,
        deleted = deleted or false,
    })
end

local function BroadcastConfigReload(category)
    -- Für Jobs/Vehicles/Factories reicht ein Signal – kein Live-Reload nötig
    -- (nur Dispatcher-Menü muss neu laden, passiert beim nächsten Öffnen)
    TriggerClientEvent("mt:admin:configReloaded", -1, { category = category })
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Admin → Server
-- ────────────────────────────────────────────────────────────

-- Spieler fragt seinen Rank an
local function OnAdminWhoAmI()
    local source = source
    local id     = GetIdentifier(source)
    TriggerClientEvent("mt:admin:rank", source, {
        rank = adminCache[id] or false
    })
end

-- Zone speichern / überschreiben
local function OnAdminSaveZone(data)
    local source = source
    if not IsAdmin(source) then return end

    local id = GetIdentifier(source)
    if not data or not data.key or not data.zoneData then return end

    -- Koordinaten aus JSON korrekt in vec3 umwandeln
    local zd = data.zoneData
    if zd.coords then
        zd.coords = vec3(zd.coords.x, zd.coords.y, zd.coords.z)
    end
    if zd.size then
        zd.size = vec3(zd.size.x, zd.size.y, zd.size.z)
    end

    Config.Zones[data.key] = zd
    SaveConfig("zone", data.key, data.zoneData, id)
    BroadcastZoneUpdate(data.key, data.zoneData, false)

    print(("[MT][Admin] Zone '%s' gespeichert von %s"):format(data.key, id))
end

-- Zone löschen
local function OnAdminDeleteZone(data)
    local source = source
    if not IsSuperAdmin(source) then
        TriggerClientEvent("mt:admin:error", source, "Nur SuperAdmins dürfen Zonen löschen.")
        return
    end

    local id = GetIdentifier(source)
    if not data or not data.key then return end

    Config.Zones[data.key] = nil
    DeleteConfig("zone", data.key, id)
    BroadcastZoneUpdate(data.key, nil, true)

    print(("[MT][Admin] Zone '%s' gelöscht von %s"):format(data.key, id))
end

-- Job speichern
local function OnAdminSaveJob(data)
    local source = source
    if not IsAdmin(source) then return end

    local id = GetIdentifier(source)
    if not data or not data.key or not data.jobData then return end

    Config.Jobs[data.key] = data.jobData
    SaveConfig("job", data.key, data.jobData, id)
    BroadcastConfigReload("job")

    print(("[MT][Admin] Job '%s' gespeichert von %s"):format(data.key, id))
end

-- Fahrzeug-Config speichern
local function OnAdminSaveVehicle(data)
    local source = source
    if not IsAdmin(source) then return end

    local id = GetIdentifier(source)
    if not data or not data.key or not data.vehicleData then return end

    if Config.Vehicles then
        Config.Vehicles[data.key] = data.vehicleData
    end
    SaveConfig("vehicle", data.key, data.vehicleData, id)
    BroadcastConfigReload("vehicle")

    print(("[MT][Admin] Fahrzeug '%s' gespeichert von %s"):format(data.key, id))
end

-- Fabrik speichern
local function OnAdminSaveFactory(data)
    local source = source
    if not IsAdmin(source) then return end

    local id = GetIdentifier(source)
    if not data or not data.key or not data.factoryData then return end

    if Config.Factories then
        Config.Factories[data.key] = data.factoryData
    end
    SaveConfig("factory", data.key, data.factoryData, id)
    BroadcastConfigReload("factory")

    print(("[MT][Admin] Fabrik '%s' gespeichert von %s"):format(data.key, id))
end

-- Client fordert komplette Config-Listen an (für Menü)
local function OnAdminFetchConfig(data)
    local source = source
    if not IsAdmin(source) then return end

    local category = data and data.category
    local result   = {}

    if category == "zone" then
        for k, v in pairs(Config.Zones) do
            result[k] = v
        end
    elseif category == "job" then
        for k, v in pairs(Config.Jobs) do
            result[k] = {
                label         = v.label,
                minLevel      = v.minLevel,
                baseWage      = v.baseWage,
                wagePerKm     = v.wagePerKm,
                wagePerTon    = v.wagePerTon,
                vehicleType   = v.vehicleType,
                timeLimitMin  = v.timeLimitMin,
                pickupZones   = v.pickupZones,
                deliveryZones = v.deliveryZones,
            }
        end
    elseif category == "vehicle" then
        if Config.Vehicles then
            for k, v in pairs(Config.Vehicles) do
                result[k] = { label = v.label, price = v.price, model = v.model }
            end
        end
    elseif category == "factory" then
        if Config.Factories then
            for k, v in pairs(Config.Factories) do
                result[k] = {
                    label       = v.label,
                    cycleMin    = v.cycleMin,
                    inputNeeded = v.inputNeeded,
                    outputPer   = v.outputPer,
                }
            end
        end
    end

    TriggerClientEvent("mt:admin:configData", source, { category = category, data = result })
end

-- ────────────────────────────────────────────────────────────
--  Konsolen-Befehle
-- ────────────────────────────────────────────────────────────

RegisterCommand("mt_addadmin", function(src, args)
    local identifier = args[1]
    local rank       = args[2] or "admin"
    if not identifier then
        print("[MT] Verwendung: mt_addadmin <license:xxx> <admin|superadmin>")
        return
    end
    if rank ~= "admin" and rank ~= "superadmin" then
        rank = "admin"
    end
    MySQL.rawExecute(
        [[INSERT INTO mt_admins (identifier, `rank`) VALUES (?,?)
          ON DUPLICATE KEY UPDATE `rank`=VALUES(`rank`)]],
        { identifier, rank },
        function()
            adminCache[identifier] = rank
            print(("[MT] Admin hinzugefügt: %s (%s)"):format(identifier, rank))
        end
    )
end, true)

RegisterCommand("mt_removeadmin", function(src, args)
    local identifier = args[1]
    if not identifier then
        print("[MT] Verwendung: mt_removeadmin <license:xxx>")
        return
    end
    MySQL.rawExecute("DELETE FROM mt_admins WHERE identifier=?", { identifier }, function()
        adminCache[identifier] = nil
        print(("[MT] Admin entfernt: %s"):format(identifier))
    end)
end, true)

RegisterCommand("mt_listadmins", function(src, args)
    print("[MT] Aktuelle Admins:")
    for id, rank in pairs(adminCache) do
        print(("  %s → %s"):format(id, rank))
    end
end, true)

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function AdminModule.IsAdmin(source) return IsAdmin(source) end

function AdminModule.IsSuperAdmin(source) return IsSuperAdmin(source) end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function AdminModule.Init(cb)
    -- 1. Admin-Cache aus DB laden
    MySQL.query("SELECT identifier, `rank` FROM mt_admins", {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                adminCache[row.identifier] = row.rank
            end
            print(("[MT][Admin] %d Admin(s) geladen"):format(#rows))
        end

        -- 2. Config-Overrides aus DB laden, dann Callback
        LoadConfigOverrides(function()
            cb()
        end)
    end)

    -- Net Events
    RegisterNetEvent("mt:admin:whoami", OnAdminWhoAmI)
    RegisterNetEvent("mt:admin:saveZone", OnAdminSaveZone)
    RegisterNetEvent("mt:admin:deleteZone", OnAdminDeleteZone)
    RegisterNetEvent("mt:admin:saveJob", OnAdminSaveJob)
    RegisterNetEvent("mt:admin:saveVehicle", OnAdminSaveVehicle)
    RegisterNetEvent("mt:admin:saveFactory", OnAdminSaveFactory)
    RegisterNetEvent("mt:admin:fetchConfig", OnAdminFetchConfig)

    print("[MT] AdminModule (Server) initialisiert")
end

_AdminModule = AdminModule
