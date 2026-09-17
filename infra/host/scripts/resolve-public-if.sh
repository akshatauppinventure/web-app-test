#!/usr/bin/env bash
# Replaces the "auto" public-interface placeholder in nftables.conf and host.env with the interface
# that carries the IPv4 default route. Providers name it differently (UpCloud eth0, OVH ens3), so it is
# detected at first boot. An explicit name set at render time is left untouched. Idempotent.
set -euo pipefail
NFT="${1:-/etc/nftables.conf}"; ENVF="${2:-/etc/app/host.env}"
IFC="$(ip -o -4 route show default | awk '{print $5}' | head -1)"
[[ "$IFC" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "resolve-public-if: no IPv4 default route interface found" >&2; exit 1; }
sed -i "s/^define PUBLIC_IF = \"auto\"\$/define PUBLIC_IF = \"$IFC\"/" "$NFT"
[[ -f "$ENVF" ]] && sed -i "s/^PUBLIC_IF=auto\$/PUBLIC_IF=$IFC/" "$ENVF"
grep -q '"auto"' "$NFT" && { echo "resolve-public-if: placeholder still present in $NFT" >&2; exit 1; }
echo "public interface: $(sed -n 's/^define PUBLIC_IF = "\(.*\)"$/\1/p' "$NFT")"
