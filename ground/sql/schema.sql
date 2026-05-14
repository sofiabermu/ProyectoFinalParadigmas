-- =============================================================
-- Proyecto Kepler — Schema MySQL 8
-- Charset: utf8mb4 | Engine: InnoDB
-- =============================================================

CREATE DATABASE IF NOT EXISTS kepler
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE kepler;

-- -------------------------------------------------------------
-- 1. missions
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS missions (
    mission_id          VARCHAR(64)     NOT NULL,
    name                VARCHAR(255)    NOT NULL,
    launched_at         DATETIME        NOT NULL,
    target_system       VARCHAR(255)    NOT NULL,
    responsible_agency  VARCHAR(128)    NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_missions PRIMARY KEY (mission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- 2. probes
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS probes (
    probe_id            VARCHAR(64)     NOT NULL,
    mission_id          VARCHAR(64)     NOT NULL,
    model               VARCHAR(128)    NOT NULL,
    sensor_status       ENUM('NOMINAL','DEGRADED','OFFLINE') NOT NULL DEFAULT 'NOMINAL',
    last_telemetry_at   DATETIME        NULL,
    CONSTRAINT pk_probes PRIMARY KEY (probe_id),
    CONSTRAINT fk_probes_mission
        FOREIGN KEY (mission_id) REFERENCES missions(mission_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- 3. observations
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observations (
    observation_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    mission_id          VARCHAR(64)     NOT NULL,
    right_ascension     VARCHAR(32)     NOT NULL,
    declination         VARCHAR(32)     NOT NULL,
    spectral_reading_json JSON          NOT NULL,
    confidence          DECIMAL(4,3)    NOT NULL,
    observed_at_utc     DATETIME(3)     NOT NULL,
    conclusion          TEXT            NOT NULL,
    inference_chain_json JSON           NOT NULL,
    CONSTRAINT pk_observations PRIMARY KEY (observation_id),
    CONSTRAINT fk_observations_mission
        FOREIGN KEY (mission_id) REFERENCES missions(mission_id)
        ON DELETE CASCADE,
    INDEX idx_obs_mission (mission_id),
    INDEX idx_obs_observed (observed_at_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- 4. transmissions
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transmissions (
    transmission_id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    observation_id          BIGINT UNSIGNED NOT NULL,
    traceability_chain_json JSON            NOT NULL,
    payload_hash            VARCHAR(64)     NOT NULL,
    corrected_bits_count    INT UNSIGNED    NOT NULL DEFAULT 0,
    received_at_ground_utc  DATETIME(3)     NOT NULL,
    CONSTRAINT pk_transmissions PRIMARY KEY (transmission_id),
    CONSTRAINT fk_transmissions_observation
        FOREIGN KEY (observation_id) REFERENCES observations(observation_id)
        ON DELETE CASCADE,
    INDEX idx_trans_observation (observation_id),
    INDEX idx_trans_hash (payload_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- 5. alerts
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alerts (
    alert_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    observation_id  BIGINT UNSIGNED NOT NULL,
    priority_level  ENUM('PRIORITY_LOW','PRIORITY_MEDIUM','PRIORITY_HIGH','PRIORITY_MAX') NOT NULL,
    justification   TEXT            NOT NULL,
    created_at_utc  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT pk_alerts PRIMARY KEY (alert_id),
    CONSTRAINT fk_alerts_observation
        FOREIGN KEY (observation_id) REFERENCES observations(observation_id)
        ON DELETE CASCADE,
    INDEX idx_alerts_priority (priority_level),
    INDEX idx_alerts_observation (observation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
