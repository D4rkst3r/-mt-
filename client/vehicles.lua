-- ============================================================
--  client/vehicles.lua
--  Zuständig für: Fahrzeug spawnen, HandlingFields anwenden,
--  Dealer-UI, Garage-UI, Upgrade-UI, Schadensystem.
-- ============================================================

local VehicleModule     = {}

-- Aktuell gespawntes Fahrzeug des Spielers
local spawnedVehicle    = nil -- { entity, plate, id, upgrades }
local pendingStorePlate = nil -- Plate des Fahrzeugs das gerade eingelagert wird

-- Schadensüberwachung
local lastHealth        = 1000.0
local damageThread      = nil

-- ────────────────────────────────────────────────────────────
--  HandlingFields anwenden
-- ────────────────────────────────────────────────────────────

-- Wendet alle Upgrade-HandlingFields auf ein Fahrzeug an.
-- Stapelt Upgrades in der Reihenfolge motor → getriebe → ...
local function ApplyUpgrades(vehicle, upgrades)
    if not vehicle or not upgrades then return end

    -- Alle Felder die durch irgendein Upgrade verändert werden könnten zurücksetzen,
    -- bevor neue Werte gesetzt werden. Verhindert Upgrade-Stacking beim Wechsel.
    for _, upgradeCfg in pairs(Config.Upgrades) do
        for _, levelCfg in ipairs(upgradeCfg.levels) do
            for field, _ in pairs(levelCfg.fields) do
                ResetVehicleHandlingField(vehicle, "CHandlingData", field)
            end
        end
    end

    for upgradeKey, level in pairs(upgrades) do
        local upgradeCfg = Config.Upgrades[upgradeKey]
        if upgradeCfg and upgradeCfg.levels[level] then
            local fields = upgradeCfg.levels[level].fields
            for field, value in pairs(fields) do
                SetVehicleHandlingFloat(vehicle, "CHandlingData", field, value)
            end
        end
    end
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug spawnen
-- ────────────────────────────────────────────────────────────

local function SpawnVehicle(data, spawnCoords, heading)
    CreateThread(function()
        local model = GetHashKey(data.model)

        if not IsModelValid(model) then
            lib.notify({ title = "Fehler", description = "Ungültiges Fahrzeugmodel.", type = "error" })
            return
        end

        -- Model laden und warten bis es bereit ist
        lib.requestModel(model, 10000)
        while not HasModelLoaded(model) do Wait(50) end

        local vehicle = CreateVehicle(
            model, spawnCoords.x, spawnCoords.y, spawnCoords.z,
            heading or 0.0, true, false
        )

        -- Warten bis Fahrzeug existiert
        while not DoesEntityExist(vehicle) do Wait(50) end

        -- Mission Entity damit GTA es nicht despawnt
        SetEntityAsMissionEntity(vehicle, true, true)

        -- Kennzeichen setzen
        SetVehicleNumberPlateText(vehicle, data.plate)

        -- Upgrades anwenden
        if data.upgrades and next(data.upgrades) then
            ApplyUpgrades(vehicle, data.upgrades)
        end

        -- Motor an
        SetVehicleEngineOn(vehicle, true, true, false)

        -- Spieler einsteigen
        local ped = PlayerPedId()
        SetPedIntoVehicle(ped, vehicle, -1)

        -- Warten bis Spieler wirklich drin sitzt
        local timeout = 0
        while GetVehiclePedIsIn(ped, false) ~= vehicle and timeout < 50 do
            Wait(100)
            timeout = timeout + 1
        end

        -- Tankstand setzen nachdem Spieler sitzt
        local fuelLevel = data.fuel or 100.0
        SetVehicleFuelLevel(vehicle, fuelLevel)

        SetModelAsNoLongerNeeded(model)

        spawnedVehicle = {
            entity   = vehicle,
            plate    = data.plate,
            id       = data.id,
            upgrades = data.upgrades or {},
        }

        -- Kilometerzähler auf DB-Stand setzen
        if _HudModule then
            _HudModule.SetOdometerBase(data.mileage or 0)
        end

        -- Schadensüberwachung starten
        VehicleModule.StartDamageThread()

        lib.notify({
            title       = "Fahrzeug geholt",
            description = ("%s – Kennzeichen: %s"):format(data.model, data.plate),
            type        = "success",
        })
    end)
