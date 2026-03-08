-- ============================================================
--  client/vehicles.lua
--  Zuständig für: Fahrzeug spawnen, HandlingFields anwenden,
--  Dealer-NUI, Garage-NUI, Upgrade-NUI, Schadensystem.
--
--  NUI-Panels ersetzen alle ox_lib Context-Menus:
--    dealerOpen  / dealerClose  / dealerBuy
--    garageOpen  / garageClose  / garageRetrieve
--    upgradeOpen / upgradeClose / upgradeRefresh / upgradeBuy
-- ============================================================

local VehicleModule     = {}

-- Aktuell gespawntes Fahrzeug des Spielers
local spawnedVehicle    = nil -- { entity, plate, id, upgrades }
local pendingStorePlate = nil -- Plate des Fahrzeugs das gerade eingelagert wird

-- Schadensüberwachung
local lastHealth        = 1000.0
local damageThread      = nil

-- Tracking ob Upgrade-Panel gerade offen ist (für Refresh nach Kauf)
local upgradePanel      = false

-- ────────────────────────────────────────────────────────────
--  HandlingFields anwenden
-- ────────────────────────────────────────────────────────────

local function ApplyUpgrades(vehicle, upgrades)
    if not vehicle or not upgrades then return end

    -- Alle Felder zuerst zurücksetzen (verhindert Upgrade-Stacking)
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
            for field, value in pairs(upgradeCfg.levels[level].fields) do
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

        lib.requestModel(model, 10000)
        while not HasModelLoaded(model) do Wait(50) end

        local vehicle = CreateVehicle(
            model, spawnCoords.x, spawnCoords.y, spawnCoords.z,
            heading or 0.0, true, false
        )

        while not DoesEntityExist(vehicle) do Wait(50) end

        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleNeedsToBeHotwired(vehicle, false)
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleNumberPlateText(vehicle, data.plate)

        if data.upgrades and next(data.upgrades) then
            ApplyUpgrades(vehicle, data.upgrades)
        end

        local ped = PlayerPedId()
        TaskWarpPedIntoVehicle(ped, vehicle, -1)

        local timeout = 0
        while GetVehiclePedIsIn(ped, false) ~= vehicle and timeout < 50 do
            Wait(100); timeout = timeout + 1
        end

        -- Motor nach Einsteigen anschalten (verhindert Abwürgen)
        SetVehicleEngineOn(vehicle, true, true, false)

        if GetVehiclePedIsIn(ped, false) ~= vehicle then
            local vCoords = GetEntityCoords(vehicle)
            SetNewWaypoint(vCoords.x, vCoords.y)
            lib.notify({ title = "Fahrzeug gespawnt", description = "Wegpunkt gesetzt.", type = "inform" })
        end

        SetVehicleFuelLevel(vehicle, data.fuel or 100.0)
        SetModelAsNoLongerNeeded(model)

        spawnedVehicle = { entity = vehicle, plate = data.plate, id = data.id, upgrades = data.upgrades or {} }

        if _HudModule then _HudModule.SetOdometerBase(data.mileage or 0) end

        VehicleModule.StartDamageThread()

        lib.notify({
            title       = "🚛 Fahrzeug geholt",
            description = ("%s – %s"):format(data.model, data.plate),
            type        = "success",
        })
    end)
end

-- ────────────────────────────────────────────────────────────
--  Schadensüberwachung
-- ────────────────────────────────────────────────────────────

function VehicleModule.StartDamageThread()
    if damageThread then return end

    damageThread = CreateThread(function()
        while true do
            Wait(2000)
            local sv = spawnedVehicle
            if not sv or not DoesEntityExist(sv.entity) then break end

            local health = GetVehicleBodyHealth(sv.entity)

            if math.abs(health - lastHealth) > 5 then
                lastHealth = health
                TriggerEvent(MT.VEHICLE_DAMAGE_SYNC, {
                    plate  = sv.plate,
                    health = health,
                    damage = Utils.Round(1.0 - (health / 1000.0), 3),
                })
            end

            if health <= 0 then
                lib.notify({
                    title = "⚠️ Fahrzeug beschädigt",
                    description = "Fahre zur Werkstatt.",
                    type = "warning",
                    duration = 8000,
                })
                break
            end
        end
        damageThread = nil
    end)
end

