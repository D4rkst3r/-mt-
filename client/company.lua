-- ============================================================
--  client/company.lua
--  Company-UI vollständig via eigenem NUI-Panel.
--  Öffnet sich über die company_buero Zone.
-- ============================================================

local CompanyModule = {}

local companyData   = nil
local nuiOpen       = false

-- ────────────────────────────────────────────────────────────
--  NUI öffnen / schließen
-- ────────────────────────────────────────────────────────────

local function OpenNUI(data)
    companyData = data

    -- Job-Liste für Route-Dropdown aufbauen
    local jobs = {}
    for k, v in pairs(Config.Jobs or {}) do
        table.insert(jobs, { key = k, label = v.label or k })
    end
    table.sort(jobs, function(a, b) return a.label < b.label end)

    -- Routen mit Job-Label anreichern
    local routes = {}
    for _, r in ipairs(data.routes or {}) do
        local jobCfg = Config.Jobs[r.route_type]
        table.insert(routes, {
            id         = r.id,
            route_type = r.route_type,
            jobLabel   = jobCfg and jobCfg.label or r.route_type,
            plate      = r.plate,
            model      = r.model,
            active     = r.active,
        })
    end

    SendNUIMessage({
        action = "companyOpen",
        data   = {
            company    = data.company,
            membership = data.membership,
            members    = data.members or {},
            routes     = routes,
            jobs       = jobs,
        },
    })

    SetNuiFocus(true, true)
    nuiOpen = true
end

local function CloseNUI()
    SendNUIMessage({ action = "companyClose" })
    SetNuiFocus(false, false)
    nuiOpen = false
end

-- ────────────────────────────────────────────────────────────
--  NUI Callbacks
-- ────────────────────────────────────────────────────────────

RegisterNUICallback("companyClose", function(_, cb)
    CloseNUI()
    cb("ok")
end)

RegisterNUICallback("companyAction", function(data, cb)
    if not data or not data.action then
        cb("err")
        return
    end

    if data.action == "found" then
        if not data.name or data.name == "" then
            cb("err")
            return
        end
        TriggerServerEvent("mt:company:found", { name = data.name })
    elseif data.action == "kick" then
        TriggerServerEvent("mt:company:kick", { identifier = data.identifier })
    elseif data.action == "promote" then
        TriggerServerEvent("mt:company:promote", { identifier = data.identifier })
    elseif data.action == "toggle_route" then
        TriggerServerEvent("mt:company:routeToggle", { routeId = data.routeId })
    elseif data.action == "create_route" then
        TriggerServerEvent("mt:company:routeCreate", {
            routeType = data.routeType,
            vehicleId = data.vehicleId,
        })
    elseif data.action == "deposit" then
        TriggerServerEvent("mt:company:deposit", { amount = data.amount })
    elseif data.action == "withdraw" then
        TriggerServerEvent("mt:company:withdraw", { amount = data.amount })
    end

    cb("ok")
end)

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

local function OnCompanyData(data)
    companyData = data
    OpenNUI(data)
end

local function OnCompanyResult(data)
    if not data.success then
        lib.notify({ title = "Fehler", description = data.error, type = "error" })
        return
    end

    local messages = {
        kicked       = "Mitglied entlassen.",
        promoted     = "Mitglied befördert.",
        routeCreated = "Route erstellt.",
        routeToggled = "Routen-Status geändert.",
        deposit      = ("Eingezahlt: %s"):format(Utils.FormatMoney(data.amount or 0)),
        withdraw     = ("Ausgezahlt: %s"):format(Utils.FormatMoney(data.amount or 0)),
    }

    if data.companyId then
        lib.notify({
            title       = "🏢 Firma gegründet!",
            description = ("**%s** ist jetzt registriert."):format(data.name),
            type        = "success",
            duration    = 8000,
        })
        -- Daten neu laden damit Panel sich aktualisiert
        TriggerServerEvent("mt:company:dataRequest")
        return
    end

    lib.notify({
        title = "✅ " .. (messages[data.action] or "Aktion ausgeführt"),
        type  = "success",
    })

    -- Panel-Daten neu laden (aktualisiert geöffnetes Panel)
    TriggerServerEvent("mt:company:dataRequest")
end

local function OnCompanyPayout(data)
    if data.net and data.net > 0 then
        lib.notify({
            title       = "🚛 Routen-Einnahmen",
            description = ("Firma erhielt **+%s** aus aktiven Routen."):format(
                Utils.FormatMoney(data.net)),
            type        = "inform",
            duration    = 6000,
        })
    end
    if companyData and companyData.company then
        companyData.company.balance = math.max(0,
            companyData.company.balance + (data.delta or 0))
    end
end

local function OnBalanceUpdate(data)
    if companyData and companyData.company then
        companyData.company.balance = data.balance
    end
    -- Live-Update im offenen Panel ohne alles neu zu laden
    if nuiOpen then
        SendNUIMessage({ action = "companyBalance", balance = data.balance })
    end
end

local function OnMemberAdded(data)
    lib.notify({
        title       = "🏢 Firma beigetreten",
        description = "Du bist jetzt Mitglied einer Firma.",
        type        = "success",
        duration    = 8000,
    })
end

local function OnMemberKicked()
    companyData = nil
    if nuiOpen then CloseNUI() end
    lib.notify({
        title       = "❌ Entlassen",
        description = "Du wurdest aus der Firma entlassen.",
        type        = "error",
        duration    = 8000,
    })
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function CompanyModule.Init()
    RegisterNetEvent("mt:company:data", OnCompanyData)
    RegisterNetEvent("mt:company:result", OnCompanyResult)
    RegisterNetEvent(MT.COMPANY_PAYOUT, OnCompanyPayout)
    RegisterNetEvent(MT.COMPANY_BALANCE_UPDATE, OnBalanceUpdate)
    RegisterNetEvent(MT.COMPANY_MEMBER_ADD, OnMemberAdded)
    RegisterNetEvent(MT.COMPANY_MEMBER_KICK, OnMemberKicked)

    AddEventHandler("mt:ui:openCompany", function()
        TriggerServerEvent("mt:company:dataRequest")
    end)

    print("[MT] CompanyModule (Client) initialisiert")
end

_CompanyModule = CompanyModule
