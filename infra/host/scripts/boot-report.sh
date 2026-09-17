#!/usr/bin/env bash
# Prints a first-boot / health summary to the VNC console (tty1) and to /var/log/boot-report.log so the
# host can be diagnosed without SSH (T20: sshd listens on wg0 only, so a broken tunnel hides everything).
# Runs last in cloud-init runcmd; safe to re-run any time. Never prints secrets (keys, tokens).
set -uo pipefail
OUT="${BOOT_REPORT_OUT:-/dev/tty1}"; LOG="${BOOT_REPORT_LOG:-/var/log/boot-report.log}"
report() {
  echo "===== web-app-test boot report $(date -u +%FT%TZ) host=$(hostname) ====="
  echo "cloud-init: $(cloud-init status 2>/dev/null | tr '\n' ' ')"
  echo "failed units: $(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ *$//')"
  echo "default route: $(ip -o -4 route show default 2>/dev/null | head -1)"
  echo "addresses: $(ip -br -4 addr 2>/dev/null | tr -s ' ' | tr '\n' ';')"
  echo "packages: wireguard-tools=$(dpkg-query -W -f='${Version}' wireguard-tools 2>/dev/null || echo MISSING) nftables=$(dpkg-query -W -f='${Version}' nftables 2>/dev/null || echo MISSING) docker-ce=$(dpkg-query -W -f='${Version}' docker-ce 2>/dev/null || echo MISSING)"
  echo "public if (nft): $(sed -n 's/^define PUBLIC_IF = "\(.*\)"$/\1/p' /etc/nftables.conf 2>/dev/null) | host.env: $(sed -n 's/^PUBLIC_IF=//p' /etc/app/host.env 2>/dev/null)"
  echo "nftables: $(systemctl is-active nftables 2>/dev/null); wg rule: $(nft list chain inet filter input 2>/dev/null | grep -c 'udp dport')"
  echo "wg-quick@wg0: $(systemctl is-active wg-quick@wg0 2>/dev/null); wg0 public key: $(cat /etc/wireguard/public.key 2>/dev/null)"
  wg show wg0 2>/dev/null | grep -E 'listening port|peer:|latest handshake|transfer' | sed 's/^/  /'
  echo "docker: $(systemctl is-active docker 2>/dev/null); docker-user-rules: $(systemctl is-active docker-user-rules 2>/dev/null)"
  echo "cloud-init errors (last 5):"; grep -iE 'error|fail|Traceback' /var/log/cloud-init-output.log 2>/dev/null | grep -viE 'failed units: $|0 fail' | tail -5 | sed 's/^/  /'
  echo "===== end boot report ====="
}
report | tee -a "$LOG" > "$OUT" 2>/dev/null || report | tee -a "$LOG"
