-- ============================================================
--  shared/utils.lua
--  Reine Hilfsfunktionen – kein State, keine Side-Effects.
--  Alle Funktionen sind im globalen Utils-Table gekapselt.
-- ============================================================

Utils = {}

-- Euklidische 3D-Distanz zwischen zwei vector3
function Utils.Distance3D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 2D-Distanz (ignoriert Höhe) – nützlich für Zone-Checks auf flachem Terrain
function Utils.Distance2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Rundet n auf decimals Nachkommastellen
function Utils.Round(n, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(n * factor + 0.5) / factor
end

-- Formatiert eine Zahl als Geldstring: 12345 → "12.345 $"
function Utils.FormatMoney(amount)
    local s = tostring(math.floor(amount))
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        count = count + 1
        result = s:sub(i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "." .. result
        end
    end
    return result .. " $"
end

-- Gibt aktuellen Unix-Timestamp zurück (client/server kompatibel)
function Utils.Timestamp()
    return os.time()
end

-- Generiert ein zufälliges Kennzeichen: 3 Buchstaben + 3 Zahlen
function Utils.GeneratePlate()
    local chars = "ABCDEFGHJKLMNPRSTUVWXYZ"
    local plate = ""
    for _ = 1, 3 do
        local idx = math.random(1, #chars)
        plate = plate .. chars:sub(idx, idx)
    end
    for _ = 1, 3 do
        plate = plate .. math.random(0, 9)
    end
    return plate
end

-- Clamp: begrenzt n auf [min, max]
function Utils.Clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

-- Prüft ob ein Wert in einer Table existiert (lineare Suche)
function Utils.TableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

-- Flaches Merge zweier Tables (b überschreibt a)
function Utils.MergeTables(a, b)
    local result = {}
    for k, v in pairs(a) do result[k] = v end
    for k, v in pairs(b) do result[k] = v end
    return result
end

-- XP-Schwellenwert für ein gegebenes Level (quadratische Kurve)
function Utils.XPForLevel(level)
    return math.floor(100 * (level ^ 1.8))
end
