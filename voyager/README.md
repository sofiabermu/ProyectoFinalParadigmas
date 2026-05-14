# Voyager IX — Nodo Sonda (SWI-Prolog)

Puerto: **7001** (servidor TCP)

## Prerequisitos

```bash
# Ubuntu
apt install swi-prolog

# macOS
brew install swi-prolog
```

## Arranque aislado

```bash
cd kepler/voyager
swipl -s voyager.pl -g start_server
```

## Prueba manual

```bash
# Disparar OBSERVE
echo '{"type":"OBSERVE"}' | nc localhost 7001

# Consultar historial
echo '{"type":"QUERY_HISTORY","mission_id":"VOY-IX-KEPLER442","limit":5}' | nc localhost 7001
```

## Base de conocimiento

`knowledge_base.pl` contiene 22 reglas en 3 grupos:

| Grupo | Reglas | Propósito |
|-------|--------|-----------|
| Origen natural | 6 | `not_volcanic_eruption`, `not_tidal_heating`, `not_meteor_impact`, `not_geothermal_primary`, `not_atmospheric_lightning`, `not_solar_reflection` |
| Error de sensor | 6 | `not_sensor_noise`, `not_sensor_saturation`, `not_cosmic_ray`, `not_stray_light`, `not_dark_current`, `not_emi_interference` |
| Clasificación | 10 | `classify_unnatural_origin`, `classify_stellar_flare`, `classify_aurora_candidate`, `classify_transit_candidate`, `classify_geothermal_anomaly`, `rule_uv_excess`, `rule_radio_emission`, `rule_photometric_dip`, `rule_stellar_flare_uv`, `rule_stellar_flare_xray` |

### Lógica de descarte

`run_inference/3` aplica las reglas en orden:
1. Intenta todas las reglas naturales → si alguna falla, esa explicación natural queda disponible.
2. Intenta todas las reglas de sensor.
3. Clasifica con las reglas de anomalía.
4. Si `classify_unnatural_origin` se dispara (todos los descartes exitosos), concluye "origen no natural conocido".
