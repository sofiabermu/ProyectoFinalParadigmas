#!/usr/bin/env bash
# ================================================================
# start-all.sh — Proyecto Kepler
# Levanta los 4 nodos en el orden correcto:
#   MySQL → GROUND → ATLAS → HERMES → Voyager IX
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
PIDS_FILE="$SCRIPT_DIR/.pids"

# ---- Variables de entorno con defaults -------------------------
export MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
export MYSQL_PORT="${MYSQL_PORT:-3307}"
export MYSQL_DB="${MYSQL_DB:-kepler}"
export MYSQL_USER="${MYSQL_USER:-kepler}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-kepler_dev_2026}"
export GROUND_URL="${GROUND_URL:-http://localhost:5000}"
export HERMES_HOST="${HERMES_HOST:-localhost}"
export HERMES_TCP_PORT="${HERMES_TCP_PORT:-7003}"
export ATLAS_TCP_PORT="${ATLAS_TCP_PORT:-7002}"
export ATLAS_HTTP_PORT="${ATLAS_HTTP_PORT:-8080}"

# ---- Detectar intérpretes --------------------------------------
PERL_BIN="${PERL_BIN:-$(which perl 2>/dev/null || echo perl)}"
# Preferir Strawberry Perl en Windows (tiene los módulos)
if [ -f "/c/Strawberry/perl/bin/perl.exe" ]; then
    PERL_BIN="/c/Strawberry/perl/bin/perl.exe"
fi

MVN_BIN="${MVN_BIN:-mvn}"
if [ -f "/c/Program Files/NetBeans-20/netbeans/java/maven/bin/mvn" ]; then
    MVN_BIN="/c/Program Files/NetBeans-20/netbeans/java/maven/bin/mvn"
fi

SWIPL_BIN="${SWIPL_BIN:-$(which swipl 2>/dev/null || echo swipl)}"
CABAL_BIN="${CABAL_BIN:-$(which cabal 2>/dev/null || echo cabal)}"

echo ""
echo "================================================================"
echo "  PROYECTO KEPLER — Sistema Distribuido de Transmisión Estelar"
echo "================================================================"
echo ""

# ================================================================
# PASO 1: MySQL via Docker
# ================================================================
echo "[START] Levantando MySQL 8 (Docker)..."
docker compose up -d
echo "[START] Esperando a que MySQL acepte conexiones..."
until docker exec kepler_mysql mysqladmin ping -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent 2>/dev/null; do
    printf "."
    sleep 3
done
echo ""
echo "[START] MySQL listo en puerto $MYSQL_PORT"

# ================================================================
# PASO 2: Aplicar schema y seed
# ================================================================
echo "[START] Aplicando schema.sql..."
docker exec -i kepler_mysql mysql -h 127.0.0.1 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    < ground/sql/schema.sql 2>/dev/null || echo "  (schema ya existe, continuando)"

echo "[START] Aplicando seed.sql..."
docker exec -i kepler_mysql mysql -h 127.0.0.1 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    < ground/sql/seed.sql 2>/dev/null || echo "  (seed ya aplicado, continuando)"

echo "[START] Base de datos lista."

# ================================================================
# PASO 3: GROUND (Perl + Mojolicious, puerto 5000)
# ================================================================
echo "[START] Iniciando GROUND (puerto 5000)..."
cd "$SCRIPT_DIR/ground"
"$PERL_BIN" ground.pl daemon -l "http://*:5000" > "$SCRIPT_DIR/logs/ground.log" 2>&1 &
GROUND_PID=$!
echo $GROUND_PID >> "$PIDS_FILE"
cd "$SCRIPT_DIR"

# Esperar a que GROUND responda
for i in $(seq 1 20); do
    if curl -s http://localhost:5000/api/summary/ping >/dev/null 2>&1 || \
       curl -s http://localhost:5000/api/health >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
echo "[START] GROUND listo (PID $GROUND_PID)"

# ================================================================
# PASO 4: ATLAS (Java 21, TCP 7002 + HTTP 8080)
# ================================================================
echo "[START] Iniciando ATLAS (TCP 7002 / HTTP 8080)..."
mkdir -p "$SCRIPT_DIR/logs"
cd "$SCRIPT_DIR/atlas"
"$MVN_BIN" -q exec:java > "$SCRIPT_DIR/logs/atlas.log" 2>&1 &
ATLAS_PID=$!
echo $ATLAS_PID >> "$PIDS_FILE"
cd "$SCRIPT_DIR"

# Esperar health check HTTP
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/api/health >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
echo "[START] ATLAS listo (PID $ATLAS_PID)"

# ================================================================
# PASO 5: HERMES (Haskell, puerto 7003)
# ================================================================
echo "[START] Iniciando HERMES (puerto 7003)..."
cd "$SCRIPT_DIR/hermes"
cabal run hermes > "$SCRIPT_DIR/logs/hermes.log" 2>&1 &
HERMES_PID=$!
echo $HERMES_PID >> "$PIDS_FILE"
cd "$SCRIPT_DIR"

sleep 5
echo "[START] HERMES listo (PID $HERMES_PID)"

# ================================================================
# PASO 6: Voyager IX (Prolog, puerto 7001)
# ================================================================
echo "[START] Iniciando Voyager IX (puerto 7001)..."
cd "$SCRIPT_DIR/voyager"
"$SWIPL_BIN" -s voyager.pl -g start_server > "$SCRIPT_DIR/logs/voyager.log" 2>&1 &
VOYAGER_PID=$!
echo $VOYAGER_PID >> "$PIDS_FILE"
cd "$SCRIPT_DIR"

sleep 6
echo "[START] Voyager IX listo (PID $VOYAGER_PID)"

# ================================================================
# Resumen
# ================================================================
echo ""
echo "================================================================"
echo "  KEPLER SYSTEM — ESTADO DE NODOS"
echo "================================================================"
printf "  %-20s  %-8s  %s\n" "NODO" "PUERTO" "ESTADO"
printf "  %-20s  %-8s  %s\n" "----" "------" "------"

check_port() {
    local port=$1
    if netstat -an 2>/dev/null | grep -q ":${port}.*LISTEN" 2>/dev/null || \
       curl -s "localhost:${port}" >/dev/null 2>&1 || \
       "$PERL_BIN" -e "use IO::Socket::INET; my \$s=IO::Socket::INET->new(PeerAddr=>\"127.0.0.1:${port}\",Timeout=>2); print defined(\$s)?'OK':'DOWN'" 2>/dev/null; then
        echo "ACTIVO"
    else
        echo "VERIFICAR"
    fi
}

printf "  %-20s  %-8s  %s\n" "Voyager IX (Prolog)" "7001" "$(check_port 7001)"
printf "  %-20s  %-8s  %s\n" "HERMES (Haskell)" "7003" "$(check_port 7003)"
printf "  %-20s  %-8s  %s\n" "ATLAS TCP (Java)" "7002" "$(check_port 7002)"
printf "  %-20s  %-8s  %s\n" "ATLAS HTTP (Java)" "8080" "$(check_port 8080)"
printf "  %-20s  %-8s  %s\n" "GROUND (Perl)" "5000" "$(check_port 5000)"
printf "  %-20s  %-8s  %s\n" "MySQL (Docker)" "3307" "$(check_port 3307)"
echo "================================================================"
echo ""
echo "Logs en: $SCRIPT_DIR/logs/"
echo "PIDs guardados en: $PIDS_FILE"
echo ""
echo "Para detener: ./stop-all.sh"
echo "Para demo:    ./demo.sh"
echo ""