-- ────────────────────────────────────────────────────────────
--  Dealer NUI
-- ────────────────────────────────────────────────────────────

local function OpenDealerMenu()
    if not exports["motortown"]:IsPlayerLoaded() then return end

    local level = exports["motortown"]:GetLevel()
    local money = exports["motortown"]:GetMoney()
    local list  = {}

    for model, cfg in pairs(Config.Vehicles) do
        table.insert(list, {
            model       = model,
            label       = cfg.label,
            price       = cfg.price,
            minLevel    = cfg.minLevel or 1,
            vehicleType = cfg.vehicleType,
            category    = cfg.category or cfg.vehicleType,
            description = cfg.description or "",
            locked      = level < (cfg.minLevel or 1),
            canAfford   = money >= cfg.price,
        })
    end
    table.sort(list, function(a, b) return a.price < b.price end)

    SendNUIMessage({ action = "dealerOpen", money = money, level = level, vehicles = list })
    SetNuiFocus(true, true)
end

-- ────────────────────────────────────────────────────────────
--  Garage NUI
-- ────────────────────────────────────────────────────────────

local function OpenGarageMenu(zoneName)
    VehicleModule._lastGarageZone = zoneName
    TriggerServerEvent("mt:vehicle:garageOpen")
    -- OnGarageList empfängt die Server-Antwort und öffnet das Panel
end

local function ShowGaragePanel(vehicles, zoneName)
    if not vehicles or #vehicles == 0 then
        lib.notify({ title = "Garage leer", description = "Du besitzt noch keine Fahrzeuge.", type = "inform" })
        return
    end
    SendNUIMessage({ action = "garageOpen", zoneName = zoneName or "", vehicles = vehicles })
    SetNuiFocus(true, true)
end

-- ────────────────────────────────────────────────────────────
--  Upgrade NUI
-- ────────────────────────────────────────────────────────────

local function BuildUpgradeList(currentUpgrades, money)
    local result = {}
    for key, cfg in pairs(Config.Upgrades) do
        local curLevel  = currentUpgrades[key] or 0
        local maxLevel  = #cfg.levels
        local nextLevel = curLevel + 1
        local cost      = 0
        if nextLevel <= maxLevel then
            local prevPrice = curLevel > 0 and cfg.levels[curLevel].price or 0
            cost = cfg.levels[nextLevel].price - prevPrice
        end
        table.insert(result, {
            key          = key,
            label        = cfg.label,
            description  = cfg.description or "",
            currentLevel = curLevel,
            maxLevel     = maxLevel,
            nextLevel    = nextLevel,
            cost         = cost,
            canAfford    = money >= cost,
        })
    end
    return result
end

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
    local upgrades = BuildUpgradeList(spawnedVehicle.upgrades, money)

    SendNUIMessage({
        action    = "upgradeOpen",
        vehicleId = spawnedVehicle.id,
        plate     = spawnedVehicle.plate,
        money     = money,
        upgrades  = upgrades,
    })
    SetNuiFocus(true, true)
    upgradePanel = true
end

-- ────────────────────────────────────────────────────────────
--  Reparatur  (ox_lib progressBar bleibt – kein Menü-Flow)
-- ────────────────────────────────────────────────────────────

local function RepairVehicle()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        vehicle = GetClosestVehicle(GetEntityCoords(ped).x, GetEntityCoords(ped).y, GetEntityCoords(ped).z, 5.0, 0, 70)
    end
    if not vehicle or vehicle == 0 then
        lib.notify({ title = "Kein Fahrzeug in der Nähe", type = "error" }); return
    end

    local health    = GetVehicleBodyHealth(vehicle)
    local damage    = Utils.Round(1.0 - (health / 1000.0), 3)
    local cost      = math.max(Config.RepairMinCost, math.floor(damage * 1000 * Config.RepairCostPerDamage))

    local confirmed = lib.alertDialog({
        header = "🔧 Fahrzeug reparieren",
        content = ("Schaden: **%.0f%%**\nKosten: **%s**"):format(damage * 100, Utils.FormatMoney(cost)),
        centered = true,
        cancel = true,
    })
    if confirmed ~= "confirm" then return end

    local success = lib.progressBar({
        duration = Config.RepairProgressMs,
        label = "Fahrzeug wird repariert...",
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        anim    = { dict = "mini@repair", clip = "fixing_a_player" },
    })
    if not success then return end

    TriggerServerEvent("mt:vehicle:repairPay", { damage = damage })
