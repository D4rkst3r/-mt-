-- ============================================================
--  server/supplychain.lua
--  Produktions-Loop, Stock-Management, Job-Generierung.
-- ============================================================

local SupplyChainModule = {}

-- Live-State: [factoryKey] = { inputStock, outputStock }
local stocks = {}

-- Produkions-Timer pro Fabrik: [factoryKey] = nächster Tick (os.time())
local nextProductionAt = {}

-- ────────────────────────────────────────────────────────────
--  DB: Laden & Speichern
-- ────────────────────────────────────────────────────────────

local function LoadStocks(cb)
    MySQL.query("SELECT * FROM mt_stocks", {}, function(rows)
        for key, _ in pairs(Config.Factories) do
            stocks[key] = { inputStock = 0, outputStock = 0 }
        end
        if rows then
            for _, row in ipairs(rows) do
                if stocks[row.factory_key] then
                    stocks[row.factory_key] = {
                        inputStock  = row.input_stock,
                        outputStock = row.output_stock,
                    }
                end
            end
        end
        -- Produktionszeitpunkte initialisieren
        local now = os.time()
        for key, factory in pairs(Config.Factories) do
            nextProductionAt[key] = now + (factory.productionTime or 300)
        end
        if cb then cb() end
    end)
end

local function SaveStocks()
    for factoryKey, stock in pairs(stocks) do
        MySQL.rawExecute(
            [[INSERT INTO mt_stocks (factory_key, input_stock, output_stock)
              VALUES (?, ?, ?)
              ON DUPLICATE KEY UPDATE
                input_stock  = VALUES(input_stock),
                output_stock = VALUES(output_stock)]],
            { factoryKey, stock.inputStock, stock.outputStock }
        )
    end
end

-- ────────────────────────────────────────────────────────────
--  BUG 1 FIX: SetInterval existiert nicht in FiveM
--  → eigene Loops mit CreateThread + Wait
-- ────────────────────────────────────────────────────────────

-- BUG 4 FIX: Produktionszeit kommt aus factory.productionTime (pro Fabrik),
-- nicht aus einem globalen Tick
local function StartProductionLoop()
    CreateThread(function()
        while true do
            Wait(10000) -- alle 10 Sek prüfen ob eine Fabrik dran ist
            local now     = os.time()
            local updates = {}

            for factoryKey, factory in pairs(Config.Factories) do
                local stock = stocks[factoryKey]
                if not stock then goto continue end

                -- Ist diese Fabrik dran?
                if now < (nextProductionAt[factoryKey] or 0) then goto continue end

                -- Nächsten Tick vorplanen (egal ob Produktion klappt)
                nextProductionAt[factoryKey] = now + (factory.productionTime or 300)

                -- Genug Input?
                if stock.inputStock >= factory.input.amount then
                    if stock.outputStock < factory.maxOutputStock then
                        stock.inputStock  = stock.inputStock - factory.input.amount
                        stock.outputStock = math.min(
                            stock.outputStock + factory.output.amount,
                            factory.maxOutputStock
                        )

                        table.insert(updates, {
                            key         = factoryKey,
                            label       = factory.label,
                            inputStock  = stock.inputStock,
                            outputStock = stock.outputStock,
                        })

                        -- Kraftwerk-Sondereffekt
                        if factory.townBonusEffect and _TownBonusModule then
                            _TownBonusModule.BoostAll(factory.townBonusEffect)
                        end

                        print(("[MT][Supply] %s produziert → Input: %d, Output: %d"):format(
                            factory.label, stock.inputStock, stock.outputStock))
                    end
                end

                -- Liefer-Job generieren wenn Output über Schwellwert
                if stock.outputStock >= factory.deliveryThreshold then
                    TriggerEvent(MT.SUPPLY_JOB_GENERATED, factoryKey, factory)
                end

                ::continue::
            end

            if #updates > 0 then
                TriggerClientEvent("mt:supply:stockUpdate", -1, updates)
                SaveStocks()
            end
        end
    end)
end

local function StartConsumerLoop()
    CreateThread(function()
        while true do
            Wait(Config.ConsumerTickMs or 600000) -- default 10 Min

            for _, consumer in ipairs(Config.Consumers) do
                local stock = stocks[consumer.factoryKey]
                if stock then
                    local before = stock.outputStock
                    stock.outputStock = math.max(0, stock.outputStock - consumer.rate)

                    if before > 0 and stock.outputStock == 0 then
                        print(("[MT][Supply] %s – %s-Stock erschöpft!"):format(
                            consumer.label, consumer.item))
                        TriggerClientEvent("mt:supply:stockUpdate", -1, { {
                            key         = consumer.factoryKey,
                            label       = consumer.label,
                            urgent      = true,
                            inputStock  = stock.inputStock,
                            outputStock = stock.outputStock,
                        } })
                    end
                end
            end

            SaveStocks()
        end
    end)
