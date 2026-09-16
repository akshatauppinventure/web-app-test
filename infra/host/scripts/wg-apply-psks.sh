#!/usr/bin/env bash
# PostUp hook: apply pre-shared keys from /etc/wireguard/psk-<name> files to peers listed in
# /etc/wireguard/psk-map (lines: "<peer public key> <psk file name>"). Missing files are skipped.
set -euo pipefail
IFACE="${1:?interface}"
MAP=/etc/wireguard/psk-map
[[ -r "$MAP" ]] || exit 0
while read -r pubkey pskfile; do
  [[ -z "$pubkey" || "$pubkey" == \#* ]] && continue
  if [[ -r "/etc/wireguard/$pskfile" ]]; then
    wg set "$IFACE" peer "$pubkey" preshared-key "/etc/wireguard/$pskfile"
  fi
done < "$MAP"
