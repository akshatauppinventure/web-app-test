#!/usr/bin/env bash
# Generates a throwaway self-signed certificate for the public hostname so the Traefik test stack
# can serve TLS with sniStrict (ACME is disabled in tests). Output: .traefik-test/ (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST="${1:-test-vinayak.duckdns.org}"
OUT="$ROOT/.traefik-test"
mkdir -p "$OUT/certs" "$OUT/dynamic"
if [[ ! -s "$OUT/certs/cert.pem" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
    -subj "/CN=$HOST" -addext "subjectAltName=DNS:$HOST" \
    -keyout "$OUT/certs/key.pem" -out "$OUT/certs/cert.pem" >/dev/null 2>&1
  chmod 644 "$OUT/certs/key.pem" "$OUT/certs/cert.pem"   # read by uid 65532 in the container
fi
cat > "$OUT/dynamic/zz-test-certs.yml" <<YAML
# test-only: self-signed certificate for $HOST (never used outside compose.traefik-test.yaml)
tls:
  certificates:
    - certFile: /certs/cert.pem
      keyFile: /certs/key.pem
YAML
echo "test certificate for $HOST in $OUT"
