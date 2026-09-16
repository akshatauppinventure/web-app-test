#!/usr/bin/env bash
# Verifies every artifact in checksums.txt against upstream (sha512 from the release .sha512 file
# and our recorded sha256), and that the Dockerfile's ADD --checksum matches. Used in CI (T11).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
status=0
while read -r name version url sha256 sha512; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  file="$tmp/$(basename "$url")"
  curl -fsSL --retry 3 -o "$file" "$url"
  curl -fsSL --retry 3 -o "$file.sha512" "$url.sha512"
  upstream="$(awk '{print $1}' "$file.sha512")"
  actual512="$(shasum -a 512 "$file" | awk '{print $1}')"
  actual256="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$upstream" != "$sha512" || "$actual512" != "$sha512" ]]; then
    echo "FAIL $name $version: sha512 mismatch (upstream=$upstream recorded=$sha512 actual=$actual512)"; status=1
  elif [[ "$actual256" != "$sha256" ]]; then
    echo "FAIL $name $version: sha256 mismatch (recorded=$sha256 actual=$actual256)"; status=1
  else
    echo "ok   $name $version"
  fi
  if ! grep -q -- "--checksum=sha256:$sha256" Dockerfile; then
    echo "FAIL Dockerfile does not ADD $name with --checksum=sha256:$sha256"; status=1
  fi
  if ! grep -q -- "APPLE_IDP_VERSION=$version" Dockerfile; then
    echo "FAIL Dockerfile version differs from checksums.txt ($version)"; status=1
  fi
done < checksums.txt
exit $status
