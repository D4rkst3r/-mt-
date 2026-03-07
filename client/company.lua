-- ============================================================
--  client/company.lua
--  Vollständige Company-UI via ox_lib context menus.
--  Öffnet sich über die company_buero Zone.
--
--  Menü-Baum:
--  Haupt-Menü
--  ├── Übersicht (Kontostand, Reputation, Mitglieder)
--  ├── Mitglieder verwalten  [manager+]
--  │   ├── Einladen
--  │   └── Entlassen
--  ├── Routen verwalten      [manager+]
--  │   ├── Route erstellen
--  │   └── Route pausieren/aktivieren
--  ├── Kasse                 [owner]
--  │   ├── Einzahlen
--  │   └── Auszahlen
--  └── Firma gründen (wenn kein Mitglied)
-- ============================================================

local CompanyModule = {}

-- Lokaler State: wird beim Öffnen des Menüs vom Server geholt
local companyData = nil -- { company, membership, members, routes }

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktionen
-- ────────────────────────────────────────────────────────────

local function RoleLabel(role)
    local labels = { owner = "👑 Owner", manager = "🔑 Manager", driver = "🚛 Fahrer" }
    return labels[role] or role
end

local function RouteStatus(active)
    return active == 1 and "🟢 Aktiv" or "🔴 Pausiert"
end

-- ────────────────────────────────────────────────────────────
--  Menü: Firma gründen
-- ────────────────────────────────────────────────────────────

local function OpenFoundMenu()
    local input = lib.inputDialog("Firma gründen", {
        {
            type        = "input",
            label       = "Firmenname",
            description = "Mindestens 3 Zeichen, einzigartig.",
            required    = true,
            min         = 3,
            max         = 40,
        },
    })

    if not input or not input[1] then return end

    local confirmed = lib.alertDialog({
        header   = "Firma gründen",
        content  = ("Name: **%s**\nGründungskosten: **%s**\n\nDieser Betrag wird sofort von deinem Konto abgebucht.")
        :format(
            input[1], Utils.FormatMoney(50000)),
        centered = true,
        cancel   = true,
    })

    if confirmed ~= "confirm" then return end

    TriggerServerEvent("mt:company:found", { name = input[1] })
end

-- ────────────────────────────────────────────────────────────
--  Menü: Mitglieder verwalten
-- ────────────────────────────────────────────────────────────

local function OpenMembersMenu()
    if not companyData then return end

    local options = {}

    -- Mitglieder auflisten
    for _, member in ipairs(companyData.members) do
        local playerData = exports["motortown"]:GetPlayerData()
        local isSelf     = playerData and (member.identifier == playerData.identifier)

        table.insert(options, {
            title       = ("%s  %s"):format(RoleLabel(member.role), member.name or "Unbekannt"),
            description = member.identifier,
            disabled    = member.role == "owner", -- Owner kann nicht entlassen werden
            onSelect    = (companyData.membership.role ~= "driver"
                and member.role ~= "owner") and function()
                -- Aktions-Untermenü für diesen Member
                lib.registerContext({
                    id      = "mt_member_action",
                    title   = member.name or member.identifier,
                    menu    = "mt_members",
                    options = {
                        {
                            title    = "Entlassen",
                            icon     = "fas fa-user-times",
                            onSelect = function()
                                local confirmed = lib.alertDialog({
                                    header   = "Mitglied entlassen",
                                    content  = ("**%s** wirklich entlassen?"):format(
                                        member.name or member.identifier),
                                    centered = true,
                                    cancel   = true,
                                })
                                if confirmed == "confirm" then
                                    TriggerServerEvent(MT.COMPANY_MEMBER_KICK, {
                                        targetIdentifier = member.identifier
                                    })
                                end
                            end,
                        },
                    },
                })
                lib.showContext("mt_member_action")
            end or nil,
        })
    end

    -- Einladen-Option
    if companyData.membership.role ~= "driver" then
        table.insert(options, {
            title    = "➕ Spieler einladen",
            icon     = "fas fa-user-plus",
            onSelect = function()
                local input = lib.inputDialog("Spieler einladen", {
                    {
                        type     = "input",
                        label    = "License-Identifier des Spielers",
                        required = true,
                    },
                })
                if not input or not input[1] then return end
                TriggerServerEvent(MT.COMPANY_MEMBER_ADD, {
                    targetIdentifier = input[1]
                })
            end,
        })
    end

    lib.registerContext({
        id      = "mt_members",
        title   = "👥 Mitglieder",
        menu    = "mt_company",
        options = options,
    })
    lib.showContext("mt_members")
end