end

-- ────────────────────────────────────────────────────────────
--  Fahrzeug einlagern
-- ────────────────────────────────────────────────────────────

local STORE_RADIUS = 20.0

local function GetNearbyOwnVehicles()
    local found     = {}
    local pedCoords = GetEntityCoords(PlayerPedId())

    if spawnedVehicle and DoesEntityExist(spawnedVehicle.entity) then
        local dist = #(pedCoords - GetEntityCoords(spawnedVehicle.entity))
        if dist <= STORE_RADIUS then
            table.insert(found,
                { entity = spawnedVehicle.entity, plate = spawnedVehicle.plate, id = spawnedVehicle.id, dist = Utils
                .Round(dist, 1) })
        end
    else
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not vehicle or vehicle == 0 then
            vehicle = GetClosestVehicle(pedCoords.x, pedCoords.y, pedCoords.z, STORE_RADIUS, 0, 70)
        end
        if vehicle and vehicle ~= 0 then
            local dist = #(pedCoords - GetEntityCoords(vehicle))
            if dist <= STORE_RADIUS then
                table.insert(found,
                    { entity = vehicle, plate = GetVehicleNumberPlateText(vehicle):gsub("%s+", ""), id = nil, dist =
                    Utils.Round(dist, 1) })
            end
        end
    end
    return found
end

local function NormalizePlate(plate)
    return plate and plate:gsub("%s+", ""):upper() or ""
end

local function DoStoreVehicle(vehicleData)
    pendingStorePlate = vehicleData.plate
    local fuel        = GetVehicleFuelLevel(vehicleData.entity)
    local mileage     = _HudModule and _HudModule.GetOdometer() or 0
    TriggerServerEvent(MT.VEHICLE_STORE, {
        plate     = NormalizePlate(vehicleData.plate),
        vehicleId = vehicleData.id,
        fuel      = Utils.Round(fuel, 0),
        mileage   = Utils.Round(mileage, 1),
    })
end

local function StoreCurrentVehicle(zoneName)
    local nearby = GetNearbyOwnVehicles()

    if #nearby == 0 then
        lib.notify({ title = "Kein Fahrzeug in der Nähe", description = ("Max. %dm Abstand."):format(STORE_RADIUS), type =
        "error" })
        return
    end
    if #nearby == 1 then
        DoStoreVehicle(nearby[1]); return
    end

    -- Edge-Case: mehrere Fahrzeuge → schnelle ox_lib Auswahl
    local options = {}
    for _, v in ipairs(nearby) do
        table.insert(options, {
            title       = ("🚛 %s"):format(v.plate),
            description = ("%.1f m entfernt"):format(v.dist),
            onSelect    = function() DoStoreVehicle(v) end,
        })
    end
    lib.registerContext({ id = "mt_store_select", title = "Welches Fahrzeug einlagern?", options = options })
    lib.showContext("mt_store_select")
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

local function OnBuyResult(data)
    if not data.success then
        lib.notify({ title = "Kauf fehlgeschlagen", description = data.error, type = "error" }); return
    end
    lib.notify({
        title = "🚛 Fahrzeug gekauft!",
        description = ("%s – Kennzeichen: %s"):format(data.label, data.plate),
        type = "success",
        duration = 8000,
    })
end

local function OnGarageList(vehicles)
    ShowGaragePanel(vehicles, VehicleModule._lastGarageZone or "")
end

local function OnSpawnData(data)
    if not data.success then
        lib.notify({ title = "Fehler", description = data.error, type = "error" }); return
    end

    local zone = Config.Zones[data.spawnZone]
    local spawnCoords, heading

    if zone and zone.spawnCoords then
        spawnCoords = zone.spawnCoords
        heading     = zone.spawnHeading or 0.0
    elseif zone then
        local base  = zone.coords
        spawnCoords = vec3(base.x + Config.SpawnOffset.x, base.y + Config.SpawnOffset.y, base.z + Config.SpawnOffset.z)
        heading     = 0.0
    else
        spawnCoords = GetEntityCoords(PlayerPedId())
        heading     = GetEntityHeading(PlayerPedId())
    end

    SpawnVehicle(data, spawnCoords, heading)
