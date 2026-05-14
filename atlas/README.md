# ATLAS — Nodo Relay (Java 21 + Maven)

Puertos: **TCP 7002** (recibe de HERMES) | **HTTP 8080** (REST)

## Prerequisitos

```bash
# Ubuntu
apt install openjdk-21-jdk maven

# macOS
brew install openjdk@21 maven
```

## Variables de entorno

| Variable          | Default                 |
|-------------------|-------------------------|
| `ATLAS_TCP_PORT`  | `7002`                  |
| `ATLAS_HTTP_PORT` | `8080`                  |
| `GROUND_URL`      | `http://localhost:5000` |
| `HERMES_HOST`     | `localhost`             |
| `HERMES_TCP_PORT` | `7003`                  |

## Arranque aislado

```bash
cd kepler/atlas
mvn -q exec:java
```

## Prueba manual

```bash
# Enviar payload TCP simulado (con GROUND arriba)
echo '{"mission_id":"VOY-IX-KEPLER442","confidence":0.92,"conclusion":"origen no natural conocido","timestamp_utc":"2026-05-13T12:00:00Z","coordinates":{"right_ascension":"18h 52m","declination":"+41 51"},"spectral_reading":[],"inference_chain":[],"payload_hash":"abc","corrected_bits_count":0,"traceability_chain":[]}' | nc localhost 7002

# Health check REST
curl http://localhost:8080/api/health

# Query history (requiere HERMES arriba)
curl http://localhost:8080/api/history/VOY-IX-KEPLER442
```

## Arquitectura interna

- `AtlasMain` — arranca dos `ExecutorService` de un hilo cada uno
- `TcpServer` — `ServerSocket(7002)` + pool de hilos para conexiones concurrentes
- `RestServer` — `com.sun.net.httpserver.HttpServer(8080)`
- `AgencyRegistry` — `ConcurrentHashMap` compartido entre ambos servidores
- `PriorityClassifier` — lógica pura sin estado
