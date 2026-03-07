-- ============================================================
--  server/company.lua
--  Firmen-CRUD, Mitgliederverwaltung, NPC-Routen-Simulation.
--
--  NPC-Routen: Es gibt keine echten Fahrzeuge/NPCs.
--  Stattdessen berechnet ein Server-Loop alle 30 Min
--  für jede aktive Route einen Auszahlungsbetrag und
--  bucht ihn ins Company-Konto. Das simuliert Einnahmen
--  als ob NPC-Fahrer unterwegs wären.
-- ============================================================

local CompanyModule    = {}

-- Memory-Cache: [companyId] = companyData
-- Wird beim ersten Zugriff aus DB geladen, danach gehalten
local companyCache     = {}

-- Member-Cache: [identifier] = { companyId, role }
-- Schneller Lookup ohne DB-Abfrage bei jedem Event
local memberCache      = {}

-- Konstanten
local FOUND_COST       = 50000          -- Gründungskosten
local ROUTE_PAYOUT_MIN = 800            -- Minimaler Strecken-Auszahlungs pro Tick
local ROUTE_PAYOUT_MAX = 2500           -- Maximum
local ROUTE_MAINT_COST = 300            -- Wartungskosten pro Route pro Tick
local ROUTE_TICK_MS    = 30 * 60 * 1000 -- 30 Minuten

-- ────────────────────────────────────────────────────────────
--  Interne Helfer
-- ────────────────────────────────────────────────────────────

local function GetIdentifier(source)
    for _, v in ipairs(GetPlayerIdentifiers(source)) do
        if v:sub(1, 8) == "license:" then return v end
    end
    return nil
end

-- Lädt Company komplett aus DB in Cache
local function LoadCompany(companyId, cb)
    MySQL.single(
        "SELECT * FROM mt_companies WHERE id = ?",
        { companyId },
        function(row)
            if not row then
                cb(nil)
                return
            end
            companyCache[companyId] = {
                id         = row.id,
                name       = row.name,
                owner      = row.owner,
                balance    = row.balance,
                reputation = row.reputation,
            }
            cb(companyCache[companyId])
        end
    )
end

-- Gibt Company-Data zurück; lädt aus DB wenn nicht im Cache
local function GetCompany(companyId, cb)
    if companyCache[companyId] then
        cb(companyCache[companyId])
    else
        LoadCompany(companyId, cb)
    end
end

-- Mitglied-Lookup: gibt { companyId, role } oder nil zurück
local function GetMembership(identifier, cb)
    if memberCache[identifier] ~= nil then
        cb(memberCache[identifier])
        return
    end
    MySQL.single(
        [[SELECT cm.company_id, cm.role
          FROM mt_company_members cm
          WHERE cm.identifier = ?]],
        { identifier },
        function(row)
            if row then
                memberCache[identifier] = { companyId = row.company_id, role = row.role }
            else
                memberCache[identifier] = false -- false = kein Mitglied (gecacht)
            end
            cb(memberCache[identifier])
        end
    )
end

-- Löscht Member-Cache-Einträge (nach Rolle-Änderung / Rauswurf)
local function InvalidateMemberCache(identifier)
    memberCache[identifier] = nil
end