end

local function StartSaveLoop()
    CreateThread(function()
        while true do
            Wait(2 * 60 * 1000)
            SaveStocks()
        end
    end)
end

-- ────────────────────────────────────────────────────────────
--  Job-Abschluss: Input-Stock einer Fabrik erhöhen
--
--  BUG 3 FIX: MT.SUPPLY_UPDATE war für zwei Dinge zuständig:
--  - Server-lokal: OnDeliveryComplete (jobs.lua → supplychain.lua)
--  - Client-Broadcast: Stock-Updates an alle Spieler
--  Das ist ein Name-Conflict. Lösung:
--  - Server-intern: MT.SUPPLY_DELIVERY (neues Event)
--  - Client-Broadcast: "mt:supply:stockUpdate" (eigener Name)
-- ────────────────────────────────────────────────────────────

local function OnDeliveryComplete(jobKey, deliveryZone)
    for factoryKey, factory in pairs(Config.Factories) do
        if factory.deliveryJobKey == jobKey then
            local stock = stocks[factoryKey]
            if stock then
                local added = math.min(
                    factory.input.amount,
                    factory.maxInputStock - stock.inputStock
                )
                if added > 0 then
                    stock.inputStock = stock.inputStock + added
                    print(("[MT][Supply] %s: Input +%d (jetzt: %d)"):format(
                        factory.label, added, stock.inputStock))
                    TriggerClientEvent("mt:supply:stockUpdate", -1, { {
                        key         = factoryKey,
                        label       = factory.label,
                        inputStock  = stock.inputStock,
                        outputStock = stock.outputStock,
                    } })
                    SaveStocks()
                end
            end
            break
        end
    end
end

-- ────────────────────────────────────────────────────────────
--  BUG 2 FIX: NetEvent-Handler bekommen KEIN source-Parameter
--  → source wird über die globale Variable `source` gelesen
-- ────────────────────────────────────────────────────────────

local function OnFactoryStatusRequest(factoryKey)
    local src     = source
    local factory = Config.Factories[factoryKey]
    local stock   = stocks[factoryKey]
    if not factory or not stock then return end

    TriggerClientEvent("mt:supply:factoryStatus", src, {
        factoryKey  = factoryKey,
        label       = factory.label,
        inputItem   = factory.input.item,
        outputItem  = factory.output.item,
        inputStock  = stock.inputStock,
        outputStock = stock.outputStock,
        maxInput    = factory.maxInputStock,
        maxOutput   = factory.maxOutputStock,
        inputPct    = Utils.Round(stock.inputStock / factory.maxInputStock * 100, 0),
        outputPct   = Utils.Round(stock.outputStock / factory.maxOutputStock * 100, 0),
    })
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.GetStock(factoryKey) return stocks[factoryKey] end

function SupplyChainModule.GetAllStocks() return stocks end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.Init()
    LoadStocks(function()
        print("[MT][Supply] Stocks geladen:")
        for key, s in pairs(stocks) do
            print(("  %s – Input: %d, Output: %d"):format(key, s.inputStock, s.outputStock))
        end
        StartProductionLoop()
        StartConsumerLoop()
        StartSaveLoop()
    end)

    -- BUG 3 FIX: eigenes internes Event statt MT.SUPPLY_UPDATE
    AddEventHandler("mt:supply:deliveryComplete", OnDeliveryComplete)

    RegisterNetEvent("mt:supply:statusRequest", OnFactoryStatusRequest)

    -- Alle Fabriken auf einmal senden (für Übersichts-Panel)
    RegisterNetEvent("mt:supply:allStatusRequest", function()
        local src  = source
        local list = {}
        for key, factory in pairs(Config.Factories) do
            local stock = stocks[key]
            if stock then
                table.insert(list, {
                    key         = key,
                    label       = factory.label,
                    inputItem   = factory.input.item,
                    outputItem  = factory.output.item,
                    inputStock  = stock.inputStock,
                    outputStock = stock.outputStock,
                    maxInput    = factory.maxInputStock,
                    maxOutput   = factory.maxOutputStock,
                    inputPct    = Utils.Round(stock.inputStock / factory.maxInputStock * 100, 0),
                    outputPct   = Utils.Round(stock.outputStock / factory.maxOutputStock * 100, 0),
                })
            end
        end
        TriggerClientEvent("mt:supply:allStatus", src, list)
    end)

    exports("GetStock", SupplyChainModule.GetStock)
    exports("GetAllStocks", SupplyChainModule.GetAllStocks)

    print("[MT] SupplyChainModule (Server) initialisiert")
end

_SupplyChainModule = SupplyChainModule