end

-- ────────────────────────────────────────────────────────────
--  Schadensüberwachung (läuft im Hintergrund)
-- ────────────────────────────────────────────────────────────

function VehicleModule.StartDamageThread()
    if damageThread then return end

    damageThread = CreateThread(function()
        while spawnedVehicle and DoesEntityExist(spawnedVehicle.entity) do
            Wait(2000)

            local vehicle = spawnedVehicle.entity
            local health  = GetVehicleBodyHealth(vehicle)

            -- Spürbarer Schaden → ans HUD-Modul melden
            if math.abs(health - lastHealth) > 5 then
                lastHealth = health
                TriggerEvent(MT.VEHICLE_DAMAGE_SYNC, {
                    plate  = spawnedVehicle.plate,
                    health = health,
                    damage = Utils.Round(1.0 - (health / 1000.0), 3),
                })
            end

            -- Fahrzeug wurde zerstört
            if health <= 0 then
                lib.notify({
                    title       = "⚠️ Fahrzeug beschädigt",
                    description = "Fahre zur Werkstatt um es reparieren zu lassen.",
                    type        = "warning",
                    duration    = 8000,
                })
                break
            end
        end
        damageThread = nil
    end)
end

-- ────────────────────────────────────────────────────────────
--  Dealer Menü
-- ────────────────────────────────────────────────────────────

local function OpenDealerMenu()
    if not exports["motortown"]:IsPlayerLoaded() then return end

    local level = exports["motortown"]:GetLevel()
    local money = exports["motortown"]:GetMoney()

    -- Fahrzeuge nach Kategorie gruppieren
    local categories = {}
    for model, cfg in pairs(Config.Vehicles) do
        local cat = cfg.category or cfg.vehicleType
        if not categories[cat] then categories[cat] = {} end
        table.insert(categories[cat], { model = model, cfg = cfg })
    end

    -- Kategorie-Auswahl zuerst
    local catOptions = {}
    local catLabels  = {
        semi         = "🚛 Sattelzüge",
        flatbed      = "🪵 Tieflader",
        kipper       = "⛏️ Kipper",
        tanker       = "⛽ Tanker",
        garbage      = "🗑️ Müllfahrzeuge",
        refrigerated = "❄️ Kühlfahrzeuge",
    }

    for cat, vehicles in pairs(categories) do
        -- Sortieren nach Preis
        table.sort(vehicles, function(a, b) return a.cfg.price < b.cfg.price end)

        local vehicleOptions = {}
        for _, v in ipairs(vehicles) do
            local locked    = level < (v.cfg.minLevel or 1)
            local canAfford = money >= v.cfg.price

            table.insert(vehicleOptions, {
                title       = locked
                    and ("🔒 %s"):format(v.cfg.label)
                    or v.cfg.label,
                description = ("%s\nPreis: %s | Level: %d | Typ: %s"):format(
                    v.cfg.description or "",
                    Utils.FormatMoney(v.cfg.price),
                    v.cfg.minLevel or 1,
                    v.cfg.vehicleType
                ),
                disabled    = locked,
                onSelect    = locked and nil or function()
                    -- Kaufbestätigung
                    local confirmed = lib.alertDialog({
                        header   = ("Kaufen: %s"):format(v.cfg.label),
                        content  = ("Preis: **%s**\nGeld: **%s**"):format(
                            Utils.FormatMoney(v.cfg.price),
                            Utils.FormatMoney(money)
                        ),
                        centered = true,
                        cancel   = true,
                    })
                    if confirmed == "confirm" then
                        TriggerServerEvent("mt:vehicle:buy", { model = v.model })
                    end
                end,
            })
        end

        table.insert(catOptions, {
            title    = catLabels[cat] or cat,
            arrow    = true,
            onSelect = function()
                lib.registerContext({
                    id      = "mt_dealer_cat_" .. cat,
                    title   = catLabels[cat] or cat,
                    menu    = "mt_dealer",
                    options = vehicleOptions,
                })
                lib.showContext("mt_dealer_cat_" .. cat)
            end,
        })
    end

    lib.registerContext({
        id      = "mt_dealer",
        title   = "🚛 Fahrzeughändler",
        options = catOptions,
    })
    lib.showContext("mt_dealer")
end

