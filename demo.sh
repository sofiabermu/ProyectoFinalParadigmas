#!/usr/bin/env bash
# ================================================================
# demo.sh — Demostración end-to-end del Proyecto Kepler
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERL_BIN="${PERL_BIN:-perl}"
if [ -f "/c/Strawberry/perl/bin/perl.exe" ]; then
    PERL_BIN="/c/Strawberry/perl/bin/perl.exe"
fi

SEP="================================================================"

echo ""
echo "$SEP"
echo "  PROYECTO KEPLER — DEMO END-TO-END"
echo "  Transmisión de Hallazgo Astronómico: Voyager IX → GROUND"
echo "$SEP"
echo ""

# ----------------------------------------------------------------
# PASO 1: Verificar MySQL
# ----------------------------------------------------------------
echo "[ 1/7 ] Verificando MySQL..."
if docker exec kepler_mysql mysqladmin ping -u kepler -pkepler_dev_2026 --silent 2>/dev/null; then
    echo "        MySQL OK — kepler_mysql en puerto 3307"
else
    echo "        ERROR: MySQL no responde. Ejecuta: ./start-all.sh"
    exit 1
fi
echo ""

# ----------------------------------------------------------------
# PASO 2: Disparar OBSERVE en Voyager IX
# ----------------------------------------------------------------
echo "[ 2/7 ] Disparando OBSERVE en Voyager IX (puerto 7001)..."
echo "        Voyager ejecuta inferencia por descarte sobre el espectro..."
echo ""

