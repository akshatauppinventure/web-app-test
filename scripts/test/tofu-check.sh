#!/usr/bin/env bash
# Static checks for infra/tofu/upcloud (PLAN T18): fmt, init (no backend), validate, tflint, trivy config.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT/infra/tofu/upcloud"
fail() { echo "FAIL: $*" >&2; exit 1; }
tofu fmt -check -recursive >/dev/null || fail "tofu fmt -check (run: tofu fmt -recursive infra/tofu/upcloud)"
echo "ok: tofu fmt"
tofu init -backend=false -input=false >/dev/null || fail "tofu init"
tofu validate >/dev/null || fail "tofu validate"
echo "ok: tofu init + validate"
tflint --init >/dev/null 2>&1 || true
tflint --config .tflint.hcl || fail "tflint"
echo "ok: tflint"
trivy config --exit-code 1 --severity HIGH,CRITICAL --quiet . || fail "trivy config"
echo "ok: trivy config (no HIGH/CRITICAL misconfigurations)"
echo "ALL TOFU CHECKS PASSED"
