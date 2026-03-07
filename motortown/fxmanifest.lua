fx_version 'cerulean'
game 'gta5'

name 'motortown'
description 'Motor Town – custom FiveM recreation'
author 'D4rkst3r'
version '1.0.0'

-- Shared: geladen auf Client UND Server, zuerst
shared_scripts {
    'shared/events.lua',
    'shared/utils.lua',
}

-- Config: ebenfalls shared (Client braucht Werte für UI/Zonen)
shared_scripts {
    'config/config.lua',
    'config/jobs.lua',
    'config/vehicles.lua',
    'config/zones.lua',
    'config/supplychain.lua',
}

-- Server-seitige Skripte (Reihenfolge: Bootstrap zuletzt,
-- damit alle Module bereits definiert sind wenn er sie aufruft)
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/player.lua',
    'server/jobs.lua',
    'server/vehicles.lua',
    'server/company.lua',
    'server/supplychain.lua',
    'server/townbonus.lua',
    'server/main.lua', -- Bootstrap: ruft alle Init() auf
}

-- Client-seitige Skripte
client_scripts {
    'client/player.lua',
    'client/zones.lua',
    'client/jobs.lua',
    'client/vehicles.lua',
    'client/company.lua',
    'client/supplychain.lua',
    'client/townbonus.lua',
    'client/hud.lua',
    'client/main.lua', -- Bootstrap: ruft alle Init() auf
}

-- ox_lib wird als Dependency eingebunden (stellt require bereit)
dependencies {
    'oxmysql',
    'ox_target',
    'ox_lib',
    'ox_inventory',
}

lua54 'yes'
