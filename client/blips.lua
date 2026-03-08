-- ============================================================
--  client/blips.lua
--  Blips werden direkt aus Config.Zones gelesen.
--  Jede Zone mit einem "blip"-Feld bekommt automatisch einen Blip.
--  Zone.label wird als Blip-Name verwendet.
--
--  Blip-Felder in Config.Zones:
--    blip = { sprite = 545, color = 3, scale = 0.9 }
--
--  GTA V Blip Sprites:  https://docs.fivem.net/game-references/blips/
--  GTA V Blip Farben:   0=weiß 1=rot 2=grün 3=blau 5=gelb
--                       6=lila 8=orange 59=orange(hell) 66=hellblau
-- ============================================================

local BlipsModule = {}

-- [zoneKey] = blipHandle
local activeBlips = {}

-- ────────────────────────────────────────────────────────────
--  Hilfsfunktion
-- ────────────────────────────────────────────────────────────

local function CreateZoneBlip(zoneKey, zoneDef)
    local b = zoneDef.blip
    if not b then return end

    local coords = zoneDef.coords
    if not coords then return end

    -- Koordinaten aus JSON (vom Admin-System) oder vec3
    local x, y, z
    if type(coords) == "userdata" then
        x, y, z = coords.x, coords.y, coords.z
    else
        x, y, z = coords.x, coords.y, coords.z
    end

    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, b.sprite or 477)
    SetBlipColour(blip, b.color or 2)
    SetBlipScale(blip, b.scale or 0.85)
    SetBlipAsShortRange(blip, true)

    local name = b.label or zoneDef.label or zoneKey
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(name)
    EndTextCommandSetBlipName(blip)

    return blip
end

local function RemoveZoneBlip(zoneKey)
    if activeBlips[zoneKey] and DoesBlipExist(activeBlips[zoneKey]) then
        RemoveBlip(activeBlips[zoneKey])
    end
    activeBlips[zoneKey] = nil
end

-- ────────────────────────────────────────────────────────────
--  Alle Blips aus Config.Zones erstellen
-- ────────────────────────────────────────────────────────────

local function CreateAllBlips()
    local count = 0
    for key, zoneDef in pairs(Config.Zones) do
        if zoneDef.blip then
            local blip = CreateZoneBlip(key, zoneDef)
            if blip then
                activeBlips[key] = blip
                count = count + 1
            end
        end
    end
    print(("[MT] %d Map-Blips aus Config.Zones erstellt"):format(count))
end

-- ────────────────────────────────────────────────────────────
--  Live-Update vom Admin-System
-- ────────────────────────────────────────────────────────────

local function OnZoneUpdate(payload)
    if not payload or not payload.key then return end
    local key = payload.key

    -- Alten Blip immer entfernen
    RemoveZoneBlip(key)

    if payload.deleted then return end

    local zd = payload.data
    if not zd or not zd.blip then return end

    -- Koordinaten aus JSON → plain table reicht für CreateZoneBlip
    local blip = CreateZoneBlip(key, zd)
    if blip then
        activeBlips[key] = blip
    end
end

-- ────────────────────────────────────────────────────────────
--  Init
-- ────────────────────────────────────────────────────────────

function BlipsModule.Init()
    AddEventHandler("mt:player:ready", function()
        CreateAllBlips()
    end)

    -- Live-Updates vom Admin-System mithören
    RegisterNetEvent("mt:admin:zoneUpdate", OnZoneUpdate)

    AddEventHandler("onResourceStop", function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end
        for _, blip in pairs(activeBlips) do
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end
        activeBlips = {}
    end)

    print("[MT] BlipsModule initialisiert (Config.Zones-basiert)")
end

_BlipsModule = BlipsModule
