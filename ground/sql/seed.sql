-- =============================================================
-- Proyecto Kepler — Seed Data
-- =============================================================

USE kepler;

-- -------------------------------------------------------------
-- Misiones (incluyendo Kepler-442 principal + 2 históricas)
-- -------------------------------------------------------------
INSERT INTO missions (mission_id, name, launched_at, target_system, responsible_agency) VALUES
-- Misión principal del demo
('VOY-IX-KEPLER442',  'Kepler-442 Deep Survey',       '2024-03-15 08:00:00', 'Kepler-442 System',    'NASA'),
-- Misiones históricas
('VOY-VII-TRAPPIST1', 'TRAPPIST-1 Exoplanet Survey',  '2023-01-10 12:00:00', 'TRAPPIST-1 System',    'ESA'),
('VOY-VIII-PROXIMA',  'Proxima Centauri Observation',  '2023-07-22 06:30:00', 'Alpha Centauri System', 'JAXA');

-- -------------------------------------------------------------
-- Sondas asociadas
-- -------------------------------------------------------------
INSERT INTO probes (probe_id, mission_id, model, sensor_status, last_telemetry_at) VALUES
('PROBE-VOY-IX-001',  'VOY-IX-KEPLER442',  'Voyager-IX Deep Probe',    'NOMINAL',   '2026-05-13 00:00:00'),
('PROBE-VOY-VII-001', 'VOY-VII-TRAPPIST1', 'Voyager-VII Survey Probe', 'DEGRADED',  '2026-05-10 18:45:00'),
('PROBE-VOY-VIII-001','VOY-VIII-PROXIMA',  'Voyager-VIII Pathfinder',  'NOMINAL',   '2026-05-12 09:22:00');

-- -------------------------------------------------------------
-- Observaciones históricas — TRAPPIST-1 (3 observaciones)
-- -------------------------------------------------------------
INSERT INTO observations
    (mission_id, right_ascension, declination, spectral_reading_json, confidence,
     observed_at_utc, conclusion, inference_chain_json)
VALUES
(
    'VOY-VII-TRAPPIST1',
    '23h 06m 29.37s', '-05° 02\' 28.6"',
    '[{"wavelength_nm":486,"intensity":0.72},{"wavelength_nm":656,"intensity":0.91},{"wavelength_nm":850,"intensity":0.55}]',
    0.760,
    '2025-11-03 14:22:10.000',
    'Emisión espectral anómala — posible actividad geotérmica subsuperficial',
    '["not_volcanic_eruption","not_stellar_flare","not_sensor_saturation","classify_geothermal_anomaly"]'
),
(
    'VOY-VII-TRAPPIST1',
    '23h 06m 31.12s', '-05° 02\' 31.0"',
    '[{"wavelength_nm":121,"intensity":1.20},{"wavelength_nm":486,"intensity":0.68},{"wavelength_nm":1083,"intensity":0.43}]',
    0.820,
    '2025-11-10 09:15:44.000',
    'Radiación UV elevada — posible origen estelar o aurora planetaria',
    '["not_meteor_impact","not_sensor_noise","rule_uv_excess","classify_aurora_candidate"]'
),
(
    'VOY-VII-TRAPPIST1',
    '23h 06m 28.50s', '-05° 02\' 27.1"',
    '[{"wavelength_nm":550,"intensity":0.34},{"wavelength_nm":750,"intensity":0.89},{"wavelength_nm":940,"intensity":1.15}]',
    0.910,
    '2025-12-01 22:40:55.000',
    'Origen no natural conocido — estructura espectral no catalogada',
    '["not_volcanic_eruption","not_tidal_heating","not_stellar_flare","not_sensor_noise","not_cosmic_ray","classify_unnatural_origin"]'
);

-- -------------------------------------------------------------
-- Observaciones históricas — Proxima Centauri (3 observaciones)
-- -------------------------------------------------------------
INSERT INTO observations
    (mission_id, right_ascension, declination, spectral_reading_json, confidence,
     observed_at_utc, conclusion, inference_chain_json)
VALUES
(
    'VOY-VIII-PROXIMA',
    '14h 29m 43.00s', '-62° 40\' 46.2"',
    '[{"wavelength_nm":430,"intensity":0.55},{"wavelength_nm":550,"intensity":0.61},{"wavelength_nm":700,"intensity":0.48}]',
    0.650,
    '2025-09-14 17:08:30.000',
    'Variación fotométrica — posible tránsito planetario',
    '["not_sensor_saturation","not_sensor_noise","rule_photometric_dip","classify_transit_candidate"]'
),
(
    'VOY-VIII-PROXIMA',
    '14h 29m 44.55s', '-62° 40\' 48.9"',
    '[{"wavelength_nm":200,"intensity":2.10},{"wavelength_nm":300,"intensity":1.75},{"wavelength_nm":450,"intensity":0.90}]',
    0.730,
    '2025-10-02 11:33:20.000',
    'Llamarada estelar confirmada — descarte de anomalía artificial',
    '["rule_stellar_flare_uv","rule_stellar_flare_xray","not_sensor_saturation","classify_stellar_flare"]'
),
(
    'VOY-VIII-PROXIMA',
    '14h 29m 42.80s', '-62° 40\' 45.5"',
    '[{"wavelength_nm":486,"intensity":0.99},{"wavelength_nm":656,"intensity":1.45},{"wavelength_nm":1083,"intensity":0.77}]',
    0.880,
    '2025-10-20 03:55:10.000',
    'Origen no natural conocido — emisión persistente sin correlato estelar',
    '["not_volcanic_eruption","not_tidal_heating","not_stellar_flare","not_sensor_noise","not_cosmic_ray","classify_unnatural_origin"]'
);