end

local function OnUpgradeResult(data)
    if not data.success then
        lib.notify({ title = "Upgrade fehlgeschlagen", description = data.error, type = "error" }); return
    end

    if spawnedVehicle then
        spawnedVehicle.upgrades[data.upgradeKey] = data.level
        ApplyUpgrades(spawnedVehicle.entity, spawnedVehicle.upgrades)
    end

    lib.notify({
        title       = "✅ Upgrade installiert",
        description = ("Stufe %d erfolgreich eingebaut."):format(data.level),
        type        = "success",
    })

    -- Upgrade-Panel live refreshen wenn offen
    if upgradePanel and spawnedVehicle then
        local money    = exports["motortown"]:GetMoney()
        local upgrades = BuildUpgradeList(spawnedVehicle.upgrades, money)
        SendNUIMessage({ action = "upgradeRefresh", upgrades = upgrades, money = money })
    end
end

local function OnRepairResult(data)
    if not data.success then
        lib.notify({ title = "Reparatur fehlgeschlagen", description = data.error, type = "error" }); return
    end

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
        lib.notify({ title = "Einlagern fehlgeschlagen", description = data.error, type = "error" }); return
    end

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
--  NUI Callbacks  (NUI → Lua)
-- ────────────────────────────────────────────────────────────

RegisterNUICallback("dealerClose", function(_, cb)
    SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback("dealerBuy", function(data, cb)
    if data and data.model then
        TriggerServerEvent("mt:vehicle:buy", { model = data.model })
    end
    cb({})
end)

RegisterNUICallback("garageClose", function(_, cb)
    SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback("garageRetrieve", function(data, cb)
    if data and data.vehicleId then
        TriggerServerEvent("mt:vehicle:retrieve", {
            vehicleId = data.vehicleId,
            spawnZone = data.zoneName or VehicleModule._lastGarageZone,
        })
    end
    cb({})
end)

RegisterNUICallback("upgradeClose", function(_, cb)
    upgradePanel = false
    SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback("upgradeBuy", function(data, cb)
    if not spawnedVehicle or not data then
        cb({}); return
    end
    TriggerServerEvent(MT.VEHICLE_UPGRADE_BUY, {
        vehicleId  = spawnedVehicle.id,
        upgradeKey = data.upgradeKey,
        level      = data.level,
    })
    cb({})
end)

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
    RegisterNetEvent("mt:vehicle:buyResult", OnBuyResult)
    RegisterNetEvent("mt:vehicle:garageList", OnGarageList)
    RegisterNetEvent("mt:vehicle:spawnData", OnSpawnData)
    RegisterNetEvent("mt:vehicle:upgradeResult", OnUpgradeResult)
    RegisterNetEvent("mt:vehicle:repairResult", OnRepairResult)
    RegisterNetEvent("mt:vehicle:storeResult", OnVehicleStoreResult)

    AddEventHandler("mt:ui:openDealer", function() OpenDealerMenu() end)
    AddEventHandler("mt:vehicle:retrieveFromGarage", function(zoneName) OpenGarageMenu(zoneName) end)
    AddEventHandler("mt:vehicle:storeToGarage", function(zoneName) StoreCurrentVehicle(zoneName) end)
    AddEventHandler("mt:vehicle:repair", function() RepairVehicle() end)
    AddEventHandler("mt:ui:openUpgrades", function() OpenUpgradeMenu() end)

    -- Resource Stop: Tankstand + Kilometerstand sichern
    AddEventHandler("onResourceStop", function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end
        if not spawnedVehicle or not DoesEntityExist(spawnedVehicle.entity) then return end
        TriggerServerEvent("mt:vehicle:emergencyStore", {
            plate   = spawnedVehicle.plate,
            fuel    = Utils.Round(GetVehicleFuelLevel(spawnedVehicle.entity), 0),
            mileage = Utils.Round(_HudModule and _HudModule.GetOdometer() or 0, 1),
        })
    end)

    exports("GetSpawnedVehicle", VehicleModule.GetSpawnedVehicle)
    exports("GetCurrentVehicleType", VehicleModule.GetCurrentVehicleType)

    print("[MT] VehicleModule (Client) initialisiert")
end

_VehicleModule = VehicleModule
