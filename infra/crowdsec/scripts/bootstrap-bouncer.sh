#!/usr/bin/env bash
# Creates the shared Traefik bouncer API key as a secret file (ADR-0013 §2, ADR-0016).
# CrowdSec registers a bouncer named "traefik" automatically from /run/secrets/bouncer_key_traefik;
# Traefik's plugin reads the same value from /run/secrets/crowdsec_bouncer_key. Usage: bootstrap-bouncer.sh <secrets-dir>
set -euo pipefail
DIR="${1:?secrets dir required}"
mkdir -p "$DIR"
if [[ -s "$DIR/crowdsec_bouncer_key" ]]; then
  echo "keep   crowdsec_bouncer_key"
else
  umask 077
  openssl rand -hex 32 | tr -d '\n' > "$DIR/crowdsec_bouncer_key"
  echo "write  crowdsec_bouncer_key"
fi
