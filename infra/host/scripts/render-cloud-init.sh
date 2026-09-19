#!/usr/bin/env bash
# Renders infra/host/cloud-init/<role>.yaml.tmpl into a complete cloud-config: substitutes the
# host variables from a vars file and embeds the repo's scripts/units/configs (indented) so the
# committed files are the single source of truth. Usage: render-cloud-init.sh <edge|core> <vars-file> [out]
# vars file (KEY=VALUE): HOSTNAME, ADMIN_USER, ADMIN_SSH_PUBKEY, PUBLIC_HOST, PUBLIC_IF (name or "auto"),
#   EDGE_PRIVATE_IP (default 10.0.0.11), CORE_PRIVATE_IP (default 10.0.0.2): private-network addresses (ADR-0026),
#   ADMIN_SSH_CIDRS (default 0.0.0.0/0): comma-separated IPv4 CIDRs allowed to reach SSH.
set -euo pipefail
ROLE="${1:?edge|core}"; VARS="${2:?vars file}"; OUT="${3:-/dev/stdout}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMPL="$HERE/cloud-init/$ROLE.yaml.tmpl"
set -a
# shellcheck source=/dev/null
. "$VARS"
set +a
: "${HOSTNAME:?}" "${ADMIN_USER:?}" "${ADMIN_SSH_PUBKEY:?}" "${PUBLIC_HOST:?}" "${PUBLIC_IF:?}"
EDGE_PRIVATE_IP="${EDGE_PRIVATE_IP:-10.0.0.11}"; CORE_PRIVATE_IP="${CORE_PRIVATE_IP:-10.0.0.2}"
ADMIN_SSH_CIDRS="${ADMIN_SSH_CIDRS:-0.0.0.0/0}"
export EDGE_PRIVATE_IP CORE_PRIVATE_IP ADMIN_SSH_CIDRS
octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'; ipv4="$octet\.$octet\.$octet\.$octet"
for v in EDGE_PRIVATE_IP CORE_PRIVATE_IP; do
  [[ "${!v}" =~ ^$ipv4$ ]] || { echo "render-cloud-init: $v must be an IPv4 address (got '${!v}')" >&2; exit 1; }
done
[[ "$EDGE_PRIVATE_IP" != "$CORE_PRIVATE_IP" ]] || { echo "render-cloud-init: EDGE_PRIVATE_IP and CORE_PRIVATE_IP must differ" >&2; exit 1; }
IFS=',' read -r -a cidrs <<<"$ADMIN_SSH_CIDRS"
(( ${#cidrs[@]} > 0 )) || { echo "render-cloud-init: ADMIN_SSH_CIDRS is empty" >&2; exit 1; }
for c in "${cidrs[@]}"; do
  [[ "$c" =~ ^$ipv4/(3[0-2]|[12]?[0-9])$ ]] || { echo "render-cloud-init: ADMIN_SSH_CIDRS entry '$c' is not an IPv4 CIDR (a.b.c.d/n)" >&2; exit 1; }
done

python3 - "$TMPL" "$OUT" "$ROLE" "$HERE" <<'PY'
import os, sys, pathlib
tmpl, out, role, here = sys.argv[1:5]
here = pathlib.Path(here)
def indent(path, n=6):
    text = pathlib.Path(path).read_text().rstrip("\n")
    return "\n".join((" " * n + line) if line.strip() else "" for line in text.splitlines())
env = os.environ
subs = {
    "__HOSTNAME__": env["HOSTNAME"], "__ADMIN_USER__": env["ADMIN_USER"], "__ADMIN_SSH_PUBKEY__": env["ADMIN_SSH_PUBKEY"],
    "__PUBLIC_HOST__": env["PUBLIC_HOST"],
    "__EDGE_PRIVATE_IP__": env["EDGE_PRIVATE_IP"], "__CORE_PRIVATE_IP__": env["CORE_PRIVATE_IP"],
    "__ADMIN_SSH_CIDRS__": ", ".join(c.strip() for c in env["ADMIN_SSH_CIDRS"].split(",")),
}
files = {
    "__DAEMON_JSON__": here / "docker/daemon.json",
    "__NFT_RULES__": here / f"nftables/{role}.nft",
    "__DOCKER_USER_RULES__": here / "scripts/docker-user-rules.sh",
    "__RESOLVE_PUBLIC_IF__": here / "scripts/resolve-public-if.sh",
    "__BOOT_REPORT__": here / "scripts/boot-report.sh",
    "__HEALTHCHECK__": here / "scripts/healthcheck.sh",
    "__UNIT_DOCKER_USER_RULES__": here / "systemd/docker-user-rules.service",
    "__UNIT_DOCKER_DROPIN__": here / "systemd/docker.service.d/ordering.conf",
    "__UNIT_HEALTHCHECK_SERVICE__": here / "systemd/healthcheck.service",
    "__UNIT_HEALTHCHECK_TIMER__": here / "systemd/healthcheck.timer",
    "__BOOTSTRAP_COMPOSE__": here / ("bootstrap/portainer-agent.compose.yaml" if role == "edge" else "bootstrap/portainer-server.compose.yaml"),
    "__PG_BACKUP__": here / "scripts/pg-backup.sh",
    "__RESTIC_CHECK__": here / "scripts/restic-check.sh",
    "__RESTORE_DRILL__": here / "scripts/restore-drill.sh",
    "__UNIT_PG_BACKUP_SERVICE__": here / "systemd/pg-backup.service",
    "__UNIT_PG_BACKUP_TIMER__": here / "systemd/pg-backup.timer",
    "__UNIT_RESTIC_CHECK_SERVICE__": here / "systemd/restic-check.service",
    "__UNIT_RESTIC_CHECK_TIMER__": here / "systemd/restic-check.timer",
}
text = pathlib.Path(tmpl).read_text()
for k, v in subs.items():
    text = text.replace(k, v)
for k, p in files.items():
    if k in text:
        body = indent(p)
        # placeholders inside embedded files (nft interface and SSH sources) are substituted too
        body = body.replace("__PUBLIC_IF__", env["PUBLIC_IF"])
        for sk, sv in subs.items():
            body = body.replace(sk, sv)
        text = text.replace(k, body)
text = text.replace("__PUBLIC_IF__", env["PUBLIC_IF"])
left = [l for l in text.splitlines() if "__" in l]
if left:
    sys.exit("unrendered placeholders:\n" + "\n".join(left))
pathlib.Path(out).write_text(text) if out != "/dev/stdout" else sys.stdout.write(text)
PY
