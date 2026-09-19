#!/usr/bin/env bash
# Prints a first-boot / health summary to the VNC console (tty1) and to /var/log/boot-report.log so the
# host can be diagnosed without SSH (a failed first boot can leave sshd or the firewall unusable).
# Runs last in cloud-init runcmd and, with --loop, every 2 minutes from bootcmd until cloud-init is done
# (so a stuck package stage is visible too). Safe to re-run any time. Never prints secrets (keys, tokens).
set -uo pipefail
OUT="${BOOT_REPORT_OUT:-/dev/tty1}"; LOG="${BOOT_REPORT_LOG:-/var/log/boot-report.log}"
report() {
  echo "===== web-app-test boot report $(date -u +%FT%TZ) host=$(hostname) ====="
  echo "cloud-init: $(cloud-init status 2>/dev/null | tr '\n' ' ')"
  echo "failed units: $(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ *$//')"
  echo "default route: $(ip -o -4 route show default 2>/dev/null | head -1)"
  echo "addresses: $(ip -br -4 addr 2>/dev/null | tr -s ' ' | tr '\n' ';')"
  echo "packages: nftables=$(dpkg-query -W -f='${Version}' nftables 2>/dev/null || echo MISSING) docker-ce=$(dpkg-query -W -f='${Version}' docker-ce 2>/dev/null || echo MISSING)"
  echo "public if (nft): $(sed -n 's/^define PUBLIC_IF = "\(.*\)"$/\1/p' /etc/nftables.conf 2>/dev/null) | host.env: $(sed -n 's/^PUBLIC_IF=//p' /etc/app/host.env 2>/dev/null)"
  echo "nftables: $(systemctl is-active nftables 2>/dev/null); ssh rule: $(nft list chain inet filter input 2>/dev/null | grep -c 'tcp dport 22')"
  echo "sshd: $(systemctl is-active ssh 2>/dev/null); listening: $(ss -Htln 'sport = :22' 2>/dev/null | awk '{print $4}' | tr '\n' ' ')"
  echo "peer (private network): $(sed -n 's/^PEER_IP=//p' /etc/app/host.env 2>/dev/null)"
  echo "docker: $(systemctl is-active docker 2>/dev/null); docker-user-rules: $(systemctl is-active docker-user-rules 2>/dev/null)"
  # shellcheck disable=SC2009  # need the elapsed time column, pgrep has none
  echo "busy: $(ps -eo etimes,comm --sort=-etimes 2>/dev/null | grep -E 'apt|dpkg|cloud-init|unattended|snap' | head -4 | awk '{printf "%s(%ss) ", $2, $1}')"
  echo "cloud-init-output tail:"; tail -n 3 /var/log/cloud-init-output.log 2>/dev/null | cut -c1-110 | sed 's/^/  /'
  echo "cloud-init errors (last 4):"; grep -iE 'error|fail|Traceback' /var/log/cloud-init-output.log 2>/dev/null | grep -viE 'failed units: $|0 fail' | tail -4 | cut -c1-110 | sed 's/^/  /'
  echo "===== end boot report ====="
}
if [[ "${1:-}" == "--loop" ]]; then
  for _ in $(seq 1 30); do
    report | tee -a "$LOG" > "$OUT" 2>/dev/null || true
    cloud-init status 2>/dev/null | grep -qE "done|error|disabled" && exit 0
    sleep 120
  done
  exit 0
fi
report | tee -a "$LOG" > "$OUT" 2>/dev/null || report | tee -a "$LOG"