-- Sende aktualisierte Company-Daten an alle Online-Mitglieder
local function BroadcastToMembers(companyId, eventName, data)
    MySQL.query(
        "SELECT identifier FROM mt_company_members WHERE company_id = ?",
        { companyId },
        function(rows)
            if not rows then return end
            for _, row in ipairs(rows) do
                -- Spieler online?
                for _, playerId in ipairs(GetPlayers()) do
                    local id = GetIdentifier(tonumber(playerId))
                    if id == row.identifier then
                        TriggerClientEvent(eventName, tonumber(playerId), data)
                        break
                    end
                end
            end
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  NPC-Routen Simulation
-- ────────────────────────────────────────────────────────────

local function RunRouteTick()
    -- Alle aktiven Routen aus DB laden
    MySQL.query(
        [[SELECT cr.id, cr.company_id, cr.route_type, cr.vehicle_id
          FROM mt_company_routes cr
          WHERE cr.active = 1]],
        {},
        function(routes)
            if not routes or #routes == 0 then return end

            -- Pro Company: Einnahmen und Kosten aggregieren
            local companyDeltas = {} -- [companyId] = netDelta

            for _, route in ipairs(routes) do
                local cid          = route.company_id

                -- Auszahlung: abhängig vom Route-Typ + Zufallsvarianz
                local jobCfg       = Config.Jobs[route.route_type]
                local basePay      = jobCfg and jobCfg.baseWage or ROUTE_PAYOUT_MIN
                local payout       = math.random(
                    math.floor(basePay * 0.15), -- 15% des normalen Job-Lohns
                    math.floor(basePay * 0.25)  -- 25% (NPC ist weniger effizient)
                )
                local cost         = ROUTE_MAINT_COST

                companyDeltas[cid] = (companyDeltas[cid] or 0) + (payout - cost)

                -- last_payout aktualisieren
                MySQL.update(
                    "UPDATE mt_company_routes SET last_payout = NOW() WHERE id = ?",
                    { route.id }
                )
            end

            -- Company-Konten aktualisieren
            for companyId, delta in pairs(companyDeltas) do
                MySQL.update(
                    "UPDATE mt_companies SET balance = GREATEST(0, balance + ?) WHERE id = ?",
                    { delta, companyId }
                )

                -- Cache invalidieren
                if companyCache[companyId] then
                    companyCache[companyId].balance =
                        math.max(0, (companyCache[companyId].balance or 0) + delta)
                end

                -- Online-Mitglieder informieren
                BroadcastToMembers(companyId, MT.COMPANY_PAYOUT, {
                    companyId = companyId,
                    delta     = delta,
                    net       = delta > 0 and delta or 0,
                    costs     = ROUTE_MAINT_COST,
                })

                print(("[MT][Company] ID %d – Routen-Tick: %+d$"):format(companyId, delta))
            end
        end
    )
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Company gründen
-- ────────────────────────────────────────────────────────────

local function OnCompanyFound(source, data)
    local source = source
    if not data or not data.name or #data.name < 3 then
        TriggerClientEvent("mt:company:result", source, {
            success = false, error = "Name muss mindestens 3 Zeichen lang sein."
        })
        return
    end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    -- Bereits Mitglied?
    GetMembership(identifier, function(membership)
        if membership then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Du bist bereits Mitglied einer Firma."
            })
            return
        end

        -- Gründungskosten abziehen
        local removed = _PlayerModule.RemoveMoney(source, FOUND_COST,
            ("Firmengründung: %s"):format(data.name))
        if not removed then
            TriggerClientEvent("mt:company:result", source, {
                success = false,
                error = ("Gründungskosten: %s"):format(
                    Utils.FormatMoney(FOUND_COST))
            })
            return
        end

        -- Name bereits vergeben?
        MySQL.scalar(
            "SELECT id FROM mt_companies WHERE name = ?",
            { data.name },
            function(existing)
                if existing then
                    -- Geld zurückgeben
                    _PlayerModule.AddMoney(source, FOUND_COST, "Firmengründung fehlgeschlagen")
                    TriggerClientEvent("mt:company:result", source, {
                        success = false, error = "Firmenname bereits vergeben."
                    })
                    return
                end

                -- Company anlegen
                MySQL.insert(
                    "INSERT INTO mt_companies (name, owner, balance) VALUES (?, ?, 0)",
                    { data.name, identifier },
                    function(companyId)
                        if not companyId then
                            -- Race Condition: zwei Spieler mit gleichem Namen gleichzeitig
                            _PlayerModule.AddMoney(source, FOUND_COST, "Firmengründung fehlgeschlagen")
                            TriggerClientEvent("mt:company:result", source, {
                                success = false, error = "Firmenname bereits vergeben (Konflikt)."
                            })
                            return
                        end
                        -- Owner als Mitglied eintragen
                        MySQL.insert(
                            [[INSERT INTO mt_company_members
                              (company_id, identifier, role) VALUES (?, ?, 'owner')]],
                            { companyId, identifier }
                        )

                        -- Cache befüllen
                        companyCache[companyId] = {
                            id = companyId,
                            name = data.name,
                            owner = identifier,
                            balance = 0,
                            reputation = 0,
                        }
                        memberCache[identifier] = { companyId = companyId, role = "owner" }

                        TriggerClientEvent("mt:company:result", source, {
                            success   = true,
                            companyId = companyId,
                            name      = data.name,
                        })

                        TriggerEvent(MT.COMPANY_CREATED, companyId, identifier)
                        print(("[MT][Company] '%s' gegründet von %s"):format(
                            data.name, identifier))
                    end
                )
            end
        )
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Company-Daten laden (für UI)
-- ────────────────────────────────────────────────────────────

