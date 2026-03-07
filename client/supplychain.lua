-- ============================================================
--  client/supplychain.lua
--  Zeigt Fabrikstatus-UI (ox_lib) und reagiert auf
--  Stock-Updates vom Server.
--
--  Andere Module können via Event den aktuellen Stock
--  einer Fabrik abfragen.
-- ============================================================

local SupplyChainModule = {}

-- Lokaler Cache der letzten bekannten Stocks
-- [factoryKey] = { inputStock, outputStock, label, ... }
local localStocks = {}

-- ────────────────────────────────────────────────────────────
--  Fabrik-Status UI (ox_lib alertDialog als Statusanzeige)
-- ────────────────────────────────────────────────────────────

local function ShowFactoryStatus(data)
    -- Progress-Balken als ASCII (ox_lib markdown)
    local function Bar(pct)
        local filled = math.floor((pct / 100) * 10)
        local empty  = 10 - filled
        return ("▓"):rep(filled) .. ("░"):rep(empty) .. (" %d%%"):format(pct)
    end

    -- Dringlichkeits-Farbe
    local inputColor  = data.inputPct < 20 and "🔴" or (data.inputPct < 50 and "🟡" or "🟢")
    local outputColor = data.outputPct < 20 and "🔴" or (data.outputPct < 50 and "🟡" or "🟢")

    lib.alertDialog({
        header   = ("🏭 %s"):format(data.label),
        content  = table.concat({
            ("**Input:**  %s `%s`  (%d/%d)"):format(
                inputColor, Bar(data.inputPct),
                data.inputStock, data.maxInput),
            ("**Output:** %s `%s`  (%d/%d)"):format(
                outputColor, Bar(data.outputPct),
                data.outputStock, data.maxOutput),
            "",
            ("_Angeliefert wird: **%s**_"):format(data.inputItem),
            ("_Produziert wird:  **%s**_"):format(data.outputItem),
        }, "\n"),
        centered = true,
    })
end

-- ────────────────────────────────────────────────────────────
--  Event Handler
-- ────────────────────────────────────────────────────────────

-- Server schickt Batch-Updates (Array von Änderungen)
local function OnSupplyUpdate(updates)
    if not updates then return end

    for _, update in ipairs(updates) do
        localStocks[update.key] = update

        -- Dringend-Warnung: leerer Stock meldet sich per Notify
        if update.urgent then
            lib.notify({
                title       = "⚠️ Lieferengpass",
                description = ("Fabrik '%s' hat keinen Output-Stock mehr! Lieferjobs verfügbar."):format(
                    update.label or update.key),
                type        = "warning",
                duration    = 10000,
            })
        end
    end

    -- HUD-Modul informieren (zeigt ggf. Fabrik-Indikator)
    TriggerEvent("mt:supply:localUpdate", localStocks)
end

-- Server antwortet auf Status-Request
local function OnFactoryStatus(data)
    if not data then return end
    localStocks[data.factoryKey] = data
    ShowFactoryStatus(data)
end

-- Spieler öffnet Fabrik-Menü via ox_target
local function OnOpenFactory(zoneName, zoneData)
    local factoryKey = zoneData and zoneData.factoryKey
    if not factoryKey then
        lib.notify({ title = "Keine Fabrik", type = "error" })
        return
    end
    -- Status beim Server anfragen
    TriggerServerEvent("mt:supply:statusRequest", factoryKey)
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.GetLocalStock(factoryKey)
    return localStocks[factoryKey]
end

function SupplyChainModule.GetAllLocalStocks()
    return localStocks
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function SupplyChainModule.Init()
    RegisterNetEvent(MT.SUPPLY_UPDATE, OnSupplyUpdate)
    RegisterNetEvent("mt:supply:factoryStatus", OnFactoryStatus)

    AddEventHandler("mt:supply:openFactory", OnOpenFactory)

    exports("GetLocalStock", SupplyChainModule.GetLocalStock)
    exports("GetAllLocalStocks", SupplyChainModule.GetAllLocalStocks)

    print("[MT] SupplyChainModule (Client) initialisiert")
end

_SupplyChainModule = SupplyChainModule
