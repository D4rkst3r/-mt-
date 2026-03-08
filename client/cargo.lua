-- ============================================================
--  client/cargo.lua
--  Item-basiertes Cargo-System – Client-Seite
--
--  Öffnet das Lade-NUI wenn Spieler an einer Pickup-Zone
--  [E] drückt, und das Ablade-NUI an einer Delivery-Zone.
--
--  Integriert mit client/jobs.lua (cargoLoaded-Flag):
--  Nach erfolgreichem Laden wird MT.JOB_CARGO_LOADED gesetzt.
-- ============================================================

local CargoModule = {}

-- Aktuell geladenes Cargo (Client-seitige Kopie für HUD/Info)
local clientCargo = {
    items        = {}, -- { [itemKey] = amount }
    trailerModel = "",
    capacity     = 0,
    loadedAt     = 0,
}

-- ────────────────────────────────────────────────────────────
--  Trailer-Modell des aktuellen Anhängers ermitteln
-- ────────────────────────────────────────────────────────────

local function GetCurrentTrailerModel()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end

    -- Angekoppelter Trailer
    local trailer = GetVehicleTrailerVehicle(vehicle)
    if trailer and trailer ~= 0 and DoesEntityExist(trailer) then
        local hash = GetEntityModel(trailer)
        -- Hash zu Model-String konvertieren
        for trModel, _ in pairs(Config.TrailerCapacity or {}) do
            if GetHashKey(trModel) == hash then return trModel end
        end
        return nil
    end

    -- Kein Trailer – Fahrzeug selbst (Kipper, Mule, etc.)
    local vehHash = GetEntityModel(vehicle)
    for trModel, _ in pairs(Config.TrailerCapacity or {}) do
        if GetHashKey(trModel) == vehHash then return trModel end
    end

    return nil
end

-- Gesamte geladene Einheiten
local function TotalLoaded()
    local n = 0
    for _, amt in pairs(clientCargo.items) do n = n + amt end
    return n
end

-- ────────────────────────────────────────────────────────────
--  NUI öffnen: Laden
-- ────────────────────────────────────────────────────────────

function CargoModule.OpenLoadNUI(zoneName)
    local trModel = GetCurrentTrailerModel()
    if not trModel then
        lib.notify({
            title       = "Kein Trailer / Fahrzeug",
            description = "Koppel einen kompatiblen Trailer an oder nutze ein Cargo-Fahrzeug.",
            type        = "error",
        })
        return
    end

    -- Server fragen was hier verfügbar ist
    TriggerServerEvent("mt:cargo:requestPickup", {
        zone         = zoneName,
        trailerModel = trModel,
    })
end

-- ────────────────────────────────────────────────────────────
--  NUI öffnen: Abladen
-- ────────────────────────────────────────────────────────────

function CargoModule.OpenUnloadNUI(zoneName)
    if not next(clientCargo.items) then
        lib.notify({
            title       = "Kein Cargo geladen",
            description = "Lade zuerst Waren an einer Pickup-Zone.",
            type        = "error",
        })
        return
    end

    TriggerServerEvent("mt:cargo:requestDelivery", { zone = zoneName })
end

-- ────────────────────────────────────────────────────────────
--  Server → Client Event Handler
-- ────────────────────────────────────────────────────────────

local function OnPickupInfo(data)
    if data.error then
        lib.notify({ title = "Fehler", description = data.error, type = "error" })
        return
    end

    -- Cargo NUI öffnen (Lade-Modus)
    SendNUIMessage({
        action    = "cargoLoadOpen",
        zone      = data.zone,
        label     = data.label,
        items     = data.items,
        capacity  = data.capacity,
        usedSlots = data.usedSlots,
        trailer   = data.trailerLabel,
    })
    SetNuiFocus(true, true)
end

local function OnDeliveryInfo(data)
    if data.error then
        lib.notify({ title = "Fehler", description = data.error, type = "error" })
        return
    end

    -- Cargo NUI öffnen (Ablade-Modus)
    SendNUIMessage({
        action  = "cargoUnloadOpen",
        zone    = data.zone,
        label   = data.label,
        matches = data.matches,
    })
    SetNuiFocus(true, true)
end

