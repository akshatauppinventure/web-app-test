#!/usr/bin/env bash
# Provider-module contract (ADR-0002 §2, ADR-0025): every module under infra/tofu/<provider> must expose
# the same variables and outputs as the reference module (infra/tofu/upcloud), so the same tfvars and the
# same downstream steps (cloud-init render, peers.yaml, DuckDNS) work whichever provider is used.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT/infra/tofu"
fail() { echo "FAIL: $*" >&2; exit 1; }

REQUIRED_VARIABLES="zone template_name edge_plan core_plan admin_user admin_ssh_public_key
cloud_init_edge_path cloud_init_core_path private_network_cidr edge_private_ip core_private_ip
hostname_prefix labels wireguard_port"
REQUIRED_OUTPUTS="public_ipv4 private_ipv4 server_ids firewall_rule_counts"
MODULES=$(find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sed 's#^\./##' | sort)
[ -n "$MODULES" ] || fail "no modules under infra/tofu"

names() { # $1 = block kind (variable|output), $2 = module dir
  { grep -hoE "^$1 \"[a-z0-9_]+\"" "$2"/*.tf 2>/dev/null || true; } | sed -E 's/^[a-z]+ "([a-z0-9_]+)"/\1/' | sort -u
}

for m in $MODULES; do
  vars=$(names variable "$m"); outs=$(names output "$m")
  for v in $REQUIRED_VARIABLES; do grep -qx "$v" <<<"$vars" || fail "$m: missing variable \"$v\""; done
  for o in $REQUIRED_OUTPUTS; do grep -qx "$o" <<<"$outs" || fail "$m: missing output \"$o\""; done
  # First-boot-only user_data: host changes go through infra/host, never through re-applied user_data.
  grep -qE 'ignore_changes\s*=\s*\[user_data\]' "$m"/main.tf || fail "$m: main.tf must ignore_changes = [user_data]"
  # Credentials only from the environment (ADR-0016 §4): no credential attributes in provider blocks.
  ! grep -nE '^\s*(token|password|application_credential_secret|user_name|api_key)\s*=' "$m"/providers.tf \
    || fail "$m: providers.tf sets a credential attribute; use environment variables"
  # Same files in every module so the runbooks apply to all of them.
  for f in versions.tf providers.tf variables.tf main.tf network.tf firewall.tf outputs.tf \
           terraform.tfvars.example README.md .tflint.hcl .terraform.lock.hcl; do
    [ -f "$m/$f" ] || fail "$m: missing $f"
  done
  # Exact provider version + committed lock file (ADR-0020).
  grep -qE '^\s*version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' "$m"/versions.tf || fail "$m: versions.tf must pin an exact provider version"
  echo "ok: $m exposes the provider-module contract ($(wc -w <<<"$REQUIRED_VARIABLES" | tr -d ' ') variables, $(wc -w <<<"$REQUIRED_OUTPUTS" | tr -d ' ') outputs)"
done
# The tfvars example must be interchangeable between modules.
for m in $MODULES; do
  for v in admin_ssh_public_key cloud_init_edge_path cloud_init_core_path; do
    grep -q "^$v" "$m"/terraform.tfvars.example || fail "$m: terraform.tfvars.example must set $v"
  done
done
echo "ALL TOFU CONTRACT CHECKS PASSED ($(wc -w <<<"$MODULES" | tr -d ' ') module(s))"
