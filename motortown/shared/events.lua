-- ============================================================
--  shared/events.lua
--  Zentrale Wahrheit für alle Event-Namen.
--  Verwendung: TriggerEvent(MT.JOB_START, data)
--
--  Vorteil: Tippfehler in Event-Namen werden sofort als
--  nil-Zugriff sichtbar, statt lautlos zu scheitern.
-- ============================================================

MT                        = {}

-- Player -------------------------------------------------------
MT.PLAYER_LOADED          = "mt:player:loaded"
MT.PLAYER_MONEY_UPDATE    = "mt:player:moneyUpdate"
MT.PLAYER_XP_UPDATE       = "mt:player:xpUpdate"
MT.PLAYER_LEVEL_UP        = "mt:player:levelUp"

-- Jobs ---------------------------------------------------------
MT.JOB_START              = "mt:job:start"
MT.JOB_CARGO_LOADED       = "mt:job:cargoLoaded"
MT.JOB_COMPLETE           = "mt:job:complete"
MT.JOB_CANCEL             = "mt:job:cancel"
MT.JOB_REQUEST            = "mt:job:request" -- C→S: Job anfordern
MT.JOB_VALIDATE           = "mt:job:validate" -- S→C: Validierungsresult

-- Zones --------------------------------------------------------
MT.ZONE_ENTER             = "mt:zone:enter"
MT.ZONE_EXIT              = "mt:zone:exit"

-- Vehicles -----------------------------------------------------
MT.VEHICLE_SPAWN          = "mt:vehicle:spawn"
MT.VEHICLE_STORE          = "mt:vehicle:store"
MT.VEHICLE_UPGRADE_BUY    = "mt:vehicle:upgradeBuy"
MT.VEHICLE_UPGRADE_APPLY  = "mt:vehicle:upgradeApply"
MT.VEHICLE_DAMAGE_SYNC    = "mt:vehicle:damageSync"

-- Company ------------------------------------------------------
MT.COMPANY_CREATED        = "mt:company:created"
MT.COMPANY_PAYOUT         = "mt:company:payout"
MT.COMPANY_MEMBER_ADD     = "mt:company:memberAdd"
MT.COMPANY_MEMBER_KICK    = "mt:company:memberKick"
MT.COMPANY_BALANCE_UPDATE = "mt:company:balanceUpdate"

-- Supply Chain -------------------------------------------------
MT.SUPPLY_UPDATE          = "mt:supply:update"
MT.SUPPLY_JOB_GENERATED   = "mt:supply:jobGenerated"

-- Town Bonus ---------------------------------------------------
MT.BONUS_UPDATE           = "mt:townbonus:update"