local function OnCompanyDataRequest(source)
    local source = source
    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership then
            TriggerClientEvent("mt:company:data", source, { membership = false })
            return
        end

        GetCompany(membership.companyId, function(company)
            if not company then
                TriggerClientEvent("mt:company:data", source, { membership = false })
                return
            end

            -- Mitglieder-Liste laden
            MySQL.query(
                [[SELECT cm.identifier, cm.role, p.name
                  FROM mt_company_members cm
                  LEFT JOIN mt_players p ON p.identifier = cm.identifier
                  WHERE cm.company_id = ?]],
                { company.id },
                function(members)
                    -- Aktive Routen laden
                    MySQL.query(
                        [[SELECT cr.id, cr.route_type, cr.active, cr.last_payout,
                                 v.model, v.plate
                          FROM mt_company_routes cr
                          LEFT JOIN mt_vehicles v ON v.id = cr.vehicle_id
                          WHERE cr.company_id = ?]],
                        { company.id },
                        function(routes)
                            TriggerClientEvent("mt:company:data", source, {
                                membership = membership,
                                company    = company,
                                members    = members or {},
                                routes     = routes or {},
                            })
                        end
                    )
                end
            )
        end)
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Mitglied einladen
-- ────────────────────────────────────────────────────────────

local function OnMemberInvite(source, data)
    local source = source
    -- data = { targetIdentifier }
    if not data or not data.targetIdentifier then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership or membership.role == "driver" then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Keine Berechtigung."
            })
            return
        end

        -- Ziel bereits Mitglied?
        GetMembership(data.targetIdentifier, function(targetMembership)
            if targetMembership then
                TriggerClientEvent("mt:company:result", source, {
                    success = false, error = "Spieler ist bereits Mitglied einer Firma."
                })
                return
            end

            MySQL.insert(
                [[INSERT INTO mt_company_members (company_id, identifier, role)
                  VALUES (?, ?, 'driver')]],
                { membership.companyId, data.targetIdentifier },
                function(insertId)
                    if not insertId then
                        TriggerClientEvent("mt:company:result", source, {
                            success = false, error = "Datenbankfehler."
                        })
                        return
                    end

                    memberCache[data.targetIdentifier] = {
                        companyId = membership.companyId, role = "driver"
                    }

                    -- Ziel-Spieler benachrichtigen falls online
                    for _, playerId in ipairs(GetPlayers()) do
                        local pid = tonumber(playerId)
                        if GetIdentifier(pid) == data.targetIdentifier then
                            TriggerClientEvent(MT.COMPANY_MEMBER_ADD, pid, {
                                companyId = membership.companyId,
                                role      = "driver",
                            })
                            break
                        end
                    end

                    TriggerClientEvent("mt:company:result", source, {
                        success = true,
                        action = "invited",
                        target = data.targetIdentifier,
                    })
                end
            )
        end)
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Mitglied entlassen
-- ────────────────────────────────────────────────────────────

local function OnMemberKick(source, data)
    local source = source
    if not data or not data.targetIdentifier then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership or membership.role == "driver" then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Keine Berechtigung."
            })
            return
        end

        -- Owner kann sich nicht selbst rauswerfen
        if data.targetIdentifier == identifier then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Du kannst dich nicht selbst entlassen."
            })
            return
        end

        MySQL.update(
            [[DELETE FROM mt_company_members
              WHERE company_id = ? AND identifier = ? AND role != 'owner']],
            { membership.companyId, data.targetIdentifier },
            function(affected)
                if affected == 0 then
                    TriggerClientEvent("mt:company:result", source, {
                        success = false, error = "Spieler nicht gefunden oder ist Owner."
                    })
                    return
                end

                InvalidateMemberCache(data.targetIdentifier)

                -- Entlassenem Spieler Bescheid geben falls online
                for _, playerId in ipairs(GetPlayers()) do
                    local pid = tonumber(playerId)
                    if GetIdentifier(pid) == data.targetIdentifier then
                        TriggerClientEvent(MT.COMPANY_MEMBER_KICK, pid, {})
                        break
                    end
                end

                TriggerClientEvent("mt:company:result", source, {
                    success = true, action = "kicked"
                })
            end
        )
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Route erstellen / pausieren
-- ────────────────────────────────────────────────────────────

local function OnRouteCreate(source, data)
    local source = source
    -- data = { routeType, vehicleId }
    if not data or not data.routeType or not data.vehicleId then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    -- Nur Manager/Owner dürfen Routen erstellen
    GetMembership(identifier, function(membership)
        if not membership or membership.role == "driver" then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Keine Berechtigung."
            })
            return
        end

        -- Job-Typ existiert?
        if not Config.Jobs[data.routeType] then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Ungültiger Routen-Typ."
            })
            return
        end

        -- Fahrzeug gehört dem Spieler?
        MySQL.scalar(
            "SELECT id FROM mt_vehicles WHERE id = ? AND identifier = ?",
            { data.vehicleId, identifier },
            function(vehId)
                if not vehId then
                    TriggerClientEvent("mt:company:result", source, {
                        success = false, error = "Fahrzeug nicht gefunden."
                    })
                    return
                end

                MySQL.insert(
                    [[INSERT INTO mt_company_routes
                      (company_id, route_type, vehicle_id, active)
                      VALUES (?, ?, ?, 1)]],
                    { membership.companyId, data.routeType, data.vehicleId },
                    function(routeId)
                        TriggerClientEvent("mt:company:result", source, {
                            success = true, action = "routeCreated", routeId = routeId
                        })
                    end
                )
            end
        )
    end)