-- ────────────────────────────────────────────────────────────
--  Garage Menü
-- ────────────────────────────────────────────────────────────

local function OpenGarageMenu(zoneName, zoneData)
    TriggerServerEvent("mt:vehicle:garageOpen")
end

local function ShowGarageList(vehicles, zoneName)
    if not vehicles or #vehicles == 0 then
        lib.notify({
            title       = "Garage leer",
            description = "Du besitzt noch keine Fahrzeuge.",
            type        = "inform",
        })
        return
    end

    local options = {}
    for _, v in ipairs(vehicles) do
        local statusIcon = v.stored and "🅿️" or "🚛"
        local upgCount   = 0
        for _ in pairs(v.upgrades) do upgCount = upgCount + 1 end

        table.insert(options, {
            title       = ("%s %s"):format(statusIcon, v.model),
            description = ("Kennzeichen: %s | Upgrades: %d | Kraftstoff: %d%%"):format(
                v.plate, upgCount, v.fuel
            ),
            disabled    = not v.stored,
            onSelect    = function()
                -- Spawn-Koordinaten aus Zone holen
                local zone = Config.Zones[zoneName]
                local spawnCoords = zone and zone.coords or GetEntityCoords(PlayerPedId())
                TriggerServerEvent("mt:vehicle:retrieve", {
                    vehicleId = v.id,
                    spawnZone = zoneName,
                })
            end,
        })
    end

    lib.registerContext({
        id      = "mt_garage",
        title   = "🅿️ Garage",
        options = options,
    })
    lib.showContext("mt_garage")
end

-- ────────────────────────────────────────────────────────────
--  Upgrade Menü
-- ────────────────────────────────────────────────────────────

local function OpenUpgradeMenu()
    if not spawnedVehicle then
        lib.notify({
            title       = "Kein Fahrzeug",
            description = "Du musst in einem Motortown-Fahrzeug sitzen.",
            type        = "error",
        })
        return
    end

    local money    = exports["motortown"]:GetMoney()
    local upgrades = spawnedVehicle.upgrades
    local options  = {}

    for upgradeKey, upgradeCfg in pairs(Config.Upgrades) do
        local currentLevel = upgrades[upgradeKey] or 0
        local maxLevel     = #upgradeCfg.levels
        local nextLevel    = currentLevel + 1

        local title        = ("%s %s"):format(upgradeCfg.icon or "🔧", upgradeCfg.label)
        local desc

        if currentLevel >= maxLevel then
            desc = "✅ Vollständig aufgerüstet"
            table.insert(options, {
                title       = title,
                description = desc,
                disabled    = true,
            })
        else
            local nextCfg   = upgradeCfg.levels[nextLevel]
            local prevPrice = currentLevel > 0 and upgradeCfg.levels[currentLevel].price or 0
            local cost      = nextCfg.price - prevPrice
            local canAfford = money >= cost

            desc            = ("%s\nStufe %d → %d | Kosten: %s%s"):format(
                upgradeCfg.description,
                currentLevel, nextLevel,
                Utils.FormatMoney(cost),
                not canAfford and " ❌" or ""
            )

            table.insert(options, {
                title       = title,
                description = desc,
                disabled    = not canAfford,
                onSelect    = function()
                    TriggerServerEvent(MT.VEHICLE_UPGRADE_BUY, {
                        vehicleId  = spawnedVehicle.id,
                        upgradeKey = upgradeKey,
                        level      = nextLevel,
                    })
                end,
            })
        end
    end

    lib.registerContext({
        id      = "mt_upgrades",
        title   = ("🔧 Upgrades – %s"):format(spawnedVehicle.plate),
        options = options,
    })
    lib.showContext("mt_upgrades")
end

-- ────────────────────────────────────────────────────────────
--  Reparatur
-- ────────────────────────────────────────────────────────────

