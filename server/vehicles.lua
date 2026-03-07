-- ============================================================
--  server/vehicles.lua
--  Zuständig für: Fahrzeug kaufen/verkaufen, Ownership-DB,
--  Upgrades speichern/laden, Garage-Verwaltung.
--
--  Sicherheit: Alle Käufe und Upgrades server-seitig validiert.
--  Kein Client kann Fahrzeuge oder Upgrades gratis bekommen.
-- ============================================================

local VehicleModule = {}

-- ────────────────────────────────────────────────────────────
--  Interne Helfer
-- ────────────────────────────────────────────────────────────

-- Generiert ein Kennzeichen das noch nicht in der DB ist
local function GenerateUniquePlate(cb, _retries)
    local retries = _retries or 0
    if retries >= 10 then
        -- Sollte in der Praxis nie eintreten, aber Safety-Guard
        print("[MT] FEHLER: GenerateUniquePlate – max. Versuche erreicht")
        cb(nil)
        return
    end
    local plate = Utils.GeneratePlate()
    MySQL.scalar(
        "SELECT id FROM mt_vehicles WHERE plate = ?",
        { plate },
        function(existing)
            if existing then
                GenerateUniquePlate(cb, retries + 1)
            else
                cb(plate)
            end
        end
    )
end

-- Lädt alle Fahrzeuge eines Spielers aus der DB
local function FetchPlayerVehicles(identifier, cb)
    MySQL.query(
        "SELECT * FROM mt_vehicles WHERE identifier = ? ORDER BY id ASC",
        { identifier },
        function(rows)
            cb(rows or {})
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Fahrzeug kaufen
-- ────────────────────────────────────────────────────────────

local function OnVehicleBuy(source, data)
    local source = source
    if not data or not data.model then return end

    local vehicleCfg = Config.Vehicles[data.model]
    if not vehicleCfg then return end

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    -- Level prüfen
    if playerData.trucking_level < (vehicleCfg.minLevel or 1) then
        TriggerClientEvent("mt:vehicle:buyResult", source, {
            success = false,
            error   = ("Benötigt Level %d."):format(vehicleCfg.minLevel),
        })
        return
    end

    -- Fahrzeuganzahl prüfen
    MySQL.scalar(
        "SELECT COUNT(*) FROM mt_vehicles WHERE identifier = ?",
        { playerData.identifier },
        function(count)
            if (count or 0) >= Config.MaxVehiclesPerPlayer then
                TriggerClientEvent("mt:vehicle:buyResult", source, {
                    success = false,
                    error   = ("Maximale Fahrzeuganzahl (%d) erreicht."):format(
                        Config.MaxVehiclesPerPlayer),
                })
                return
            end

            -- Geld abziehen
            local removed = _PlayerModule.RemoveMoney(
                source, vehicleCfg.price,
                ("Fahrzeug gekauft: %s"):format(vehicleCfg.label)
            )
            if not removed then
                TriggerClientEvent("mt:vehicle:buyResult", source, {
                    success = false,
                    error   = "Nicht genug Geld.",
                })
                return
            end

            -- Kennzeichen generieren & in DB speichern
            GenerateUniquePlate(function(plate)
                if not plate then
                    _PlayerModule.AddMoney(source, vehicleCfg.price, "Fahrzeugkauf fehlgeschlagen")
                    TriggerClientEvent("mt:vehicle:buyResult", source, {
                        success = false, error = "Kennzeichen-Generierung fehlgeschlagen."
                    })
                    return
                end
                MySQL.insert(
                    [[INSERT INTO mt_vehicles
                      (identifier, plate, model, upgrades, fuel, mileage, stored)
                      VALUES (?, ?, ?, ?, 100, 0, 1)]],
                    { playerData.identifier, plate, vehicleCfg.model,
                        json.encode({}) },
                    function(insertId)
                        TriggerClientEvent("mt:vehicle:buyResult", source, {
                            success   = true,
                            vehicleId = insertId,
                            plate     = plate,
                            model     = vehicleCfg.model,
                            label     = vehicleCfg.label,
                        })
                        print(("[MT] %s kaufte %s (Plate: %s, %d$)"):format(
                            playerData.identifier, vehicleCfg.model,
                            plate, vehicleCfg.price
                        ))
                    end
                )
            end)
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Garage (Fahrzeugliste anfordern)
-- ────────────────────────────────────────────────────────────

local function OnGarageRequest(source)
    local source = source
    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    FetchPlayerVehicles(playerData.identifier, function(vehicles)
        -- Upgrade-JSON dekodieren für Client
        local result = {}
        for _, v in ipairs(vehicles) do
            table.insert(result, {
                id       = v.id,
                plate    = v.plate,
                model    = v.model,
                upgrades = json.decode(v.upgrades or "{}") or {},
                fuel     = v.fuel,
                mileage  = v.mileage,
                stored   = v.stored == 1,
            })
        end
        TriggerClientEvent("mt:vehicle:garageList", source, result)
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Fahrzeug einlagern
-- ────────────────────────────────────────────────────────────

local function OnVehicleStore(source, data)
    local source = source
    if not data or not data.plate then return end

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    -- Sicherheit: Fahrzeug muss dem Spieler gehören
    MySQL.scalar(
        "SELECT id FROM mt_vehicles WHERE plate = ? AND identifier = ?",
        { data.plate, playerData.identifier },
        function(vehicleId)
            if not vehicleId then
                TriggerClientEvent("mt:vehicle:storeResult", source, {
                    success = false, error = "Fahrzeug gehört dir nicht."
                })
                return
            end

            MySQL.update(
                "UPDATE mt_vehicles SET stored = 1, fuel = ?, mileage = ? WHERE id = ?",
                { data.fuel or 100, data.mileage or 0, vehicleId },
                function()
                    TriggerClientEvent("mt:vehicle:storeResult", source, {
                        success = true, plate = data.plate
                    })
                end
            )
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Fahrzeug holen (aus Garage spawnen)
-- ────────────────────────────────────────────────────────────

local function OnVehicleRetrieve(source, data)
    local source = source
    if not data or not data.vehicleId then return end

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    MySQL.single(
        "SELECT * FROM mt_vehicles WHERE id = ? AND identifier = ?",
        { data.vehicleId, playerData.identifier },
        function(vehicle)
            if not vehicle then
                TriggerClientEvent("mt:vehicle:spawnData", source, {
                    success = false, error = "Fahrzeug nicht gefunden."
                })
                return
            end

            if vehicle.stored == 0 then
                TriggerClientEvent("mt:vehicle:spawnData", source, {
                    success = false,
                    error   = "Fahrzeug ist bereits gespawnt.",
                })
                return
            end

            -- Als "draußen" markieren
            MySQL.update(
                "UPDATE mt_vehicles SET stored = 0 WHERE id = ?",
                { vehicle.id }
            )

            TriggerClientEvent("mt:vehicle:spawnData", source, {
                success   = true,
                id        = vehicle.id,
                plate     = vehicle.plate,
                model     = vehicle.model,
                upgrades  = json.decode(vehicle.upgrades or "{}") or {},
                fuel      = vehicle.fuel,
                spawnZone = data.spawnZone,
            })
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Upgrade kaufen
-- ────────────────────────────────────────────────────────────

local function OnUpgradeBuy(source, data)
    local source = source
    -- data = { vehicleId, upgradeKey, level }
    if not data or not data.vehicleId or not data.upgradeKey or not data.level then
        return
    end

    local upgradeCfg = Config.Upgrades[data.upgradeKey]
    if not upgradeCfg then return end

    local levelCfg = upgradeCfg.levels[data.level]
    if not levelCfg then return end

    local playerData = _PlayerModule.GetData(source)
    if not playerData then return end

    -- Fahrzeug gehört dem Spieler?
    MySQL.single(
        "SELECT * FROM mt_vehicles WHERE id = ? AND identifier = ?",
        { data.vehicleId, playerData.identifier },
        function(vehicle)
            if not vehicle then
                TriggerClientEvent("mt:vehicle:upgradeResult", source, {
                    success = false, error = "Fahrzeug nicht gefunden."
                })
                return
            end

            local upgrades = json.decode(vehicle.upgrades or "{}") or {}

            -- Bereits diese oder höhere Stufe?
            local currentLevel = upgrades[data.upgradeKey] or 0
            if currentLevel >= data.level then
                TriggerClientEvent("mt:vehicle:upgradeResult", source, {
                    success = false,
                    error   = "Upgrade bereits installiert oder höhere Stufe vorhanden.",
                })
                return
            end

            -- Preis: nur Differenz zur vorherigen Stufe zahlen
            local prevPrice = 0
            if currentLevel > 0 then
                prevPrice = upgradeCfg.levels[currentLevel].price
            end
            local cost = levelCfg.price - prevPrice

            local removed = _PlayerModule.RemoveMoney(
                source, cost,
                ("%s Upgrade Stufe %d: %s"):format(
                    upgradeCfg.label, data.level, vehicle.plate)
            )
            if not removed then
                TriggerClientEvent("mt:vehicle:upgradeResult", source, {
                    success = false, error = "Nicht genug Geld."
                })
                return
            end

            -- Upgrade speichern
            upgrades[data.upgradeKey] = data.level
            MySQL.update(
                "UPDATE mt_vehicles SET upgrades = ? WHERE id = ?",
                { json.encode(upgrades), vehicle.id },
                function()
                    TriggerClientEvent("mt:vehicle:upgradeResult", source, {
                        success    = true,
                        upgradeKey = data.upgradeKey,
                        level      = data.level,
                        fields     = levelCfg.fields,
                    })
                end
            )
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Reparatur bezahlen
-- ────────────────────────────────────────────────────────────

local function OnRepairPay(source, data)
    local source = source
    -- data = { damage }  0.0–1.0 Schadenwert vom Client
    if not data then return end

    local damage  = Utils.Clamp(data.damage or 0, 0.0, 1.0)
    local cost    = math.max(
        Config.RepairMinCost,
        math.floor(damage * 1000 * Config.RepairCostPerDamage)
    )

    local removed = _PlayerModule.RemoveMoney(source, cost, "Fahrzeugreparatur")
    if not removed then
        TriggerClientEvent("mt:vehicle:repairResult", source, {
            success = false, error = "Nicht genug Geld. Kosten: " .. Utils.FormatMoney(cost)
        })
        return
    end

    TriggerClientEvent("mt:vehicle:repairResult", source, {
        success = true, cost = cost
    })
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function VehicleModule.GetPlayerVehicles(identifier, cb)
    FetchPlayerVehicles(identifier, cb)
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function VehicleModule.Init()
    RegisterNetEvent("mt:vehicle:buy", OnVehicleBuy)
    RegisterNetEvent("mt:vehicle:garageOpen", OnGarageRequest)
    RegisterNetEvent(MT.VEHICLE_STORE, OnVehicleStore)
    RegisterNetEvent("mt:vehicle:retrieve", OnVehicleRetrieve)
    RegisterNetEvent(MT.VEHICLE_UPGRADE_BUY, OnUpgradeBuy)
    RegisterNetEvent("mt:vehicle:repairPay", OnRepairPay)

    exports("GetPlayerVehicles", VehicleModule.GetPlayerVehicles)

    print("[MT] VehicleModule (Server) initialisiert")
end

_VehicleModule = VehicleModule
