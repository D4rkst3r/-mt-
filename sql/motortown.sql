-- ============================================================
--  MOTORTOWN – Datenbankschema
--  Ausführen einmalig beim Setup, danach via oxmysql auto-sync
-- ============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
--  Spieler
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_players` (
    `identifier`       VARCHAR(60)    NOT NULL,
    `name`             VARCHAR(60)    NOT NULL DEFAULT 'Unknown',
    `money`            INT UNSIGNED   NOT NULL DEFAULT 500,
    `bank`             INT UNSIGNED   NOT NULL DEFAULT 2000,
    `trucking_level`   SMALLINT       NOT NULL DEFAULT 1,
    `trucking_xp`      INT UNSIGNED   NOT NULL DEFAULT 0,
    `total_deliveries` INT UNSIGNED   NOT NULL DEFAULT 0,
    `total_earned`     BIGINT         NOT NULL DEFAULT 0,
    `last_seen`        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Transaktionslog – niemals direkt löschen, nur archivieren
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_transactions` (
    `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60)     NOT NULL,
    `amount`     INT             NOT NULL,         -- negativ = Abzug
    `type`       ENUM('cash','bank') NOT NULL DEFAULT 'cash',
    `reason`     VARCHAR(120)    NOT NULL DEFAULT '',
    `created_at` TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_created`    (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Fahrzeug-Besitz
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_vehicles` (
    `id`         INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60)     NOT NULL,
    `plate`      VARCHAR(8)      NOT NULL,
    `model`      VARCHAR(50)     NOT NULL,
    `upgrades`   JSON,                            -- {"motor":2,"getriebe":1,...}
    `fuel`       TINYINT UNSIGNED NOT NULL DEFAULT 100,
    `mileage`    INT UNSIGNED    NOT NULL DEFAULT 0,
    `stored`     TINYINT(1)      NOT NULL DEFAULT 1, -- 1=in Garage, 0=gespawnt
    `created_at` TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE  KEY `uq_plate`       (`plate`),
    INDEX       `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Companies
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_companies` (
    `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(60)   NOT NULL,
    `owner`       VARCHAR(60)   NOT NULL,   -- identifier des Gründers
    `balance`     BIGINT        NOT NULL DEFAULT 0,
    `reputation`  SMALLINT      NOT NULL DEFAULT 0,
    `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mt_company_members` (
    `company_id` INT UNSIGNED NOT NULL,
    `identifier` VARCHAR(60) NOT NULL,
    `role`       ENUM('owner','manager','driver') NOT NULL DEFAULT 'driver',
    `joined_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`company_id`, `identifier`),
    CONSTRAINT `fk_cm_company` FOREIGN KEY (`company_id`)
        REFERENCES `mt_companies`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mt_company_routes` (
    `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    `company_id`  INT UNSIGNED  NOT NULL,
    `route_type`  VARCHAR(40)   NOT NULL,   -- aus config/jobs.lua key
    `vehicle_id`  INT UNSIGNED  NOT NULL,
    `active`      TINYINT(1)    NOT NULL DEFAULT 1,
    `last_payout` TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    CONSTRAINT `fk_cr_company` FOREIGN KEY (`company_id`)
        REFERENCES `mt_companies`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Supply-Chain Lagerbestände
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_stocks` (
    `factory_key` VARCHAR(40)  NOT NULL,
    `input_stock` SMALLINT     NOT NULL DEFAULT 0,
    `output_stock` SMALLINT    NOT NULL DEFAULT 0,
    `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`factory_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Town Bonus
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_town_bonus` (
    `zone_key`   VARCHAR(40)     NOT NULL,
    `bonus`      DECIMAL(4,2)    NOT NULL DEFAULT 1.00,
    `updated_at` TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;