local function RepairVehicle()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        -- Prüfe ob Fahrzeug in der Nähe (Spieler ist ausgestiegen)
        vehicle = GetClosestVehicle(
            GetEntityCoords(ped).x, GetEntityCoords(ped).y,
            GetEntityCoords(ped).z, 5.0, 0, 70
        )
    end
    if not vehicle or vehicle == 0 then
        lib.notify({ title = "Kein Fahrzeug in der Nähe", type = "error" })
        return
    end

    local health    = GetVehicleBodyHealth(vehicle)
    local damage    = Utils.Round(1.0 - (health / 1000.0), 3)
    local cost      = math.max(
        Config.RepairMinCost,
        math.floor(damage * 1000 * Config.RepairCostPerDamage)
    )

    -- Vorschau der Kosten
    local confirmed = lib.alertDialog({
        header   = "Fahrzeug reparieren",
        content  = ("Schaden: **%.0f%%**\nKosten: **%s**"):format(
            damage * 100, Utils.FormatMoney(cost)),
        centered = true,
        cancel   = true,
    })
    if confirmed ~= "confirm" then return end

    local success = lib.progressBar({
        duration     = Config.RepairProgressMs,
        label        = "Fahrzeug wird repariert...",
        useWhileDead = false,
        canCancel    = false,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = "mini@repair", clip = "fixing_a_player" },
    })
    if not success then return end

    TriggerServerEvent("mt:vehicle:repairPay", { damage = damage })
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

local function OnBuyResult(data)
    if not data.success then
        lib.notify({ title = "Kauf fehlgeschlagen", description = data.error, type = "error" })
        return
    end
    lib.notify({
        title       = "🚛 Fahrzeug gekauft!",
        description = ("%s – Kennzeichen: %s"):format(data.label, data.plate),
        type        = "success",
        duration    = 8000,
    })
end

local function OnGarageList(vehicles)
    -- Zonename ist beim Aufruf von OpenGarageMenu bekannt,
    -- hier merken wir ihn in einem Closure
    ShowGarageList(vehicles, VehicleModule._lastGarageZone or "garage_stadtmitte")
end

local function OnSpawnData(data)
    if not data.success then
        lib.notify({ title = "Fehler", description = data.error, type = "error" })
        return
    end

    local zone        = Config.Zones[data.spawnZone]
    local baseCoords  = zone and zone.coords or GetEntityCoords(PlayerPedId())
    local spawnCoords = vec3(
        baseCoords.x + Config.SpawnOffset.x,
        baseCoords.y + Config.SpawnOffset.y,
        baseCoords.z + Config.SpawnOffset.z
    )

    SpawnVehicle(data, spawnCoords, 0.0)
end

local function OnUpgradeResult(data)
    if not data.success then
        lib.notify({ title = "Upgrade fehlgeschlagen", description = data.error, type = "error" })
        return
    end

    -- Upgrade lokal anwenden ohne neu spawnen
    if spawnedVehicle then
        spawnedVehicle.upgrades[data.upgradeKey] = data.level
        ApplyUpgrades(spawnedVehicle.entity, spawnedVehicle.upgrades)
    end

    lib.notify({
        title       = "✅ Upgrade installiert",
        description = ("Stufe %d erfolgreich eingebaut."):format(data.level),
        type        = "success",
    })
end

local function OnRepairResult(data)
    if not data.success then
        lib.notify({ title = "Reparatur fehlgeschlagen", description = data.error, type = "error" })
        return
    end

    -- Fahrzeug tatsächlich reparieren
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
        lastHealth = 1000.0
    end

    lib.notify({
        title       = "🔧 Reparatur abgeschlossen",
        description = ("Kosten: %s"):format(Utils.FormatMoney(data.cost)),
        type        = "success",
    })
end

local function OnVehicleStoreResult(data)
    if not data.success then
        pendingStorePlate = nil
        lib.notify({ title = "Einlagern fehlgeschlagen", description = data.error, type = "error" })
        return
    end

    -- Fahrzeug löschen (das tatsächlich eingelagerte)
    if spawnedVehicle and DoesEntityExist(spawnedVehicle.entity) then
        local storedPlate = pendingStorePlate or spawnedVehicle.plate
        if spawnedVehicle.plate == storedPlate then
            DeleteVehicle(spawnedVehicle.entity)
            spawnedVehicle = nil
        end
    end
    pendingStorePlate = nil

    lib.notify({ title = "🅿️ Fahrzeug eingelagert", type = "success" })
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug einlagern (aus Zone-Target)
-- ────────────────────────────────────────────────────────────

local STORE_RADIUS = 15.0 -- Meter – Fahrzeug muss innerhalb stehen