local function OnLoadResult(data)
    if not data.success then
        lib.notify({ title = "Laden fehlgeschlagen", description = data.error, type = "error" })
        return
    end

    -- Client-Cargo aktualisieren
    clientCargo.items        = data.items or {}
    clientCargo.trailerModel = data.trailerModel or clientCargo.trailerModel
    clientCargo.capacity     = data.capacity or clientCargo.capacity
    clientCargo.loadedAt     = os.time()

    -- HUD-Update: Cargo-Indikator
    SendNUIMessage({
        action   = "cargoStateUpdate",
        items    = clientCargo.items,
        capacity = clientCargo.capacity,
        loaded   = data.totalLoaded,
    })

    lib.notify({
        title       = ("📦 %s geladen"):format(data.label),
        description = ("%d Einheiten | %d/%d Slots"):format(data.amount, data.totalLoaded, data.capacity),
        type        = "success",
    })

    -- Falls Spieler einen aktiven Job hat: cargoLoaded-Flag setzen
    local jobModule = _JobModule
    if jobModule and jobModule.GetCurrentJob and jobModule.GetCurrentJob() then
        TriggerEvent(MT.JOB_CARGO_LOADED, { cargoLoaded = true, stopsDone = 1, stopCount = 1, multiStop = false })
    end
end

local function OnUnloadResult(data)
    if not data.success then
        lib.notify({ title = "Abladen fehlgeschlagen", description = data.error, type = "error" })
        return
    end

    -- Cargo leeren (oder was übrig ist)
    local totalLeft = 0
    for _, log in ipairs(data.deliveryLog or {}) do
        local remaining = (clientCargo.items[log.item] or 0) - log.amount
        clientCargo.items[log.item] = remaining > 0 and remaining or nil
        totalLeft = totalLeft + math.max(0, remaining)
    end

    -- HUD-Update
    SendNUIMessage({
        action   = "cargoStateUpdate",
        items    = clientCargo.items,
        capacity = clientCargo.capacity,
        loaded   = totalLeft,
    })

    -- Erfolgs-Benachrichtigung
    local bonusText = data.townBonus and data.townBonus > 1.0
        and (" (×%.2f Stadtbonus)"):format(data.townBonus)
        or ""
    lib.notify({
        title       = "✅ Cargo abgeliefert",
        description = ("Lohn: %s%s"):format(Utils.FormatMoney(data.wage), bonusText),
        type        = "success",
        duration    = 6000,
    })

    if totalLeft == 0 then
        clientCargo = { items = {}, trailerModel = "", capacity = 0, loadedAt = 0 }
    end
end

-- ────────────────────────────────────────────────────────────
--  NUI Callbacks (NUI → Lua)
-- ────────────────────────────────────────────────────────────

RegisterNUICallback("cargoLoadClose", function(_, cb)
    SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback("cargoLoadConfirm", function(data, cb)
    -- data = { zone, item, amount, trailerModel }
    local trModel = GetCurrentTrailerModel() or data.trailerModel or ""
    TriggerServerEvent("mt:cargo:load", {
        zone         = data.zone,
        item         = data.item,
        amount       = tonumber(data.amount) or 0,
        trailerModel = trModel,
    })
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback("cargoUnloadClose", function(_, cb)
    SetNuiFocus(false, false); cb({})
end)

RegisterNUICallback("cargoUnloadConfirm", function(data, cb)
    -- data = { zone, items = { itemKey: amount, ... } }
    TriggerServerEvent("mt:cargo:unload", {
        zone  = data.zone,
        items = data.items,
    })
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback("cargoClear", function(_, cb)
    TriggerServerEvent("mt:cargo:clear")
    clientCargo = { items = {}, trailerModel = "", capacity = 0, loadedAt = 0 }
    SendNUIMessage({ action = "cargoStateUpdate", items = {}, capacity = 0, loaded = 0 })
    cb({})
end)

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function CargoModule.GetCargo()
    return clientCargo
end

function CargoModule.HasCargo()
    return next(clientCargo.items) ~= nil
end

function CargoModule.GetTotalLoaded()
    return TotalLoaded()
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function CargoModule.Init()
    RegisterNetEvent("mt:cargo:pickupInfo", OnPickupInfo)
    RegisterNetEvent("mt:cargo:deliveryInfo", OnDeliveryInfo)
    RegisterNetEvent("mt:cargo:loadResult", OnLoadResult)
    RegisterNetEvent("mt:cargo:unloadResult", OnUnloadResult)

    -- Zone-Events
    AddEventHandler("mt:job:startLoad", function(zoneName)
        CargoModule.OpenLoadNUI(zoneName)
    end)

    AddEventHandler("mt:job:startUnload", function(zoneName)
        CargoModule.OpenUnloadNUI(zoneName)
    end)

    -- Cargo-Anzeige im HUD beim Login laden
    AddEventHandler("mt:player:loaded", function()
        -- Server hat Cargo aus DB wiederhergestellt → kurzer Delay dann Status holen
        -- (optional: könnte auch via mt:cargo:loadResult initial gesetzt werden)
    end)

    exports("GetCargo", CargoModule.GetCargo)
    exports("HasCargo", CargoModule.HasCargo)
    exports("GetTotalLoaded", CargoModule.GetTotalLoaded)

    print("[MT] CargoModule (Client) initialisiert")
end

_CargoModule = CargoModule
