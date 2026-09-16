#!/bin/sh
# Renders the static configuration (ACME email / CA server come from the environment because a
# Traefik static file cannot reference variables) into a tmpfs and starts Traefik.
set -eu
: "${ACME_EMAIL:?ACME_EMAIL is required}"
: "${ACME_CA_SERVER:=https://acme-v02.api.letsencrypt.org/directory}"
: "${LOG_LEVEL:=INFO}"
mkdir -p /tmp/traefik
sed -e "s|__ACME_EMAIL__|${ACME_EMAIL}|g" \
    -e "s|__ACME_CA_SERVER__|${ACME_CA_SERVER}|g" \
    -e "s|__LOG_LEVEL__|${LOG_LEVEL}|g" \
    /etc/traefik/traefik.yml > /tmp/traefik/traefik.yml
exec traefik --configFile=/tmp/traefik/traefik.yml "$@"
