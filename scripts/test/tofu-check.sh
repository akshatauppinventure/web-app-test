#!/usr/bin/env bash
# Static checks for every module under infra/tofu (PLAN T18, T26): fmt, init (no backend), validate,
# tflint, trivy config; then the provider-module contract test. Usage: tofu-check.sh [module ...]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
if [ $# -gt 0 ]; then MODULES="$*"; else MODULES=$(find "$ROOT/infra/tofu" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sort); fi
for m in $MODULES; do
  cd "$ROOT/infra/tofu/$m" || fail "no module infra/tofu/$m"
  echo "== infra/tofu/$m"
  tofu fmt -check -recursive >/dev/null || fail "$m: tofu fmt -check (run: tofu fmt -recursive infra/tofu/$m)"
  echo "ok: tofu fmt"
  tofu init -backend=false -input=false >/dev/null || fail "$m: tofu init"
  tofu validate >/dev/null || fail "$m: tofu validate"
  echo "ok: tofu init + validate"
  tflint --init >/dev/null 2>&1 || true
  tflint --config .tflint.hcl || fail "$m: tflint"
  echo "ok: tflint"
  trivy config --exit-code 1 --severity HIGH,CRITICAL --quiet . || fail "$m: trivy config"
  echo "ok: trivy config (no HIGH/CRITICAL misconfigurations)"
done
"$ROOT/scripts/test/tofu-contract.sh"
echo "ALL TOFU CHECKS PASSED"
