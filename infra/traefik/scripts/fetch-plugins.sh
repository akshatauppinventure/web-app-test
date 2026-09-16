#!/usr/bin/env bash
# Downloads every plugin in plugins.lock, verifies its sha256 and (optionally) extracts it into
# <outdir>/src/<module>/ — the layout Traefik expects under /plugins-local. Also asserts that the
# Dockerfile pins the same version and checksum. Usage: fetch-plugins.sh [outdir]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
status=0
while read -r module version url sha256; do
  [[ -z "$module" || "$module" == \#* ]] && continue
  file="$tmp/$(basename "$url")"
  curl -fsSL --retry 3 -o "$file" "$url"
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$sha256" ]]; then
    echo "FAIL $module $version: sha256 $actual != $sha256"; status=1; continue
  fi
  echo "ok   $module $version"
  grep -q -- "--checksum=sha256:$sha256" Dockerfile || { echo "FAIL Dockerfile lacks --checksum=sha256:$sha256"; status=1; }
  grep -q -- "CROWDSEC_PLUGIN_VERSION=${version#v}" Dockerfile || { echo "FAIL Dockerfile version differs from plugins.lock ($version)"; status=1; }
  if [[ -n "$OUT" ]]; then
    dest="$OUT/src/$module"
    mkdir -p "$dest"
    tar -xzf "$file" -C "$dest" --strip-components=1
    echo "     extracted to $dest"
  fi
done < plugins.lock
exit $status