-- -------------------------------------------------------------
-- Transmissions para observaciones históricas (observation_id 1–6)
-- -------------------------------------------------------------
INSERT INTO transmissions
    (observation_id, traceability_chain_json, payload_hash, corrected_bits_count, received_at_ground_utc)
VALUES
(1,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'a3f1c2e4b5d6789012345678901234567890abcdef1234567890abcdef123456', 0, '2025-11-03 14:22:45.000'),
(2,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'b4e2d3f5c6a7890123456789012345678901bcdef2345678901bcdef234567', 2, '2025-11-10 09:16:10.000'),
(3,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'c5f3e4g6d7b8901234567890123456789012cdef3456789012cdef345678', 0, '2025-12-01 22:41:30.000'),
(4,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'd6a4f5h7e8c9012345678901234567890123def4567890123def456789', 1, '2025-09-14 17:09:05.000'),
(5,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'e7b5g6i8f9d0123456789012345678901234ef5678901234ef567890', 0, '2025-10-02 11:33:55.000'),
(6,'[{"node":"VOYAGER_IX","action":"EMIT"},{"node":"HERMES","action":"RELAY"},{"node":"ATLAS","action":"ENRICH"}]',
 'f8c6h7j9g0e1234567890123456789012345f6789012345f6789012', 3, '2025-10-20 03:55:45.000');

-- -------------------------------------------------------------
-- Alerts para observaciones históricas
-- -------------------------------------------------------------
INSERT INTO alerts (observation_id, priority_level, justification, created_at_utc) VALUES
(1, 'PRIORITY_MEDIUM', 'Confidence 0.76 — actividad geotérmica, seguimiento recomendado',    '2025-11-03 14:22:45.000'),
(2, 'PRIORITY_HIGH',   'Confidence 0.82 — aurora planetaria, análisis espectral prioritario', '2025-11-10 09:16:10.000'),
(3, 'PRIORITY_MAX',    'Confidence 0.91 + origen no natural — escalado a comité científico',   '2025-12-01 22:41:30.000'),
(4, 'PRIORITY_LOW',    'Confidence 0.65 — tránsito candidato, confirmación pendiente',         '2025-09-14 17:09:05.000'),
(5, 'PRIORITY_LOW',    'Confidence 0.73 — llamarada estelar clasificada, sin novedad',         '2025-10-02 11:33:55.000'),
(6, 'PRIORITY_MAX',    'Confidence 0.88 + origen no natural — emisión persistente anomalía',   '2025-10-20 03:55:45.000');

-- -------------------------------------------------------------
-- 16 agencias del consorcio (tabla de referencia en memoria de ATLAS)
-- Esta tabla es informativa; ATLAS la lee de AgencyRegistry.java
-- La incluimos aquí para trazabilidad documental.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agencies (
    agency_code     VARCHAR(16)  NOT NULL,
    full_name       VARCHAR(255) NOT NULL,
    country         VARCHAR(128) NOT NULL,
    joined_at       YEAR         NOT NULL,
    CONSTRAINT pk_agencies PRIMARY KEY (agency_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO agencies (agency_code, full_name, country, joined_at) VALUES
('NASA',      'National Aeronautics and Space Administration',              'United States',      1958),
('ESA',       'European Space Agency',                                      'European Union',     1975),
('JAXA',      'Japan Aerospace Exploration Agency',                         'Japan',              2003),
('CNSA',      'China National Space Administration',                        'China',              1993),
('ISRO',      'Indian Space Research Organisation',                         'India',              1969),
('ROSCOSMOS', 'State Space Corporation Roscosmos',                          'Russia',             1992),
('CSA',       'Canadian Space Agency',                                      'Canada',             1989),
('KARI',      'Korea Aerospace Research Institute',                         'South Korea',        1989),
('CNES',      'Centre National d\'Études Spatiales',                        'France',             1961),
('DLR',       'Deutsches Zentrum für Luft- und Raumfahrt',                  'Germany',            1997),
('ASI',       'Agenzia Spaziale Italiana',                                  'Italy',              1988),
('UKSA',      'UK Space Agency',                                            'United Kingdom',     2010),
('UAE-SA',    'UAE Space Agency',                                           'United Arab Emirates',2014),
('INPE',      'Instituto Nacional de Pesquisas Espaciais',                  'Brazil',             1971),
('SNSB',      'Swedish National Space Agency',                              'Sweden',             1972),
('NCSIST',    'National Chung-Shan Institute of Science and Technology',    'Taiwan',             1969);
