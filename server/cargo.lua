-- ============================================================
--  server/cargo.lua
--  Item-basiertes Cargo-System
--
--  Zuständig für:
--  - Aktives Cargo pro Spieler tracken (Memory + DB)
--  - Laden validieren (Zone bietet Item an? Trailer nimmt es?)
--  - Abladen validieren (Zone nimmt Item? Menge ok?)
--  - Lohn pro gelieferte Einheit auszahlen
--  - Fabrik-Input-Stock erhöhen bei Lieferung
--  - Admin: Items und Delivery Points konfigurieren (in mt_config)
-- ============================================================

local CargoModule   = {}

-- In-Memory: [identifier] = cargoState
-- cargoState = {
--   items         = { [itemKey] = amount, ... },
--   trailerModel  = "trailers",
--   capacity      = 30,
--   pickupZone    = "ladezone_holz",
--   loadedAt      = os.time(),
-- }
local activeCargo   = {}

-- Live-Stock der Pickup-Punkte: [zoneKey][itemKey] = currentStock
-- Wird beim Init aus DB geladen, dann nur In-Memory
local pickupStocks  = {}

-- Config-Overrides aus DB (Admin-Overrides überschreiben Lua-Config)
local dpOverrides   = {}  -- deliverypoint overrides: [zoneKey] = data
local itemOverrides = {}  -- item overrides:          [itemKey]  = data

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

-- Gibt die effektive DeliveryPoint-Config zurück (Override > Lua-Config)
local function GetDeliveryPoint(zoneKey)
    if dpOverrides[zoneKey] then return dpOverrides[zoneKey] end
    return Config.DeliveryPoints and Config.DeliveryPoints[zoneKey] or nil
end

-- Gibt die effektive Item-Config zurück (Override > Lua-Config)
local function GetItem(itemKey)
    if itemOverrides[itemKey] then return itemOverrides[itemKey] end
    return Config.Items and Config.Items[itemKey] or nil
end

-- Identifier des Spielers (nutzt Utils aus shared/utils.lua)
local function GetId(src)
    return Utils.GetIdentifier(src)
end

-- Gesamte Einheiten im Cargo
local function TotalCargoUnits(cargo)
    local n = 0
    for _, amt in pairs(cargo.items) do n = n + amt end
    return n
end

-- ────────────────────────────────────────────────────────────
--  Pickup-Stock Verwaltung
-- ────────────────────────────────────────────────────────────

local function InitPickupStocks()
    -- Alle Pickup-Punkte aus Config initialisieren
    if not Config.DeliveryPoints then return end
    for zoneKey, dp in pairs(Config.DeliveryPoints) do
        if dp.type == "pickup" then
            pickupStocks[zoneKey] = {}
            for _, offer in ipairs(dp.offeredItems or {}) do
                pickupStocks[zoneKey][offer.item] = offer.maxStock or 50
            end
        end
    end
end

