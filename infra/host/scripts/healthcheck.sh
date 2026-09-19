#!/usr/bin/env bash
# Host health check every 5 minutes (ADR-0024 §1): container health, private-network peer reachability,
# disk usage, backup age (core), certificate expiry (edge). Failures go to journald and, when
# NOTIFY_WEBHOOK_URL is set in /etc/app/host.env, to a webhook (e.g. an ntfy topic).
set -uo pipefail
ENV_FILE="${ENV_FILE:-/etc/app/host.env}"
# shellcheck source=/dev/null
[[ -r "$ENV_FILE" ]] && . "$ENV_FILE"
ROLE="${HOST_ROLE:-unknown}"
PUBLIC_HOST="${PUBLIC_HOST:-test-vinayak.duckdns.org}"
PEER_IP="${PEER_IP:-}"                      # the other host's private-network address (ADR-0026)
DISK_LIMIT="${DISK_LIMIT_PERCENT:-80}"
BACKUP_MAX_AGE_H="${BACKUP_MAX_AGE_HOURS:-26}"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-14}"
problems=()

# 1. containers: everything running must be healthy (or have no healthcheck)
while read -r name health; do
  [[ -z "$name" ]] && continue
  [[ "$health" == "healthy" || "$health" == "none" ]] || problems+=("container $name is $health")
done < <(docker ps --format '{{.Names}} {{.State}}' 2>/dev/null | awk '$2=="running"{print $1}' | while read -r n; do
  h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$n" 2>/dev/null)"; echo "$n $h"; done)
[[ "$(docker ps -q 2>/dev/null | wc -l)" -gt 0 ]] || problems+=("no containers running")

# 2. the peer host answers on the private network (edge -> Keycloak/FastAPI, core -> Portainer Agent)
if [[ -n "$PEER_IP" ]]; then
  ping -c 2 -W 2 -q "$PEER_IP" >/dev/null 2>&1 || problems+=("private network: $PEER_IP does not answer ping")
fi

# 3. disk
usage="$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')"
(( usage < DISK_LIMIT )) || problems+=("disk usage ${usage}% >= ${DISK_LIMIT}%")

# 4. backup age (core only)
if [[ "$ROLE" == "core" ]]; then
  stamp=/var/lib/app/last-backup-ok
  if [[ ! -f "$stamp" ]]; then problems+=("backup: never succeeded")
  else
    age_h=$(( ( $(date +%s) - $(stat -c %Y "$stamp") ) / 3600 ))
    (( age_h < BACKUP_MAX_AGE_H )) || problems+=("backup: last success ${age_h}h ago")
  fi
fi

# 5. certificate expiry (edge only)
if [[ "$ROLE" == "edge" ]] && command -v openssl >/dev/null; then
  end="$(echo | timeout 10 openssl s_client -servername "$PUBLIC_HOST" -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [[ -z "$end" ]]; then problems+=("tls: could not read certificate for $PUBLIC_HOST")
  else
    days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
    (( days > CERT_MIN_DAYS )) || problems+=("tls: certificate expires in ${days}d")
  fi
fi

if (( ${#problems[@]} == 0 )); then
  logger -t healthcheck -p daemon.info "ok role=$ROLE"
  exit 0
fi
msg="healthcheck[$ROLE@$(hostname)]: $(IFS='; '; echo "${problems[*]}")"
logger -t healthcheck -p daemon.err "$msg"
if [[ -n "${NOTIFY_WEBHOOK_URL:-}" ]]; then
  curl -fsS --max-time 10 -H "Title: web-app-test $ROLE" -d "$msg" "$NOTIFY_WEBHOOK_URL" >/dev/null 2>&1 || logger -t healthcheck -p daemon.warning "webhook notification failed"
fi
exit 1
