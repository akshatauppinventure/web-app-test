# ADR-0025: OVHcloud Public Cloud as the second provider module

- **Status:** Accepted (2026-09-16)
- **Date:** 2026-09-16
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0004, ADR-0014, ADR-0015, ADR-0016, ADR-0020

## Context

- ADR-0002 hosts the POC on UpCloud `us-nyc1` and keeps the design provider-portable, naming OVHcloud (Vint Hill, VA) as the likely next provider with "one small module per provider (`infra/tofu/upcloud` now, `infra/tofu/ovh` later)".
- On 2026-09-16 the owner asked for the OVHcloud OpenTofu module now, to repeat the POC on OVHcloud once the UpCloud tests are finished.
- ADR-0002 compared **OVHcloud VPS**. Findings when writing the module (2026-09-16):
  - The VPS range cannot be provisioned the way `infra/host` expects: the OVH API can order a VPS and reinstall it with an SSH key, but takes no cloud-init user data, and VPS have no private network. Every host-side artefact (cloud-init templates, nftables, WireGuard, Docker, timers) would need a second delivery path.
  - **OVHcloud Public Cloud** instances are OpenStack: cloud-init user data, private networks (vRack, free, delivered with new projects), stateful security groups, and a mature OpenTofu provider (`terraform-provider-openstack/openstack`). Discovery flavors `d2-4` (2 vCPU / 4 GB, $14.18/month) and `d2-8` (4 vCPU / 8 GB, $25.53/month) match ADR-0002 §3; General Purpose `b3-8`/`b3-16` are the upgrade path. From 2026-10-01 public IPv4 and local storage on `b3-*` are billed separately.
  - Vint Hill is served by **OVHcloud US**, a separate entity (`us.ovhcloud.com`, OpenStack endpoint `https://auth.cloud.ovh.us/v3`, region `US-EAST-VA-1`) with its own account and billing.
  - Ubuntu 26.04 was not confirmed in OVH's public image catalog at the time of writing; the module selects the image by regex so the owner can fall back to 24.04 (ADR-0004 fallback) without code changes.

## Decision

1. **We will target OVHcloud Public Cloud (OpenStack) instances in `US-EAST-VA-1`**, not OVH VPS, so that cloud-init, WireGuard over a private network and the provider firewall work exactly as on UpCloud.
2. **We will keep one module per provider with an identical contract.** `infra/tofu/ovh` exposes the same variable and output names as `infra/tofu/upcloud` (`zone`, `template_name`, `edge_plan`, `core_plan`, `admin_user`, `admin_ssh_public_key`, `cloud_init_*_path`, `private_network_cidr`, `*_private_ip`, `hostname_prefix`, `labels`; outputs `public_ipv4`, `private_ipv4`, `server_ids`, `firewall_rule_counts`), accepts the same `terraform.tfvars`, and ignores `user_data` after first boot. `scripts/test/tofu-contract.sh` enforces this in CI for every module under `infra/tofu/`. Provider-specific extras are allowed (`private_network_vlan_id`, `public_network_name`).
3. **Only the OpenStack provider is used**, with credentials from the environment (`openrc` file or application credential, ADR-0016 §4). The `ovh/ovh` provider (OVH API keys) is not needed and not added.
4. **Networking mirrors UpCloud:** Ext-Net public IPv4 as the default route; a vRack private network (`provider:network_type = vrack`, VLAN 42, DHCP, no gateway) with fixed 10.0.0.1/.2 as the WireGuard transport; security groups with default rules deleted, IPv4-only rules (edge 80/443/51820, core 51820, ICMP echo, private network, egress), no IPv6 rules.
5. **Migration is a repeat of Phase 4 on the other provider,** not a code change: render cloud-init with `PUBLIC_IF=ens3`, `tofu apply` in `infra/tofu/ovh`, update `peers.yaml` and DuckDNS, push secrets. Nothing under `infra/host`, `infra/stacks` or the images changes.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| OVHcloud VPS via the `ovh/ovh` provider (`ovh_vps`) | No cloud-init user data on install, no private network: the host baseline (ADR-0014/0015/0017) would need a second, SSH-driven delivery path. |
| One generic module with a `provider` switch | OpenTofu cannot select a provider dynamically; conditional resources across two providers make both harder to read. Two small modules with a tested contract are simpler. |
| Add the `ovh/ovh` provider for the vRack/private network | The OpenStack API creates vRack networks directly (`provider:network_type = vrack`); a second credential set adds prerequisites without benefit. |
| WireGuard over public IPs only (no private network) | Allowed by ADR-0002 §2, but public IPs are unknown before `apply`, which breaks the pre-rendered cloud-init; the vRack network keeps the fixed-address flow identical to UpCloud. |

## Consequences

**Positive**
- The OVH POC needs no changes outside `infra/tofu/ovh` and the owner's variables; the contract test keeps both modules aligned as they evolve.
- Stateful security groups remove the return-traffic rules and the 20-rule concern of the UpCloud module.

**Negative / risks**
- Not yet validated against a real OVH project (no account): image name, flavor availability in `US-EAST-VA-1` and vRack delivery are checked by the owner before the first `tofu apply` (module README).
- Two provider lock files and two sets of provider updates for Renovate.
- Public Cloud costs more than OVH VPS (≈ $40/month for d2-4 + d2-8, similar to UpCloud) and, from October 2026, IPv4 is billed separately on `b3-*`.

**Follow-ups**
- T26 (module, this ADR). When the OVH POC starts: owner prerequisite P15, then T20–T23 repeated with `infra/tofu/ovh`.
- Object storage for backups on OVH (ADR-0021 counterpart) is decided when the OVH POC starts.

## References

- https://docs.ovhcloud.com/en/guides/public-cloud/network-services/vrack (vRack private network via OpenStack, `provider:network_type vrack`)
- https://us.ovhcloud.com/public-cloud/prices/ (flavors d2-4, d2-8, b3-8, b3-16; IPv4 billing change 2026-10-01)
- https://support.us.ovhcloud.com/hc/en-us/articles/19912021174291-Using-service-accounts-to-connect-to-OpenStack (`OS_AUTH_URL=https://auth.cloud.ovh.us/v3`)
- https://registry.terraform.io/providers/terraform-provider-openstack/openstack/3.4.0
