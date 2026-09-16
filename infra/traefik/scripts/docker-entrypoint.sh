#!/bin/sh
# Renders the static configuration (ACME email / CA server come from the environment because a
# Traefik static file cannot reference variables) into a tmpfs and starts Traefik.
set -eu
: "${ACME_EMAIL:?ACME_EMAIL is required}"
: "${ACME_CA_SERVER:=https://acme-v02.api.letsencrypt.org/directory}"
: "${LOG_LEVEL:=INFO}"
: "${FORWARDED_TRUSTED_IPS:=}"      # comma-separated CIDRs allowed to set X-Forwarded-*; empty = none
mkdir -p /tmp/traefik
sed -e "s|__ACME_EMAIL__|${ACME_EMAIL}|g" \
    -e "s|__ACME_CA_SERVER__|${ACME_CA_SERVER}|g" \
    -e "s|__LOG_LEVEL__|${LOG_LEVEL}|g" \
    -e "s|__FORWARDED_TRUSTED_IPS__|${FORWARDED_TRUSTED_IPS}|g" \
    /etc/traefik/traefik.yml > /tmp/traefik/traefik.yml
exec traefik --configFile=/tmp/traefik/traefik.yml "$@"
