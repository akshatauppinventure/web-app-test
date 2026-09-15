# ADR-0002: Hosting on UpCloud US-NYC1 with a provider-portable design

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0014, ADR-0015, ADR-0021

## Context

- **Scope:** a POC on two VPS. Production readiness comes later.
- **Region:** USA, preferably US East.
- **Providers evaluated:** UpCloud and OVHcloud. The owner may move to OVHcloud or another provider later.

Research findings (2026-09-13/14):

| Criterion | UpCloud | OVHcloud VPS |
|---|---|---|
| US East location | **us-nyc1 (New York)**. Other US zones: us-chi1 (Chicago), us-sjo1 (San Jose). No Virginia zone. | **Vint Hill, Virginia** (US-East); also Hillsboro, Oregon |
| Private network between servers | Free SDN Private Network + SDN Router | **None on the VPS range.** vRack is only for Public Cloud and dedicated servers. |
| Provider firewall | Included, per server, up to 1000 rules. The classic firewall is stateless; SDN firewall rules are stateful. | Edge Network Firewall: 20 rules per IP, filter-only |
| DDoS protection | Mitigation inside their network | Always-on, Tbps-class anti-DDoS (a strength) |
| SLA / support | 100% SLA (50× compensation); reviews praise fast support | 99.99%; reviews consistently cite slow support |
| Approx. cost (4 vCPU/8 GB + 2 vCPU/4 GB) | ≈ $40–50/month | ≈ $15–20/month (after the March 2026 ~30% increase) |
| Object storage in the US | Managed Object Storage **US-1, located in Chicago**, reachable from NYC1 | Available |
| Ubuntu 26.04 LTS image | Available | Was "coming in weeks" as of May 2026 |

## Decision

1. **Provider and region.**
   - We will host the POC on **UpCloud in `us-nyc1` (New York)**.
   - Backups go to **UpCloud Managed Object Storage US-1 (Chicago)**, a different data center (see ADR-0021).
2. **We will keep the design provider-portable:**
   - **Cross-server traffic runs through WireGuard** (ADR-0015), never directly over the provider's private network. On UpCloud the tunnel runs over the SDN private network; on a provider without one, it runs over the public IPs. Nothing else changes.
   - **The host firewall (nftables) is the source of truth** (ADR-0014). The provider firewall repeats a *small* ruleset that fits OVH's 20-rules-per-IP limit.
   - **Servers are provisioned with cloud-init + OpenTofu,** with one small module per provider (`infra/tofu/upcloud` now, `infra/tofu/ovh` later).
   - **No managed services that lock us in:** no managed database, load balancer, container registry or secrets service from the provider.
3. **Plans.**
   - VPS-A "edge": **2 vCPU / 4 GB**.
   - VPS-B "core": **4 vCPU / 8 GB** (Keycloak's JVM, PostgreSQL, FastAPI, Portainer).
   - Use General Purpose or Cloud Native plans available in us-nyc1. Confirm current prices on UpCloud's pricing page at provisioning time.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| OVHcloud VPS, Vint Hill VA | Much cheaper and has stronger always-on anti-DDoS, but no private networking on VPS, a limited edge firewall and weaker support reviews. Remains the primary migration target; the portable design keeps the move cheap. |
| OVHcloud Public Cloud instances | Have vRack private networking, but cost more and are more complex than VPS for a POC |
| UpCloud us-chi1 / us-sjo1 | Not US East |
| Hyperscalers (AWS/Azure/GCP) | Out of scope (VPS-based POC requested); higher cost and complexity |

## Consequences

**Positive**
- A private network and a provider-level firewall at no extra cost, plus good support for a security-focused POC.
- Moving to OVH (Vint Hill, VA) needs only a new OpenTofu module and DNS changes.

**Negative / risks**
- About 2–3× the monthly cost of OVH.
- Traffic between NYC and Chicago for backups adds latency (irrelevant for nightly jobs).
- UpCloud's object storage is at the same provider, so it doesn't protect against losing the provider account. A second-provider copy is a production follow-up.
- UpCloud's classic firewall is stateless. Rules must explicitly allow return traffic, or SDN stateful rules must be used (validated during provisioning).

**Follow-ups**
- Confirm plan availability and prices in us-nyc1 when provisioning.
- Production: evaluate a second backup provider and the OVH migration path again.

## References

- https://upcloud.com/docs/getting-started/locations/
- https://upcloud.com/docs/products/cloud-servers/availability/
- https://upcloud.com/docs/products/managed-object-storage/availability/
- https://upcloud.com/docs/products/networking/firewall/
- https://getdeploying.com/ovh-vs-upcloud
- https://www.vpsbenchmarks.com/compare/ovhcloud_vs_upcloud
- https://www.ovhcloud.com/en/vps/
- https://www.ovhcloud.com/en/network/vrack/
- https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/firewall-network
- https://us.ovhcloud.com/press/press-releases/2023/ovhcloud-us-celebrates-five-year-anniversary-of-vint-hill-and-hillsboro-data-centers/
