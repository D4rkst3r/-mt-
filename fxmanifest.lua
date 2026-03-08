fx_version 'cerulean'
game 'gta5'

name 'motortown'
description 'Motor Town – custom FiveM recreation'
author 'D4rkst3r'
version '1.0.2'

-- Shared: geladen auf Client UND Server
-- WICHTIG: nur EIN shared_scripts-Block erlaubt, sonst wird der erste ignoriert!
shared_scripts {
    '@ox_lib/init.lua', -- stellt das globale "lib" bereit – muss zuerst kommen
    'shared/events.lua',
    'shared/utils.lua',
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
    'server/admin.lua', -- vor main.lua: lädt Overrides bevor andere Module starten
    'server/jobs.lua',
    'server/vehicles.lua',
    'server/company.lua',
    'server/supplychain.lua',
    'server/townbonus.lua',
    'server/main.lua',
}

-- Client-seitige Skripte
client_scripts {
    'client/player.lua',
    'client/zones.lua',
    'client/blips.lua',
    'client/jobs.lua',
    'client/vehicles.lua',
    'client/company.lua',
    'client/supplychain.lua',
    'client/townbonus.lua',
    'client/hud.lua',
    'client/admin.lua',
    'client/main.lua',
}

-- ox_lib wird als Dependency eingebunden (stellt require bereit)
dependencies {
    'oxmysql',
    'ox_target',
    'ox_lib',
}

lua54 'yes'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
}
