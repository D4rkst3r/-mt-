-- ============================================================
--  client/supplychain.lua
--  Fabrikstatus via eigenem NUI-Panel (factory-panel).
--  Einzelne Fabrik-Zone öffnet Panel gefiltert auf diese Fabrik.
--  "Alle Fabriken"-Übersicht zeigt alle auf einmal.
-- ============================================================

local SupplyChainModule = {}

-- Lokaler Cache [factoryKey] = { inputStock, outputStock, ... }
local localStocks       = {}
local nuiOpen           = false

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktion: Prozent-Wert berechnen
-- ────────────────────────────────────────────────────────────

local function Pct(stock, max)
    if not max or max == 0 then return 0 end
    return math.floor((stock / max) * 100)
end

-- ────────────────────────────────────────────────────────────
--  NUI: alle Fabriken anzeigen
-- ────────────────────────────────────────────────────────────

local function BuildFactoryList(filterKey)
    local list = {}
    for key, cfg in pairs(Config.Factories or {}) do
        if not filterKey or key == filterKey then
            local s           = localStocks[key] or {}
            local inputStock  = s.inputStock or 0
            local outputStock = s.outputStock or 0
            local maxIn       = cfg.maxInputStock or 1
            local maxOut      = cfg.maxOutputStock or 1

            table.insert(list, {
                key         = key,
                label       = cfg.label,
                inputItem   = cfg.input and cfg.input.item or "?",
                outputItem  = cfg.output and cfg.output.item or "?",
                inputStock  = inputStock,
                outputStock = outputStock,
                maxInput    = maxIn,
                maxOutput   = maxOut,
                inputPct    = Pct(inputStock, maxIn),
                outputPct   = Pct(outputStock, maxOut),
            })
        end
    end
    -- Alphabetisch sortieren
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function OpenFactoryPanel(filterKey)
    SendNUIMessage({
        action    = "factoryOpen",
        factories = BuildFactoryList(filterKey),
    })
    SetNuiFocus(true, true)
    nuiOpen = true
end

local function CloseFactoryPanel()
    SendNUIMessage({ action = "factoryClose" })
    SetNuiFocus(false, false)
    nuiOpen = false
end

-- ────────────────────────────────────────────────────────────
--  NUI Callbacks
-- ────────────────────────────────────────────────────────────

RegisterNUICallback("factoryClose", function(_, cb)
    CloseFactoryPanel()
    cb("ok")
end)

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

-- Server schickt Batch-Updates (Array von Änderungen)
local function OnSupplyUpdate(updates)
    if not updates then return end

    for _, update in ipairs(updates) do
        localStocks[update.key] = update

        -- Dringend-Warnung
        if update.urgent then
            lib.notify({
                title       = "⚠️ Lieferengpass",
                description = ("**%s** hat keinen Output-Stock mehr! Neue Lieferjobs verfügbar."):format(
                    update.label or update.key),
                type        = "warning",
                duration    = 10000,
            })
        end

        -- Wenn Panel offen: Live-Update schicken
        if nuiOpen then
            local cfg = Config.Factories and Config.Factories[update.key]
            if cfg then
                SendNUIMessage({
                    action  = "factoryUpdate",
                    factory = {
                        key         = update.key,
                        inputStock  = update.inputStock or 0,
                        outputStock = update.outputStock or 0,
                        maxInput    = cfg.maxInputStock or 1,
                        maxOutput   = cfg.maxOutputStock or 1,
                        inputPct    = Pct(update.inputStock or 0, cfg.maxInputStock or 1),
                        outputPct   = Pct(update.outputStock or 0, cfg.maxOutputStock or 1),
                    },
                })
            end
        end
    end

    TriggerEvent("mt:supply:localUpdate", localStocks)
end

-- Server antwortet auf Status-Request einer einzelnen Fabrik
local function OnFactoryStatus(data)
    if not data then return end
    localStocks[data.factoryKey or data.key] = data
    -- Panel mit dieser Fabrik öffnen
    OpenFactoryPanel(data.factoryKey or data.key)
end

-- Zone-Target: Fabrik-Zone betreten → Status anfordern
local function OnOpenFactory(zoneName, zoneData)
    local factoryKey = zoneData and zoneData.factoryKey
    if not factoryKey then
        lib.notify({ title = "Keine Fabrik", type = "error" })
        return
    end
    -- Falls schon im Cache: sofort öffnen, dann beim Server aktualisieren
    if localStocks[factoryKey] then
        OpenFactoryPanel(factoryKey)
    end
    TriggerServerEvent("mt:supply:statusRequest", factoryKey)
end

-- Event für "Alle Fabriken" Übersicht (z.B. von einer Zentralzone)
local function OnOpenAllFactories()
    TriggerServerEvent("mt:supply:allStatusRequest")
end

-- Server schickt alle Fabriken auf einmal
local function OnAllFactoryStatus(dataList)
    if not dataList then return end
    for _, d in ipairs(dataList) do
        if d.key then localStocks[d.key] = d end
    end
    OpenFactoryPanel(nil) -- alle anzeigen
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
    RegisterNetEvent("mt:supply:stockUpdate", OnSupplyUpdate)
    RegisterNetEvent("mt:supply:factoryStatus", OnFactoryStatus)
    RegisterNetEvent("mt:supply:allStatus", OnAllFactoryStatus)

    AddEventHandler("mt:supply:openFactory", OnOpenFactory)
    AddEventHandler("mt:supply:openAll", OnOpenAllFactories)

    exports("GetLocalStock", SupplyChainModule.GetLocalStock)
    exports("GetAllLocalStocks", SupplyChainModule.GetAllLocalStocks)

    print("[MT] SupplyChainModule (Client) initialisiert")
end

_SupplyChainModule = SupplyChainModule
