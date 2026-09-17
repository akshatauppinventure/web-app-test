# OpenTofu module: UpCloud (ADR-0002, ADR-0004, ADR-0014, ADR-0015)

Creates exactly: 2 servers (`<prefix>-edge` 2xCPU-4GB, `<prefix>-core` 4xCPU-8GB, Ubuntu 26.04 template, public IPv4 only, private SDN interface), 1 private network + 1 router, and one stateless firewall ruleset per server (edge: 80/443/51820 + return traffic; core: 51820 + return traffic; IPv6 dropped; default drop in / accept out; 12–14 rules).

## Usage (owner, T20)

```bash
export UPCLOUD_TOKEN="$(cat ~/.config/upcloud/token)"   # P6: private file outside the repo, mode 600
mkdir -p .tofu-rendered && infra/host/scripts/render-cloud-init.sh edge /path/edge.vars .tofu-rendered/edge.yaml
infra/host/scripts/render-cloud-init.sh core /path/core.vars .tofu-rendered/core.yaml
cd infra/tofu/upcloud && cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars
tofu init && tofu plan -out plan.bin          # expect: 2 servers, 1 network, 1 router, 2 firewall rulesets
tofu apply plan.bin                           # billing starts
tofu output                                   # public/private IPs for DuckDNS (P8) and peers.yaml
```

**State** is local (`terraform.tfstate`, gitignored) and committed only encrypted: `sops --encrypt terraform.tfstate > terraform.tfstate.sops` (rule in `.sops.yaml`); same for `terraform.tfvars`. Decrypt before the next `tofu` run.

`user_data` is applied on first boot only (`ignore_changes`); later host changes go through `infra/host` and re-provisioning.

## Checks

`make tofu-check` → `tofu fmt -check`, `tofu init -backend=false`, `tofu validate`, `tflint`, `trivy config`. No credentials needed. The provider lock file (`.terraform.lock.hcl`) is committed and pins the provider hash.
