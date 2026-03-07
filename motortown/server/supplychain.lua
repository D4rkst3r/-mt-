-- ============================================================
--  server/supplychain.lua
--  Produktions-Loop, Stock-Management, Job-Generierung.
--
--  State lebt in Memory (stocks-Table) und wird periodisch
--  in mt_stocks persistiert. Beim Start wird aus DB geladen.
-- ============================================================

local SupplyChainModule = {}

-- Live-State: [factoryKey] = { inputStock, outputStock }
local stocks = {}

-- ────────────────────────────────────────────────────────────
--  DB: Laden & Speichern
-- ────────────────────────────────────────────────────────────

local function LoadStocks(cb)
    MySQL.query("SELECT * FROM mt_stocks", {}, function(rows)
        -- Erst alle Fabriken mit 0 initialisieren
        for key, _ in pairs(Config.Factories) do
            stocks[key] = { inputStock = 0, outputStock = 0 }
        end
        -- Dann DB-Werte überschreiben
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
        if cb then cb() end
    end)
end

local function SaveStocks()
    for factoryKey, stock in pairs(stocks) do
        MySQL.update(
            [[INSERT INTO mt_stocks (factory_key, input_stock, output_stock)
              VALUES (?, ?, ?)
              ON DUPLICATE KEY UPDATE
                input_stock = VALUES(input_stock),
                output_stock = VALUES(output_stock)]],
            { factoryKey, stock.inputStock, stock.outputStock }
        )
    end
end

-- ────────────────────────────────────────────────────────────
--  Produktions-Tick (alle 5 Min)
-- ────────────────────────────────────────────────────────────

local function RunProductionTick()
    local updates = {}

    for factoryKey, factory in pairs(Config.Factories) do
        local stock = stocks[factoryKey]
        if not stock then goto continue end

        -- Genug Input vorhanden?
        if stock.inputStock >= factory.input.amount then
            -- Output-Cap prüfen
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

                -- Kraftwerk-Sondereffekt: Town Bonus anheben
                if factory.townBonusEffect and _TownBonusModule then
                    _TownBonusModule.BoostAll(factory.townBonusEffect)
                end

                print(("[MT][Supply] %s produziert: Input %d → Output %d"):format(
                    factory.label, stock.inputStock, stock.outputStock
                ))
            end
        end

        -- Neuen Liefer-Job generieren wenn Output-Stock über Schwellwert
        if stock.outputStock >= factory.deliveryThreshold then
            TriggerEvent(MT.SUPPLY_JOB_GENERATED, factoryKey, factory)
        end

        ::continue::
    end

    -- Clients über Stockänderungen informieren
    if #updates > 0 then
        TriggerClientEvent(MT.SUPPLY_UPDATE, -1, updates)
    end

    SaveStocks()
end

-- ────────────────────────────────────────────────────────────
--  Verbraucher-Tick (alle 10 Min)
-- ────────────────────────────────────────────────────────────

local function RunConsumerTick()
    for _, consumer in ipairs(Config.Consumers) do
        local stock = stocks[consumer.factoryKey]
        if stock then
            local before = stock.outputStock
            stock.outputStock = math.max(0, stock.outputStock - consumer.rate)

            if before > 0 and stock.outputStock == 0 then
                -- Stock leergelaufen → dringende Benachrichtigung
                print(("[MT][Supply] WARNUNG: %s – %s-Stock erschöpft!"):format(
                    consumer.label, consumer.item
                ))
                TriggerClientEvent(MT.SUPPLY_UPDATE, -1, {
                    {
                        key = consumer.factoryKey,
                        urgent = true,
                        inputStock  = stock.inputStock,
                        outputStock = stock.outputStock
                    }
                })
            end
        end
    end
    SaveStocks()
end

-- ────────────────────────────────────────────────────────────
--  Job-Abschluss: Input-Stock einer Fabrik erhöhen
--  Wird über MT.SUPPLY_UPDATE Event vom jobs.lua getriggert
-- ────────────────────────────────────────────────────────────

local function OnDeliveryComplete(jobKey, deliveryZone)
    -- Finde Fabrik die diesen jobKey als deliveryJobKey hat
    -- UND deren Zone mit deliveryZone übereinstimmt
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
                        factory.label, added, stock.inputStock
                    ))
                    -- Sofort an alle Clients broadcasten
                    TriggerClientEvent(MT.SUPPLY_UPDATE, -1, {
                        {
                            key         = factoryKey,
                            label       = factory.label,
                            inputStock  = stock.inputStock,
                            outputStock = stock.outputStock
                        }
                    })
                end
            end
            break
        end
    end
end

-- ────────────────────────────────────────────────────────────
--  Client fragt Fabrikstatus an (für UI)
-- ────────────────────────────────────────────────────────────

local function OnFactoryStatusRequest(source, factoryKey)
    local factory = Config.Factories[factoryKey]
    local stock   = stocks[factoryKey]
    if not factory or not stock then return end

    TriggerClientEvent("mt:supply:factoryStatus", source, {
        factoryKey  = factoryKey,
        label       = factory.label,
        inputItem   = factory.input.item,
        outputItem  = factory.output.item,
        inputStock  = stock.inputStock,
        outputStock = stock.outputStock,
        maxInput    = factory.maxInputStock,
        maxOutput   = factory.maxOutputStock,
        -- Prozentsätze für UI-Progress-Bars
        inputPct    = Utils.Round(stock.inputStock / factory.maxInputStock * 100, 0),
        outputPct   = Utils.Round(stock.outputStock / factory.maxOutputStock * 100, 0),
    })
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.GetStock(factoryKey)
    return stocks[factoryKey]
end

function SupplyChainModule.GetAllStocks()
    return stocks
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.Init()
    -- Stocks aus DB laden, dann Loops starten
    LoadStocks(function()
        print("[MT][Supply] Stocks geladen:")
        for key, s in pairs(stocks) do
            print(("  %s – Input: %d, Output: %d"):format(key, s.inputStock, s.outputStock))
        end

        -- Produktions-Loop
        lib.setInterval(RunProductionTick, Config.ProductionTickMs)

        -- Verbraucher-Loop
        lib.setInterval(RunConsumerTick, Config.ConsumerTickMs)

        -- Periodisches Speichern (alle 2 Min extra)
        lib.setInterval(SaveStocks, 2 * 60 * 1000)
    end)

    -- Event-Listener
    AddEventHandler(MT.SUPPLY_UPDATE, OnDeliveryComplete)

    RegisterNetEvent("mt:supply:statusRequest", OnFactoryStatusRequest)

    exports("GetStock", SupplyChainModule.GetStock)
    exports("GetAllStocks", SupplyChainModule.GetAllStocks)

    print("[MT] SupplyChainModule (Server) initialisiert")
end

_SupplyChainModule = SupplyChainModule