-- Gibt alle eigenen MT-Fahrzeuge zurück die innerhalb des Radius stehen
local function GetNearbyOwnVehicles(garageCoords)
    local found = {}

    -- Eigenes aktuell gespawntes Fahrzeug
    if spawnedVehicle and DoesEntityExist(spawnedVehicle.entity) then
        local vehCoords = GetEntityCoords(spawnedVehicle.entity)
        local dist      = #(garageCoords - vehCoords)
        if dist <= STORE_RADIUS then
            table.insert(found, {
                entity = spawnedVehicle.entity,
                plate  = spawnedVehicle.plate,
                id     = spawnedVehicle.id,
                dist   = Utils.Round(dist, 1),
            })
        end
    end

    return found
end

local function DoStoreVehicle(vehicleData)
    pendingStorePlate = vehicleData.plate
    local fuel        = GetVehicleFuelLevel(vehicleData.entity)
    local mileage     = _HudModule and _HudModule.GetOdometer() or 0
    TriggerServerEvent(MT.VEHICLE_STORE, {
        plate   = vehicleData.plate,
        fuel    = Utils.Round(fuel, 0),
        mileage = Utils.Round(mileage, 1),
    })
end

local function StoreCurrentVehicle(zoneName)
    local zone         = Config.Zones[zoneName or "garage_stadtmitte"]
    local garageCoords = zone and zone.coords or GetEntityCoords(PlayerPedId())

    local nearby       = GetNearbyOwnVehicles(garageCoords)

    if #nearby == 0 then
        lib.notify({
            title       = "Kein Fahrzeug in der Nähe",
            description = ("Dein Fahrzeug muss innerhalb von %dm zur Garage stehen."):format(STORE_RADIUS),
            type        = "error",
        })
        return
    end

    -- Nur ein Fahrzeug in der Nähe → direkt einlagern
    if #nearby == 1 then
        DoStoreVehicle(nearby[1])
        return
    end

    -- Mehrere Fahrzeuge → Auswahl anzeigen
    local options = {}
    for _, v in ipairs(nearby) do
        table.insert(options, {
            title       = ("🚛 %s"):format(v.plate),
            description = ("%.1f m entfernt"):format(v.dist),
            onSelect    = function()
                DoStoreVehicle(v)
            end,
        })
    end

    lib.registerContext({
        id      = "mt_store_select",
        title   = "Welches Fahrzeug einlagern?",
        options = options,
    })
    lib.showContext("mt_store_select")
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function VehicleModule.GetSpawnedVehicle()
    return spawnedVehicle
end

function VehicleModule.GetCurrentVehicleType()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end

    local hash = GetEntityModel(vehicle)
    for vType, models in pairs(Config.VehicleTypes) do
        for _, m in ipairs(models) do
            if GetHashKey(m) == hash then return vType end
        end
    end
    return nil
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function VehicleModule.Init()
    -- Server → Client Events
    RegisterNetEvent("mt:vehicle:buyResult", OnBuyResult)
    RegisterNetEvent("mt:vehicle:garageList", OnGarageList)
    RegisterNetEvent("mt:vehicle:spawnData", OnSpawnData)
    RegisterNetEvent("mt:vehicle:upgradeResult", OnUpgradeResult)
    RegisterNetEvent("mt:vehicle:repairResult", OnRepairResult)
    RegisterNetEvent("mt:vehicle:storeResult", OnVehicleStoreResult)

    -- Zone-Target Events (aus client/zones.lua)
    AddEventHandler("mt:ui:openDealer", function()
        OpenDealerMenu()
    end)

    AddEventHandler("mt:vehicle:retrieveFromGarage", function(zoneName)
        VehicleModule._lastGarageZone = zoneName
        OpenGarageMenu(zoneName)
    end)

    AddEventHandler("mt:vehicle:storeToGarage", function(zoneName)
        StoreCurrentVehicle(zoneName)
    end)

    AddEventHandler("mt:vehicle:repair", function()
        RepairVehicle()
    end)

    AddEventHandler("mt:ui:openUpgrades", function()
        OpenUpgradeMenu()
    end)

    exports("GetSpawnedVehicle", VehicleModule.GetSpawnedVehicle)
    exports("GetCurrentVehicleType", VehicleModule.GetCurrentVehicleType)

    print("[MT] VehicleModule (Client) initialisiert")
end

_VehicleModule = VehicleModule
