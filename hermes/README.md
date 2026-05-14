# HERMES — Nodo Relay (Haskell + Cabal)

Puerto: **7003** (servidor TCP)  
Conecta a: Voyager IX en **7001** y ATLAS en **7002**

## Prerequisitos

```bash
# Ubuntu
apt install ghc cabal-install
cabal update

# macOS
brew install ghc cabal-install
cabal update
```

## Arranque aislado

```bash
cd kepler/hermes
cabal build
cabal run hermes
```

## Prueba manual

```bash
# Enviar payload similar a Voyager
echo '{"mission_id":"VOY-IX-KEPLER442","confidence":0.92,"conclusion":"origen no natural conocido","timestamp_utc":"2026-05-13T12:00:00Z","coordinates":{"right_ascension":"18h 52m 27.6s","declination":"+41 51 50.1"},"spectral_reading":[{"wavelength_nm":486,"intensity":0.91}],"inference_chain":["not_volcanic_eruption","classify_unnatural_origin"],"traceability_chain":[{"node":"VOYAGER_IX","action":"EMIT","timestamp_utc":"2026-05-13T12:00:00Z"}]}' | nc localhost 7003
```

## Diseño

- `Protocol.hs` — ADT `VoyagerReport`, `HermesEnvelope`, instancias Aeson
- `Hashing.hs` — SHA-256 puro sobre JSON canónico (`cryptonite`)
- `ErrorCorrection.hs` — Repetition code (3×): majority-vote por triplete de bytes
- `Main.hs` — IO en el borde: TCP server, fork por conexión, retry exponencial

### Corrección de errores

Se usa **triple-repetition code**: cada byte se codifica como 3 copias idénticas.
El decodificador aplica votación mayoritaria por grupo de 3 bytes. Si el grupo
no es unánime, cuenta un bit corregido. Es más simple que Hamming(7,4) y
suficiente para demostrar el concepto en un canal de baja tasa de error.