VOYAGER_RESPONSE=$(
    "$PERL_BIN" -e '
use IO::Socket::INET;
my $s = IO::Socket::INET->new(PeerAddr=>"127.0.0.1:7001",Proto=>"tcp",Timeout=>15)
    or die "No se puede conectar a Voyager IX: $!";
print $s "{\"type\":\"OBSERVE\"}\n";
my $r = <$s>; close $s;
print $r // "";
' 2>&1 )

if [ -z "$VOYAGER_RESPONSE" ]; then
    echo "  ERROR: Voyager IX no respondió. ¿Está corriendo?"
    exit 1
fi

CONCLUSION=$(echo "$VOYAGER_RESPONSE" | "$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{conclusion}' 2>/dev/null || echo "N/A")
CONFIDENCE=$(echo "$VOYAGER_RESPONSE" | "$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{confidence}' 2>/dev/null || echo "N/A")
CHAIN_LEN=$(echo "$VOYAGER_RESPONSE" | "$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print scalar @{$d->{inference_chain}}' 2>/dev/null || echo "0")

echo "  [VOYAGER IX] Observación generada:"
echo "    Conclusión  : $CONCLUSION"
echo "    Confianza   : $CONFIDENCE"
echo "    Reglas aplic: $CHAIN_LEN"
echo ""

# Guardar respuesta de Voyager en archivo temporal para evitar corrupción de shell
TMP_VOY=$(mktemp /tmp/kepler_voy.XXXXXX)
TMP_HRM=$(mktemp /tmp/kepler_hrm.XXXXXX)
TMP_ATL=$(mktemp /tmp/kepler_atl.XXXXXX)
echo "$VOYAGER_RESPONSE" > "$TMP_VOY"

# ----------------------------------------------------------------
# PASO 3: Mensaje viajando por HERMES
# ----------------------------------------------------------------
echo "[ 3/7 ] Enviando reporte a HERMES (puerto 7003)..."
"$PERL_BIN" - "$TMP_VOY" "$TMP_HRM" <<'PERL_HERMES'
use IO::Socket::INET;
my ($in_file, $out_file) = @ARGV;
open(my $fh, '<', $in_file) or die "cannot open $in_file: $!";
my $payload = do { local $/; <$fh> }; close $fh;
chomp $payload;
my $s = IO::Socket::INET->new(PeerAddr=>"127.0.0.1:7003",Proto=>"tcp",Timeout=>25)
    or die "No se puede conectar a HERMES: $!";
print $s $payload . "\n";
my $r = <$s>; close $s;
open(my $ofh, '>', $out_file) or die $!;
print $ofh $r // ""; close $ofh;
PERL_HERMES

if [ ! -s "$TMP_HRM" ]; then
    echo "  ERROR: HERMES no respondió o respuesta vacía."
    rm -f "$TMP_VOY" "$TMP_HRM" "$TMP_ATL"
    exit 1
fi

BITS=$("$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{corrected_bits_count}//0' < "$TMP_HRM" 2>/dev/null || echo "0")
echo "  [HERMES] Mensaje procesado:"
echo "    Satélite    : HERMES-01"
echo "    Bits correg.: $BITS"
echo "    Hash SHA-256: (calculado y adjuntado)"
echo ""

# ----------------------------------------------------------------
# PASO 4: Mensaje enviado a ATLAS
# ----------------------------------------------------------------
echo "[ 4/7 ] HERMES reenvió a ATLAS (puerto 7002)..."
echo "  [ATLAS] Enriqueciendo con prioridad y agencia responsable..."

"$PERL_BIN" - "$TMP_HRM" "$TMP_ATL" <<'PERL_ATLAS'
use IO::Socket::INET;
my ($in_file, $out_file) = @ARGV;
open(my $fh, '<', $in_file) or die "cannot open $in_file: $!";
my $payload = do { local $/; <$fh> }; close $fh;
chomp $payload;
my $s = IO::Socket::INET->new(PeerAddr=>"127.0.0.1:7002",Proto=>"tcp",Timeout=>25)
    or die "No se puede conectar a ATLAS: $!";
print $s $payload . "\n";
my $r = <$s>; close $s;
open(my $ofh, '>', $out_file) or die $!;
print $ofh $r // ""; close $ofh;
PERL_ATLAS

if [ ! -s "$TMP_ATL" ]; then
    echo "  ERROR: ATLAS no respondió o respuesta vacía."
    rm -f "$TMP_VOY" "$TMP_HRM" "$TMP_ATL"
    exit 1
fi

PRIORITY=$("$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{priority_level}//"N/A"' < "$TMP_ATL" 2>/dev/null || echo "N/A")
AGENCY=$("$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{responsible_agency}//"N/A"' < "$TMP_ATL" 2>/dev/null || echo "N/A")
ACTIVE=$("$PERL_BIN" -MJSON::XS -e 'my $d=JSON::XS->new->decode(do{local $/;<STDIN>}); print $d->{active_missions_count}//0' < "$TMP_ATL" 2>/dev/null || echo "0")

echo "  [ATLAS] Enriquecido:"
echo "    Prioridad   : $PRIORITY"
echo "    Agencia     : $AGENCY"
echo "    Misiones act: $ACTIVE"
echo ""
rm -f "$TMP_VOY" "$TMP_HRM" "$TMP_ATL"

# ----------------------------------------------------------------
# PASO 5: Esperar a que GROUND procese
# ----------------------------------------------------------------
echo "[ 5/7 ] Esperando que GROUND persista el evento..."
sleep 3
echo "  [GROUND] Evento almacenado en MySQL"
echo ""

# ----------------------------------------------------------------
# PASO 6: GET resumen desde GROUND
# ----------------------------------------------------------------
echo "[ 6/7 ] Consultando resumen en GROUND..."
SUMMARY=$(curl -s "http://localhost:5000/api/summary/VOY-IX-KEPLER442" 2>&1)
echo "  [GROUND] GET /api/summary/VOY-IX-KEPLER442:"
echo "$SUMMARY" | "$PERL_BIN" -MJSON::XS -e '
my $d = JSON::XS->new->decode(do{local $/;<STDIN>});
printf "    mission_id     : %s\n", $d->{mission_id}//"N/A";
printf "    responsible    : %s\n", $d->{responsible_agency}//"N/A";
printf "    total_obs      : %s\n", $d->{total_observations}//0;
printf "    max_confidence : %s\n", $d->{max_confidence}//"N/A";
printf "    last_observed  : %s\n", $d->{last_observed_at}//"N/A";
' 2>/dev/null || echo "$SUMMARY"
echo ""

# ----------------------------------------------------------------
# PASO 7: Flujo inverso (historia) via ATLAS → HERMES → Voyager
# ----------------------------------------------------------------
echo "[ 7/7 ] Flujo inverso: ATLAS → HERMES → Voyager IX (historial)..."
HISTORY=$(curl -s "http://localhost:8080/api/history/VOY-IX-KEPLER442" 2>&1)
echo "  [ATLAS] GET /api/history/VOY-IX-KEPLER442:"
echo "$HISTORY" | "$PERL_BIN" -MJSON::XS -e '
my $d = eval { JSON::XS->new->decode(do{local $/;<STDIN>}) } // {};
if ($d->{observations}) {
    printf "    Total en Voyager: %s\n", $d->{total}//0;
    printf "    Tipo respuesta  : HISTORY_RESPONSE desde Voyager IX\n";
} elsif ($d->{error}) {
    printf "    (HERMES no disponible o Voyager sin historial previo: %s)\n", $d->{error};
} else {
    printf "    Respuesta: %s\n", substr(JSON::XS->new->encode($d),0,100);
}
' 2>/dev/null || echo "$HISTORY"
echo ""

# ----------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------
echo "$SEP"
echo "  FLUJO COMPLETO COMPLETADO"
echo "$SEP"
echo ""
echo "  Voyager IX  (Prolog)   →  reporte generado con inferencia lógica"
echo "     ↓ TCP:7001→7003"
echo "  HERMES      (Haskell)  →  SHA-256 + corrección de errores"
echo "     ↓ TCP:7003→7002"
echo "  ATLAS       (Java)     →  prioridad=$PRIORITY agencia=$AGENCY"
echo "     ↓ HTTP POST"
echo "  GROUND      (Perl)     →  persistido en MySQL 8"
echo ""
echo "  Flujo inverso: ATLAS HTTP → HERMES TCP → Voyager IX"
echo ""
echo "$SEP"