end

local function OnRouteToggle(source, data)
    local source = source
    -- data = { routeId }
    if not data or not data.routeId then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership or membership.role == "driver" then return end

        MySQL.update(
            [[UPDATE mt_company_routes
              SET active = 1 - active
              WHERE id = ? AND company_id = ?]],
            { data.routeId, membership.companyId },
            function(affected)
                if affected > 0 then
                    TriggerClientEvent("mt:company:result", source, {
                        success = true, action = "routeToggled"
                    })
                end
            end
        )
    end)
end

-- ────────────────────────────────────────────────────────────
--  Net Events: Geld einzahlen / auszahlen (Owner only)
-- ────────────────────────────────────────────────────────────

local function OnCompanyDeposit(source, data)
    local source = source
    if not data or not data.amount or data.amount <= 0 then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership or membership.role ~= "owner" then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Nur Owner können einzahlen."
            })
            return
        end

        local removed = _PlayerModule.RemoveMoney(source, data.amount, "Company Einzahlung")
        if not removed then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Nicht genug Geld."
            })
            return
        end

        MySQL.update(
            "UPDATE mt_companies SET balance = balance + ? WHERE id = ?",
            { data.amount, membership.companyId }
        )

        if companyCache[membership.companyId] then
            companyCache[membership.companyId].balance =
                companyCache[membership.companyId].balance + data.amount
        end

        TriggerClientEvent("mt:company:result", source, {
            success = true, action = "deposit", amount = data.amount
        })

        BroadcastToMembers(membership.companyId, MT.COMPANY_BALANCE_UPDATE, {
            balance = companyCache[membership.companyId] and
                companyCache[membership.companyId].balance or 0
        })
    end)
end

local function OnCompanyWithdraw(source, data)
    local source = source
    if not data or not data.amount or data.amount <= 0 then return end

    local identifier = GetIdentifier(source)
    if not identifier then return end

    GetMembership(identifier, function(membership)
        if not membership or membership.role ~= "owner" then
            TriggerClientEvent("mt:company:result", source, {
                success = false, error = "Nur Owner können auszahlen."
            })
            return
        end

        GetCompany(membership.companyId, function(company)
            if not company or company.balance < data.amount then
                TriggerClientEvent("mt:company:result", source, {
                    success = false, error = "Firmenkontostand unzureichend."
                })
                return
            end

            MySQL.update(
                "UPDATE mt_companies SET balance = balance - ? WHERE id = ?",
                { data.amount, membership.companyId }
            )

            companyCache[membership.companyId].balance =
                companyCache[membership.companyId].balance - data.amount

            _PlayerModule.AddMoney(source, data.amount, "Company Auszahlung")

            TriggerClientEvent("mt:company:result", source, {
                success = true, action = "withdraw", amount = data.amount
            })

            BroadcastToMembers(membership.companyId, MT.COMPANY_BALANCE_UPDATE, {
                balance = companyCache[membership.companyId].balance
            })
        end)
    end)
end

-- ────────────────────────────────────────────────────────────
--  Öffentliche API
-- ────────────────────────────────────────────────────────────

function CompanyModule.GetMembership(identifier, cb)
    GetMembership(identifier, cb)
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function CompanyModule.Init()
    RegisterNetEvent("mt:company:found", OnCompanyFound)
    RegisterNetEvent("mt:company:dataRequest", OnCompanyDataRequest)
    RegisterNetEvent(MT.COMPANY_MEMBER_ADD, OnMemberInvite)
    RegisterNetEvent(MT.COMPANY_MEMBER_KICK, OnMemberKick)
    RegisterNetEvent("mt:company:routeCreate", OnRouteCreate)
    RegisterNetEvent("mt:company:routeToggle", OnRouteToggle)
    RegisterNetEvent("mt:company:deposit", OnCompanyDeposit)
    RegisterNetEvent("mt:company:withdraw", OnCompanyWithdraw)

    -- Cache aufräumen wenn Spieler disconnectet
    AddEventHandler("playerDropped", function()
        local id = GetIdentifier(source)
        if id then memberCache[id] = nil end
    end)

    -- NPC-Routen Simulation
    SetInterval(RunRouteTick, ROUTE_TICK_MS)

    exports("GetMembership", CompanyModule.GetMembership)

    print("[MT] CompanyModule (Server) initialisiert")
end

_CompanyModule = CompanyModule

-- ────────────────────────────────────────────────────────────
