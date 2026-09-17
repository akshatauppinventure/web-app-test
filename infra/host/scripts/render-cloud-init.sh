#!/usr/bin/env bash
# Renders infra/host/cloud-init/<role>.yaml.tmpl into a complete cloud-config: substitutes the
# host variables from a vars file and embeds the repo's scripts/units/configs (indented) so the
# committed files are the single source of truth. Usage: render-cloud-init.sh <edge|core> <vars-file> [out]
# vars file (KEY=VALUE): HOSTNAME, ADMIN_USER, ADMIN_SSH_PUBKEY, PUBLIC_HOST, PUBLIC_IF (name or "auto"),
#                        WG_PRIVATE_KEY (this host's bootstrap key, T20), ADMIN_PUBLIC_KEY,
#                        CORE_PUBLIC_KEY/CORE_ENDPOINT (edge) or EDGE_PUBLIC_KEY/EDGE_ENDPOINT (core)
# Every WireGuard key must be a real key (44-char base64): a placeholder would make wg-quick fail at
# first boot and leave the host unreachable (sshd listens on the WireGuard address only).
set -euo pipefail
ROLE="${1:?edge|core}"; VARS="${2:?vars file}"; OUT="${3:-/dev/stdout}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMPL="$HERE/cloud-init/$ROLE.yaml.tmpl"
set -a
# shellcheck source=/dev/null
. "$VARS"
set +a
: "${HOSTNAME:?}" "${ADMIN_USER:?}" "${ADMIN_SSH_PUBKEY:?}" "${PUBLIC_HOST:?}" "${PUBLIC_IF:?}" "${ADMIN_PUBLIC_KEY:?}" "${WG_PRIVATE_KEY:?}"
PEER_VAR="$([[ $ROLE == edge ]] && echo CORE_PUBLIC_KEY || echo EDGE_PUBLIC_KEY)"
for v in WG_PRIVATE_KEY ADMIN_PUBLIC_KEY "$PEER_VAR"; do
  [[ "${!v:-}" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "render-cloud-init: $v must be a 44-character base64 WireGuard key (got '${!v:-<unset>}')" >&2; exit 1; }
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
    "__PUBLIC_HOST__": env["PUBLIC_HOST"], "__ADMIN_PUBLIC_KEY__": env["ADMIN_PUBLIC_KEY"],
    "__WG_PRIVATE_KEY__": env["WG_PRIVATE_KEY"],
    "__CORE_PUBLIC_KEY__": env.get("CORE_PUBLIC_KEY", ""),
    "__CORE_ENDPOINT__": env.get("CORE_ENDPOINT", "10.0.0.2:51820"),
    "__EDGE_PUBLIC_KEY__": env.get("EDGE_PUBLIC_KEY", ""),
    "__EDGE_ENDPOINT__": env.get("EDGE_ENDPOINT", "10.0.0.11:51820"),
}
files = {
    "__DAEMON_JSON__": here / "docker/daemon.json",
    "__NFT_RULES__": here / f"nftables/{role}.nft",
    "__WG_TEMPLATE__": here / f"wireguard/wg0-{role}.conf.tmpl",
    "__DOCKER_USER_RULES__": here / "scripts/docker-user-rules.sh",
    "__WG_APPLY_PSKS__": here / "scripts/wg-apply-psks.sh",
    "__WG_ROTATE_KEY__": here / "scripts/wg-rotate-key.sh",
    "__RESOLVE_PUBLIC_IF__": here / "scripts/resolve-public-if.sh",
    "__HEALTHCHECK__": here / "scripts/healthcheck.sh",
    "__UNIT_DOCKER_USER_RULES__": here / "systemd/docker-user-rules.service",
    "__UNIT_DOCKER_DROPIN__": here / "systemd/docker.service.d/wireguard.conf",
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
        # placeholders inside embedded files (nft public interface, wg keys) are substituted too
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