-- ────────────────────────────────────────────────────────────
--  Menü: Routen verwalten
-- ────────────────────────────────────────────────────────────

local function OpenRoutesMenu()
    if not companyData then return end

    local options = {}

    -- Bestehende Routen
    for _, route in ipairs(companyData.routes) do
        local jobCfg  = Config.Jobs[route.route_type]
        local label   = jobCfg and jobCfg.label or route.route_type
        local vehicle = route.plate and
            ("%s (%s)"):format(route.model or "?", route.plate) or "Kein Fahrzeug"

        table.insert(options, {
            title       = ("%s  %s"):format(RouteStatus(route.active), label),
            description = ("Fahrzeug: %s"):format(vehicle),
            onSelect    = function()
                -- Pausieren / Aktivieren
                lib.registerContext({
                    id      = "mt_route_action",
                    title   = label,
                    menu    = "mt_routes",
                    options = {
                        {
                            title    = route.active == 1 and "⏸ Pausieren" or "▶ Aktivieren",
                            onSelect = function()
                                TriggerServerEvent("mt:company:routeToggle", {
                                    routeId = route.id
                                })
                            end,
                        },
                    },
                })
                lib.showContext("mt_route_action")
            end,
        })
    end

    -- Neue Route erstellen
    if companyData.membership.role ~= "driver" then
        -- Job-Typ Optionen bauen
        local jobOptions = {}
        for jobKey, jobCfg in pairs(Config.Jobs) do
            table.insert(jobOptions, { value = jobKey, label = jobCfg.label })
        end

        table.insert(options, {
            title    = "➕ Neue Route erstellen",
            icon     = "fas fa-route",
            onSelect = function()
                local input = lib.inputDialog("Route erstellen", {
                    {
                        type    = "select",
                        label   = "Job-Typ",
                        options = jobOptions,
                    },
                    {
                        type        = "input",
                        label       = "Fahrzeug-ID (aus deiner Garage)",
                        description = "Numerische ID aus der Fahrzeugverwaltung.",
                        required    = true,
                    },
                })

                if not input or not input[1] or not input[2] then return end

                TriggerServerEvent("mt:company:routeCreate", {
                    routeType = input[1],
                    vehicleId = tonumber(input[2]),
                })
            end,
        })
    end

    if #options == 0 then
        table.insert(options, {
            title    = "Keine Routen vorhanden",
            disabled = true,
        })
    end

    lib.registerContext({
        id      = "mt_routes",
        title   = "🗺 Routen",
        menu    = "mt_company",
        options = options,
    })
    lib.showContext("mt_routes")
end

-- ────────────────────────────────────────────────────────────
--  Menü: Kasse (Owner only)
-- ────────────────────────────────────────────────────────────

local function OpenFinanceMenu()
    if not companyData then return end
    if companyData.membership.role ~= "owner" then
        lib.notify({ title = "Kein Zugriff", type = "error" })
        return
    end

    lib.registerContext({
        id      = "mt_finance",
        title   = ("💰 Kasse – %s"):format(
            Utils.FormatMoney(companyData.company.balance)),
        menu    = "mt_company",
        options = {
            {
                title       = "💵 Einzahlen",
                description = ("Dein Geld: %s"):format(
                    Utils.FormatMoney(exports["motortown"]:GetMoney())),
                onSelect    = function()
                    local input = lib.inputDialog("Einzahlen", {
                        { type = "number", label = "Betrag ($)", required = true, min = 1 }
                    })
                    if input and input[1] then
                        TriggerServerEvent("mt:company:deposit", { amount = input[1] })
                    end
                end,
            },
            {
                title       = "🏦 Auszahlen",
                description = ("Firmenkontostand: %s"):format(
                    Utils.FormatMoney(companyData.company.balance)),
                onSelect    = function()
                    local input = lib.inputDialog("Auszahlen", {
                        { type = "number", label = "Betrag ($)", required = true, min = 1 }
                    })
                    if input and input[1] then
                        TriggerServerEvent("mt:company:withdraw", { amount = input[1] })
                    end
                end,
            },
        },
    })
    lib.showContext("mt_finance")
end

-- ────────────────────────────────────────────────────────────
--  Haupt-Menü (nach Daten-Empfang vom Server aufgebaut)
-- ────────────────────────────────────────────────────────────