-- Stock-Refresh-Loop (respawnt Lager langsam)
local function StartStockRefreshLoop()
    CreateThread(function()
        while true do
            Wait(60000) -- jede Minute prüfen
            local now = os.time()
            if not Config.DeliveryPoints then goto skipRefresh end

            for zoneKey, dp in pairs(Config.DeliveryPoints) do
                if dp.type == "pickup" and pickupStocks[zoneKey] then
                    for _, offer in ipairs(dp.offeredItems or {}) do
                        local key      = offer.item
                        local max      = offer.maxStock or 50
                        local refillMs = (offer.stockRefillMin or 15) * 60 * 1000
                        local stocks   = pickupStocks[zoneKey]

                        -- Jede Minute: Prozentual auffüllen (1 Einheit pro Minute)
                        if stocks[key] and stocks[key] < max then
                            stocks[key] = math.min(max, stocks[key] + 1)
                        end
                    end
                end
            end

            ::skipRefresh::
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  DB: Cargo persistieren (für Restart-Sicherheit)
-- ────────────────────────────────────────────────────────────

local function SaveCargoToDB(identifier, cargo)
    if not cargo then
        MySQL.rawExecute("DELETE FROM mt_cargo WHERE identifier = ?", { identifier })
        return
    end
    MySQL.rawExecute(
        [[INSERT INTO mt_cargo (identifier, items, trailer_model, pickup_zone, loaded_at)
          VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            items         = VALUES(items),
            trailer_model = VALUES(trailer_model),
            pickup_zone   = VALUES(pickup_zone),
            loaded_at     = VALUES(loaded_at)]],
        {
            identifier,
            json.encode(cargo.items),
            cargo.trailerModel or "",
            cargo.pickupZone or "",
            os.date("%Y-%m-%d %H:%M:%S", cargo.loadedAt or os.time()),
        }
    )
end

local function LoadCargoDB(cb)
    MySQL.query("SELECT * FROM mt_cargo", {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                local ok, items = pcall(json.decode, row.items)
                if ok and items then
                    -- Kapazität aus Trailer-Config holen
                    local tc                    = Config.TrailerCapacity and Config.TrailerCapacity[row.trailer_model]
                    local capacity              = tc and tc.capacity or 30

                    activeCargo[row.identifier] = {
                        items        = items,
                        trailerModel = row.trailer_model,
                        capacity     = capacity,
                        pickupZone   = row.pickup_zone,
                        loadedAt     = os.time(), -- ungefähr
                    }
                end
            end
        end
        if cb then cb() end
    end)
end

-- ────────────────────────────────────────────────────────────
--  DB-Overrides laden (Admin-Konfigurationen)
-- ────────────────────────────────────────────────────────────

local function LoadOverrides(cb)
    MySQL.query(
        "SELECT category, `key`, data FROM mt_config WHERE category IN ('item','deliverypoint') AND deleted = 0",
        {},
        function(rows)
            if rows then
                for _, row in ipairs(rows) do
                    local ok, data = pcall(json.decode, row.data)
                    if ok then
                        if row.category == "item" then
                            itemOverrides[row.key] = data
                        elseif row.category == "deliverypoint" then
                            dpOverrides[row.key] = data
                        end
                    end
                end
            end
            if cb then cb() end
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  NET EVENTS: Laden
-- ────────────────────────────────────────────────────────────

-- Client fragt verfügbare Items an einem Pickup-Punkt an
local function OnRequestPickupItems(data)
    local source = source
    local id     = GetId(source)
    if not id or not data or not data.zone then return end

    local dp = GetDeliveryPoint(data.zone)
    if not dp or dp.type ~= "pickup" then
        TriggerClientEvent("mt:cargo:pickupInfo", source, { error = "Keine Ladezone." })
        return
    end

    -- Trailer-Kapazität ermitteln (Client schickt trailerModel mit)
    local trailerModel = data.trailerModel or ""
    local tc           = Config.TrailerCapacity and Config.TrailerCapacity[trailerModel]
    local capacity     = tc and tc.capacity or 0
    local filter       = tc and tc.acceptedCategories or {}

    if capacity == 0 then
        TriggerClientEvent("mt:cargo:pickupInfo", source, { error = "Kein kompatibler Trailer/Fahrzeug gefunden." })
        return
    end

    -- Bereits geladenes Cargo des Spielers
    local existing  = activeCargo[id]
    local usedSlots = existing and TotalCargoUnits(existing) or 0
    local freeSlots = capacity - usedSlots

    -- Filtere Items nach Trailer-Kompatibilität
    local items     = {}
    local stocks    = pickupStocks[data.zone] or {}
    for _, offer in ipairs(dp.offeredItems or {}) do
        local itemCfg = GetItem(offer.item)
        if itemCfg then
            -- Prüfen ob Trailer diese Kategorie akzeptiert
            local ok = false
            for _, cat in ipairs(filter) do
                if cat == itemCfg.category then
                    ok = true; break
                end
            end

            if ok then
                local stock = stocks[offer.item] or 0
                table.insert(items, {
                    key           = offer.item,
                    label         = itemCfg.label,
                    icon          = itemCfg.icon,
                    category      = itemCfg.category,
                    stock         = stock,
                    maxAmount     = math.min(offer.maxStock or 50, freeSlots, stock),
                    currentLoaded = (existing and existing.items[offer.item]) or 0,
                    perishable    = itemCfg.perishable or false,
                    dangerous     = itemCfg.dangerous or false,
                })
            end
        end
    end

    TriggerClientEvent("mt:cargo:pickupInfo", source, {
        zone         = data.zone,
        label        = dp.label or data.zone,
        items        = items,
        capacity     = capacity,
        usedSlots    = usedSlots,
        trailerModel = trailerModel,
        trailerLabel = tc and tc.label or trailerModel,
    })
end

-- Client bestätigt: X Einheiten von Item Y laden
local function OnCargoLoad(data)
    local source = source
    local id     = GetId(source)
    if not id or not data then return end

    -- Validierung
    local zone    = data.zone
    local itemKey = data.item
    local amount  = tonumber(data.amount) or 0
    local trModel = data.trailerModel or ""

    if amount <= 0 then
        TriggerClientEvent("mt:cargo:loadResult", source, { success = false, error = "Ungültige Menge." })
        return
    end

    local dp = GetDeliveryPoint(zone)
    if not dp or dp.type ~= "pickup" then
        TriggerClientEvent("mt:cargo:loadResult", source, { success = false, error = "Keine Ladezone." })
        return
    end

    local itemCfg = GetItem(itemKey)
    if not itemCfg then
        TriggerClientEvent("mt:cargo:loadResult", source, { success = false, error = "Unbekanntes Item." })
        return
    end

    -- Stock prüfen
    local stocks = pickupStocks[zone] or {}
    if (stocks[itemKey] or 0) < amount then
        TriggerClientEvent("mt:cargo:loadResult", source, {
            success = false,
            error   = ("Nicht genug %s vorrätig (noch %d)."):format(itemCfg.label, stocks[itemKey] or 0)
        })
        return
    end

    -- Trailer-Kapazität prüfen
    local tc        = Config.TrailerCapacity and Config.TrailerCapacity[trModel]
    local capacity  = tc and tc.capacity or 0

    local existing  = activeCargo[id] or
    { items = {}, trailerModel = trModel, capacity = capacity, pickupZone = zone, loadedAt = os.time() }
    local usedSlots = TotalCargoUnits(existing)

    if usedSlots + amount > capacity then
        TriggerClientEvent("mt:cargo:loadResult", source, {
            success = false,
            error   = ("Trailer voll! Frei: %d Slots."):format(capacity - usedSlots)
        })
        return
    end

    -- Kategorie-Kompatibilität
    if tc then
        local ok = false
        for _, cat in ipairs(tc.acceptedCategories or {}) do
            if cat == itemCfg.category then
                ok = true; break
            end
        end
        if not ok then
            TriggerClientEvent("mt:cargo:loadResult", source, {
                success = false,
                error   = ("Dieser Trailer nimmt keine %s."):format(Config.ItemCategories and
                Config.ItemCategories[itemCfg.category] and Config.ItemCategories[itemCfg.category].label or
                itemCfg.category)
            })
            return
        end
    end

    -- Alles OK → laden
    stocks[itemKey]         = (stocks[itemKey] or 0) - amount
    existing.items[itemKey] = (existing.items[itemKey] or 0) + amount
    if existing.items[itemKey] <= 0 then existing.items[itemKey] = nil end

    existing.trailerModel = trModel
    existing.capacity     = capacity
    existing.pickupZone   = zone
    if not existing.loadedAt then existing.loadedAt = os.time() end

    activeCargo[id] = existing
    SaveCargoToDB(id, existing)

    local total = TotalCargoUnits(existing)
    TriggerClientEvent("mt:cargo:loadResult", source, {
        success     = true,
        item        = itemKey,
        label       = itemCfg.label,
        amount      = amount,
        totalLoaded = total,
        capacity    = capacity,
        items       = existing.items,
    })
end

-- ────────────────────────────────────────────────────────────
--  NET EVENTS: Abladen
-- ────────────────────────────────────────────────────────────

-- Client fragt was eine Delivery-Zone akzeptiert + was Spieler geladen hat
local function OnRequestDeliveryInfo(data)
    local source = source
    local id     = GetId(source)
    if not id or not data or not data.zone then return end

    local dp = GetDeliveryPoint(data.zone)
    if not dp or dp.type ~= "delivery" then
        TriggerClientEvent("mt:cargo:deliveryInfo", source, { error = "Keine Ablieferzone." })
        return
    end

    local cargo = activeCargo[id]
    if not cargo or not next(cargo.items) then
        TriggerClientEvent("mt:cargo:deliveryInfo", source, { error = "Du hast kein Cargo geladen." })
        return
    end

    -- Erstelle Liste der annehmlichen Items + was der Spieler davon hat
    local matches = {}
    for _, accept in ipairs(dp.acceptedItems or {}) do
        local inTrailer = cargo.items[accept.item] or 0
        if inTrailer > 0 then
            local itemCfg = GetItem(accept.item)
            if itemCfg then
                local deliverable = math.min(inTrailer, accept.maxPerDeliv or 99)
                local pay         = deliverable * (accept.pricePerUnit or 100)

                -- Perishable: Abzug wenn zu lange unterwegs
                local penalty     = 1.0
                if itemCfg.perishable and cargo.loadedAt then
                    local elapsedMin = (os.time() - cargo.loadedAt) / 60.0
                    local perishMin  = itemCfg.perishMin or 45
                    if elapsedMin > perishMin then
                        penalty = 0.0 -- komplett verdorben
                    elseif elapsedMin > (perishMin * 0.6) then
                        penalty = 0.5 -- halb verdorben
                    end
                end

                table.insert(matches, {
                    key          = accept.item,
                    label        = itemCfg.label,
                    icon         = itemCfg.icon,
                    inTrailer    = inTrailer,
                    deliverable  = deliverable,
                    pricePerUnit = accept.pricePerUnit or 100,
                    totalPay     = math.floor(pay * penalty),
                    penalty      = penalty,
                    maxPerDeliv  = accept.maxPerDeliv or 99,
                })
            end
        end
    end

    if #matches == 0 then
        TriggerClientEvent("mt:cargo:deliveryInfo", source, {
            error = "Diese Zone nimmt deine Waren nicht an."
        })
        return
    end

    TriggerClientEvent("mt:cargo:deliveryInfo", source, {
        zone    = data.zone,
        label   = dp.label or data.zone,
        matches = matches,
    })
end

-- Client bestätigt Ablieferung
local function OnCargoUnload(data)
    local source = source
    local id     = GetId(source)
    if not id or not data then return end

    local zone  = data.zone
    local items = data.items   -- { [itemKey] = amount, ... }

    if not items or not next(items) then
        TriggerClientEvent("mt:cargo:unloadResult", source, { success = false, error = "Keine Items ausgewählt." })
        return
    end

    local dp = GetDeliveryPoint(zone)
    if not dp or dp.type ~= "delivery" then
        TriggerClientEvent("mt:cargo:unloadResult", source, { success = false, error = "Keine Ablieferzone." })
        return
    end

    local cargo = activeCargo[id]
    if not cargo then
        TriggerClientEvent("mt:cargo:unloadResult", source, { success = false, error = "Kein Cargo geladen." })
        return
    end

    -- Akzeptanz-Map aufbauen
    local acceptMap = {}
    for _, accept in ipairs(dp.acceptedItems or {}) do
        acceptMap[accept.item] = accept
    end

    -- Jeden Item-Typ validieren und Lohn berechnen
    local totalWage     = 0
    local deliveryLog   = {}
    local factoryBoosts = {} -- [factoryKey] = amount (für Supply-Chain)

    for itemKey, deliverAmt in pairs(items) do
        deliverAmt = tonumber(deliverAmt) or 0
        if deliverAmt <= 0 then goto nextItem end

        local accept = acceptMap[itemKey]
        if not accept then goto nextItem end -- Zone nimmt das nicht

        local itemCfg = GetItem(itemKey)
        if not itemCfg then goto nextItem end

        -- Sicherheit: Spieler hat wirklich soviel
        local inTrailer = cargo.items[itemKey] or 0
        local actual    = math.min(deliverAmt, inTrailer, accept.maxPerDeliv or 99)
        if actual <= 0 then goto nextItem end

        -- Perishable Penalty
        local penalty = 1.0
        if itemCfg.perishable and cargo.loadedAt then
            local elapsedMin = (os.time() - cargo.loadedAt) / 60.0
            local perishMin  = itemCfg.perishMin or 45
            if elapsedMin > perishMin then
                penalty = 0.0
            elseif elapsedMin > (perishMin * 0.6) then
                penalty = 0.5
            end
        end

        local pay = math.floor(actual * (accept.pricePerUnit or 100) * penalty)
        totalWage = totalWage + pay

        -- Cargo abziehen
        cargo.items[itemKey] = inTrailer - actual
        if cargo.items[itemKey] <= 0 then cargo.items[itemKey] = nil end

        -- Fabrik-Stock erhöhen
        if accept.factoryKey then
            factoryBoosts[accept.factoryKey] = (factoryBoosts[accept.factoryKey] or 0) + actual
        end

        table.insert(deliveryLog, {
            item    = itemKey,
            label   = itemCfg.label,
            amount  = actual,
            pay     = pay,
            penalty = penalty,
        })

        ::nextItem::
    end

    if #deliveryLog == 0 then
        TriggerClientEvent("mt:cargo:unloadResult", source, { success = false, error = "Keine lieferbaren Waren." })
        return
    end

    -- Town Bonus anwenden
    local townBonus = _TownBonusModule and _TownBonusModule.GetBonusForDelivery(zone) or 1.0
    local finalWage = math.floor(totalWage * townBonus)

    -- Lohn auszahlen
    if finalWage > 0 then
        _PlayerModule.AddMoney(source, finalWage, ("Cargo geliefert: %s"):format(dp.label or zone))
        _PlayerModule.AddXP(source, Config.XPBaseDelivery or 50)
        _PlayerModule.IncrementDeliveries(source)
    end

    -- Town Bonus erhöhen
    if _TownBonusModule then _TownBonusModule.OnDelivery(zone) end

    -- Fabrik-Stocks erhöhen (Supply-Chain)
    if _SupplyChainModule then
        for factoryKey, amount in pairs(factoryBoosts) do
            _SupplyChainModule.AddInputStock(factoryKey, amount)
        end
    end

    -- Cargo-State aktualisieren / leeren
    if not next(cargo.items) then
        activeCargo[id] = nil
        SaveCargoToDB(id, nil)
    else
        SaveCargoToDB(id, cargo)
    end

    TriggerClientEvent("mt:cargo:unloadResult", source, {
        success     = true,
        deliveryLog = deliveryLog,
        wage        = finalWage,
        townBonus   = townBonus,
    })
end

-- ────────────────────────────────────────────────────────────
--  NET EVENTS: Cargo leeren (bei Job-Abbruch, Fahrzeug verloren)
-- ────────────────────────────────────────────────────────────

local function OnCargoClear()
    local source = source
    local id     = GetId(source)
    if not id then return end
    activeCargo[id] = nil
    SaveCargoToDB(id, nil)
end

-- ────────────────────────────────────────────────────────────
--  Admin: Item erstellen / bearbeiten
-- ────────────────────────────────────────────────────────────

local function OnAdminSaveItem(data)
    local source = source
    -- Admin-Check läuft bereits über admin.lua – hier nochmal absichern
    local id = GetId(source)
    if not id then return end

    -- Minimale Validierung
    if not data or not data.key or not data.label then
        TriggerClientEvent("mt:cargo:adminResult", source, { success = false, error = "Fehlende Felder." })
        return
    end

    local key = tostring(data.key):lower():gsub("[^a-z0-9_]", "")
    if #key < 2 then
        TriggerClientEvent("mt:cargo:adminResult", source, { success = false, error = "Key ungültig." })
        return
    end

    local itemData = {
        label        = tostring(data.label),
        icon         = tostring(data.icon or "📦"),
        category     = tostring(data.category or "industrie"),
        weight       = tonumber(data.weight) or 100,
        valuePerUnit = tonumber(data.valuePerUnit) or 100,
        perishable   = data.perishable and true or false,
        perishMin    = tonumber(data.perishMin) or 45,
        dangerous    = data.dangerous and true or false,
    }

    itemOverrides[key] = itemData

    MySQL.rawExecute(
        [[INSERT INTO mt_config (category, `key`, data, updated_by)
          VALUES ('item', ?, ?, ?)
          ON DUPLICATE KEY UPDATE data = VALUES(data), updated_by = VALUES(updated_by), deleted = 0]],
        { key, json.encode(itemData), id }
    )

    -- Alle Admins über neues Item informieren
    TriggerClientEvent("mt:cargo:adminResult", source, { success = true, action = "item_saved", key = key })
end

-- Admin: Delivery Point konfigurieren
local function OnAdminSaveDeliveryPoint(data)
    local source = source
    local id     = GetId(source)
    if not id or not data or not data.zone then return end

    local zone        = tostring(data.zone)
    local dpData      = {
        type          = data.type or "delivery",
        label         = tostring(data.label or zone),
        offeredItems  = data.offeredItems or {},
        acceptedItems = data.acceptedItems or {},
    }

    dpOverrides[zone] = dpData

    MySQL.rawExecute(
        [[INSERT INTO mt_config (category, `key`, data, updated_by)
          VALUES ('deliverypoint', ?, ?, ?)
          ON DUPLICATE KEY UPDATE data = VALUES(data), updated_by = VALUES(updated_by), deleted = 0]],
        { zone, json.encode(dpData), id }
    )

    TriggerClientEvent("mt:cargo:adminResult", source, { success = true, action = "dp_saved", zone = zone })
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API (für andere Module)
-- ────────────────────────────────────────────────────────────

-- Gibt das aktive Cargo eines Spielers zurück (für jobs.lua)
function CargoModule.GetCargo(identifier)
    return activeCargo[identifier]
end

-- Checkt ob Spieler irgendwas geladen hat
function CargoModule.HasCargo(identifier)
    local c = activeCargo[identifier]
    return c ~= nil and next(c.items) ~= nil
end

-- Gibt alle Items + aktuelle Config zurück (für Admin-NUI)
function CargoModule.GetAllItems()
    local result = {}
    -- Basis-Items
    if Config.Items then
        for key, cfg in pairs(Config.Items) do
            result[key]          = Utils.ShallowCopy and Utils.ShallowCopy(cfg) or cfg
            result[key].key      = key
            result[key].override = itemOverrides[key] ~= nil
        end
    end
    -- Overrides die in Config.Items nicht existieren
    for key, cfg in pairs(itemOverrides) do
        if not result[key] then
            result[key]          = Utils.ShallowCopy and Utils.ShallowCopy(cfg) or cfg
            result[key].key      = key
            result[key].override = true
        end
    end
    return result
end

-- Gibt alle Delivery Points zurück (für Admin-NUI)
function CargoModule.GetAllDeliveryPoints()
    local result = {}
    if Config.DeliveryPoints then
        for key, dp in pairs(Config.DeliveryPoints) do
            result[key] = { key = key, override = dpOverrides[key] ~= nil }
            local effective = dpOverrides[key] or dp
            for k, v in pairs(effective) do result[key][k] = v end
        end
    end
    for key, dp in pairs(dpOverrides) do
        if not result[key] then
            result[key] = { key = key, override = true }
            for k, v in pairs(dp) do result[key][k] = v end
        end
    end
    return result
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function CargoModule.Init()
    LoadOverrides(function()
        InitPickupStocks()
        LoadCargoDB(function()
            StartStockRefreshLoop()
            print("[MT] CargoModule initialisiert – " ..
                (Config.Items and tostring(#(function()
                    local n = 0; for _ in pairs(Config.Items) do n = n + 1 end; return { n }
                end)()[1]) or "0") ..
                " Items geladen")
        end)
    end)

    RegisterNetEvent("mt:cargo:requestPickup", OnRequestPickupItems)
    RegisterNetEvent("mt:cargo:load", OnCargoLoad)
    RegisterNetEvent("mt:cargo:requestDelivery", OnRequestDeliveryInfo)
    RegisterNetEvent("mt:cargo:unload", OnCargoUnload)
    RegisterNetEvent("mt:cargo:clear", OnCargoClear)
    RegisterNetEvent("mt:cargo:admin:saveItem", OnAdminSaveItem)
    RegisterNetEvent("mt:cargo:admin:saveDp", OnAdminSaveDeliveryPoint)

    -- Cargo löschen wenn Spieler disconnectet
    AddEventHandler("playerDropped", function()
        local src = source
        local id  = GetId(src)
        if id then
            -- Cargo BLEIBT in DB → Spieler kann nach Reconnect weitermachen
            activeCargo[id] = nil
        end
    end)
end

_CargoModule = CargoModule
