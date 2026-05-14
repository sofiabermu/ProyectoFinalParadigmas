#!/usr/bin/env bash
# ================================================================
# stop-all.sh — Detiene todos los nodos del Proyecto Kepler
# ================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_FILE="$SCRIPT_DIR/.pids"

echo "[STOP] Deteniendo nodos Kepler..."

if [ -f "$PIDS_FILE" ]; then
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null && echo "  Proceso $pid detenido"
        fi
    done < "$PIDS_FILE"
    rm -f "$PIDS_FILE"
else
    echo "  No se encontró .pids — intentando por nombre de proceso"
    pkill -f "voyager.pl"    2>/dev/null && echo "  Voyager IX detenido"
    pkill -f "ground.pl"     2>/dev/null && echo "  GROUND detenido"
    pkill -f "AtlasMain"     2>/dev/null && echo "  ATLAS detenido"
    pkill -f "exec:java.*atlas" 2>/dev/null && echo "  ATLAS Maven detenido"
    pkill -f "hermes"        2>/dev/null && echo "  HERMES detenido"
fi

cd "$SCRIPT_DIR" && docker compose down 2>/dev/null && echo "  MySQL detenido"

echo "[STOP] Sistema Kepler detenido."