local function BuildMainMenu()
    if not companyData then return end

    -- Kein Mitglied: nur Gründen anzeigen
    if not companyData.membership then
        lib.registerContext({
            id      = "mt_company",
            title   = "🏢 Firmen-Verwaltung",
            options = {
                {
                    title       = "Neue Firma gründen",
                    description = ("Kosten: %s"):format(Utils.FormatMoney(50000)),
                    icon        = "fas fa-building",
                    onSelect    = OpenFoundMenu,
                },
                {
                    title    = "Kein Mitglied einer Firma",
                    disabled = true,
                },
            },
        })
        lib.showContext("mt_company")
        return
    end

    local c            = companyData.company
    local mem          = companyData.membership

    -- Statistik-Zeilen
    local activeRoutes = 0
    for _, r in ipairs(companyData.routes) do
        if r.active == 1 then activeRoutes = activeRoutes + 1 end
    end

    local options = {
        -- Übersicht (nicht klickbar, reine Info)
        {
            title       = ("📊 %s"):format(c.name),
            description = table.concat({
                ("Kontostand:  **%s**"):format(Utils.FormatMoney(c.balance)),
                ("Mitglieder:  **%d**"):format(#companyData.members),
                ("Aktive Routen: **%d**"):format(activeRoutes),
                ("Deine Rolle: **%s**"):format(RoleLabel(mem.role)),
            }, "\n"),
            disabled    = true,
        },
    }

    -- Mitglieder (Manager/Owner)
    if mem.role ~= "driver" then
        table.insert(options, {
            title    = "👥 Mitglieder verwalten",
            arrow    = true,
            icon     = "fas fa-users",
            onSelect = OpenMembersMenu,
        })
    end

    -- Routen (Manager/Owner)
    if mem.role ~= "driver" then
        table.insert(options, {
            title    = "🗺 Routen verwalten",
            arrow    = true,
            icon     = "fas fa-route",
            onSelect = OpenRoutesMenu,
        })
    end

    -- Routen-Ansicht für alle (read-only)
    if mem.role == "driver" then
        table.insert(options, {
            title       = ("🗺 Routen (%d aktiv)"):format(activeRoutes),
            description = "Nur Manager können Routen verwalten.",
            disabled    = true,
        })
    end

    -- Kasse (Owner only)
    if mem.role == "owner" then
        table.insert(options, {
            title    = "💰 Kasse",
            arrow    = true,
            icon     = "fas fa-coins",
            onSelect = OpenFinanceMenu,
        })
    end

    lib.registerContext({
        id      = "mt_company",
        title   = "🏢 Firmen-Verwaltung",
        options = options,
    })
    lib.showContext("mt_company")
end

-- ────────────────────────────────────────────────────────────
--  Event Handler (Server → Client)
-- ────────────────────────────────────────────────────────────

local function OnCompanyData(data)
    companyData = data
    BuildMainMenu()
end

local function OnCompanyResult(data)
    if not data.success then
        lib.notify({ title = "Fehler", description = data.error, type = "error" })
        return
    end

    local messages = {
        invited      = "✅ Spieler eingeladen.",
        kicked       = "✅ Mitglied entlassen.",
        routeCreated = "✅ Route erstellt.",
        routeToggled = "✅ Routen-Status geändert.",
        deposit      = ("✅ %s eingezahlt."):format(Utils.FormatMoney(data.amount or 0)),
        withdraw     = ("✅ %s ausgezahlt."):format(Utils.FormatMoney(data.amount or 0)),
    }

    if data.companyId then
        -- Firma gegründet
        lib.notify({
            title       = "🏢 Firma gegründet!",
            description = ("**%s** ist jetzt registriert."):format(data.name),
            type        = "success",
            duration    = 8000,
        })
        return
    end

    lib.notify({
        title = messages[data.action] or "Aktion ausgeführt",
        type  = "success",
    })

    -- Menü nach Aktion neu laden
    TriggerServerEvent("mt:company:dataRequest")
end

-- NPC-Routen Auszahlung empfangen
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

    -- Lokalen Balance-Cache updaten
    if companyData and companyData.company then
        companyData.company.balance = math.max(0,
            companyData.company.balance + (data.delta or 0))
    end
end

-- Balance-Update (nach Einzahlung durch anderen Member)
local function OnBalanceUpdate(data)
    if companyData and companyData.company then
        companyData.company.balance = data.balance
    end
end

-- Eingeladen / Rausgeworfen
local function OnMemberAdded(data)
    lib.notify({
        title       = "🏢 Firma beigetreten",
        description = ("Du bist jetzt **%s** einer Firma."):format(RoleLabel(data.role)),
        type        = "success",
        duration    = 8000,
    })
end

local function OnMemberKicked()
    companyData = nil
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

    -- Zone-Target: Büro öffnen
    AddEventHandler("mt:ui:openCompany", function()
        TriggerServerEvent("mt:company:dataRequest")
    end)

    print("[MT] CompanyModule (Client) initialisiert")
end

_CompanyModule = CompanyModule
