# GROUND — Nodo de Persistencia (Perl + Mojolicious + MySQL)

Puerto: **5000**

## Prerequisitos

```bash
# Ubuntu
apt install perl cpanminus
cpanm --installdeps .

# macOS
brew install perl cpanminus
cpanm --installdeps .
```

## Variables de entorno

| Variable        | Default          |
|-----------------|------------------|
| `MYSQL_HOST`    | `127.0.0.1`      |
| `MYSQL_PORT`    | `3307`           |
| `MYSQL_DB`      | `kepler`         |
| `MYSQL_USER`    | `kepler`         |
| `MYSQL_PASSWORD`| `kepler_dev_2026`|

## Arranque aislado

```bash
# Con MySQL ya corriendo (docker compose up -d desde kepler/)
cd kepler/ground
perl ground.pl daemon -l http://*:5000
```

## Prueba manual

```bash
# POST evento simulado
curl -s -X POST http://localhost:5000/api/events \
  -H 'Content-Type: application/json' \
  -d '{
    "mission_id":         "VOY-IX-KEPLER442",
    "coordinates":        {"right_ascension":"18h 52m 27.6s","declination":"+41° 51 50.1\""},
    "spectral_reading":   [{"wavelength_nm":486,"intensity":0.91}],
    "confidence":         0.92,
    "timestamp_utc":      "2026-05-13T12:00:00Z",
    "inference_chain":    ["not_volcanic_eruption","classify_unnatural_origin"],
    "conclusion":         "origen no natural conocido",
    "payload_hash":       "abc123",
    "corrected_bits_count": 0,
    "priority_level":     "PRIORITY_MAX",
    "responsible_agency": "NASA",
    "traceability_chain": [{"node":"VOYAGER_IX","action":"EMIT","timestamp_utc":"2026-05-13T12:00:00Z"}]
  }' | python3 -m json.tool

# GET resumen
curl -s http://localhost:5000/api/summary/VOY-IX-KEPLER442 | python3 -m json.tool

# GET historial
curl -s http://localhost:5000/api/history/VOY-IX-KEPLER442 | python3 -m json.tool
```

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/api/events` | Recibe evento enriquecido de ATLAS, persiste en 3 tablas |
| GET  | `/api/summary/:mission_id` | Resumen consolidado de misión |
| GET  | `/api/history/:mission_id` | Historial completo de observaciones |
