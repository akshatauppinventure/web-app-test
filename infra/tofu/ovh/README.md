# OpenTofu module: OVHcloud Public Cloud (ADR-0025; ADR-0002, ADR-0004, ADR-0014, ADR-0015)

Second provider module with the **same contract** as `infra/tofu/upcloud` (checked by `scripts/test/tofu-contract.sh`): same variable and output names, same `terraform.tfvars` keys, same downstream steps (cloud-init render, `peers.yaml`, DuckDNS). Use it for the OVHcloud POC after the UpCloud one.

Creates exactly: 2 instances (`<prefix>-edge` d2-4, `<prefix>-core` d2-8, newest public `Ubuntu 26.04` image, Ext-Net public interface + vRack private interface at 10.0.0.1/.2), 1 keypair, 1 private network + 1 subnet (VLAN 42, DHCP, no gateway), 2 security groups with 6 (edge: 80/443/51820, ICMP echo, private network, egress) and 4 (core) rules. Security groups are stateful, so no return-traffic rules; no IPv6 rules, so IPv6 is dropped as on UpCloud.

Target: **OVHcloud US** (Vint Hill, VA = `US-EAST-VA-1`), a separate legal entity from OVHcloud EU/CA with its own control panel (`us.ovhcloud.com`) and OpenStack endpoint `https://auth.cloud.ovh.us/v3`. Public Cloud instances, not the VPS range: VPS has no OpenTofu-driven install with cloud-init user data and no private network (ADR-0025).

## Usage (owner)

```bash
source ~/openrc.sh                                         # P15: OpenStack user openrc from the control panel, never in the repo
mkdir -p .tofu-rendered && infra/host/scripts/render-cloud-init.sh edge /path/edge.vars .tofu-rendered/edge.yaml   # PUBLIC_IF=ens3
infra/host/scripts/render-cloud-init.sh core /path/core.vars .tofu-rendered/core.yaml
cd infra/tofu/ovh && cp terraform.tfvars.example terraform.tfvars && $EDITOR terraform.tfvars   # or reuse the UpCloud one
tofu init && tofu plan -out plan.bin   # expect: 2 instances, 1 keypair, 1 network, 1 subnet, 2 security groups, 10 rules
tofu apply plan.bin                    # billing starts
tofu output                            # public/private IPs for DuckDNS (P8) and peers.yaml
```

Checks before the first apply on a new project: `openstack image list --public | grep Ubuntu` (26.04 present? otherwise set `template_name`), `openstack flavor list | grep -E 'd2-4|d2-8'` (available in the region? otherwise `b3-8`/`b3-16`), `openstack network list` shows `Ext-Net`, and the project has a vRack (Public Cloud → Network → Private network).

**State** is local (`terraform.tfstate`, gitignored) and committed only encrypted: `sops --encrypt terraform.tfstate > terraform.tfstate.sops` (rule in `.sops.yaml`); same for `terraform.tfvars`. Decrypt before the next `tofu` run.

`user_data` is applied on first boot only (`ignore_changes`); later host changes go through `infra/host` and re-provisioning. Cloud-init reads it from the config drive.

Differences from UpCloud worth knowing: the public interface is `ens3` (set `PUBLIC_IF` in the host vars); OVH images also create the `ubuntu` user with the keypair (cloud-init disables password login for all users); from 2026-10-01 OVH bills the public IPv4 and local storage of `b3-*` flavors separately.

## Checks

`make tofu-check` → for every module: `tofu fmt -check`, `tofu init -backend=false`, `tofu validate`, `tflint`, `trivy config`; then the contract test. No credentials needed. The provider lock file (`.terraform.lock.hcl`) is committed and pins the provider hashes for darwin_arm64, darwin_amd64 and linux_amd64.

Not yet run against a real OVH project (no account, P15): `tofu plan` output is the first thing to verify when the OVH POC starts.
