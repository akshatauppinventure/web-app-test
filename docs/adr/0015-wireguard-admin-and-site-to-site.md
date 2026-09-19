# ADR-0015: WireGuard for admin access and site-to-site traffic

- **Status:** Superseded by ADR-0026 (2026-09-19; WireGuard removed from the POC, restoring it is production-hardening item 1)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0003, ADR-0006, ADR-0014

## Context

We need:
1. **Admin access** (SSH, Portainer UI, Keycloak admin console) that isn't exposed to the internet.
2. **Encrypted traffic between the servers** (Traefik → Keycloak, Next.js → FastAPI, Portainer Server → Agent) that works the same on UpCloud (SDN private network available) and on OVH VPS (no private network).

Options researched (2026): plain WireGuard, Tailscale, Headscale, NetBird. All use the WireGuard data plane.
- **Tailscale:** its coordination server is SaaS.
- **Headscale:** self-hosted control plane, CLI-focused.
- **NetBird:** fully self-hostable with a web UI, but needs its own management host.

A WireGuard endpoint **doesn't respond to unauthenticated packets**, so its UDP port is effectively invisible to scanners.

## Decision

We will use **plain kernel WireGuard** (`wireguard-tools`, host-native, ADR-0005) with one interface `wg0` per device on UDP **51820**.

1. **Addressing (`10.10.0.0/24`):**

   | Peer | WG IP | Endpoint used by others |
   |---|---|---|
   | VPS-A (edge) | `10.10.0.1/32` | B uses A's **UpCloud SDN private IP**; admins use A's public IP |
   | VPS-B (core) | `10.10.0.2/32` | A uses B's **SDN private IP**; admins use B's public IP |
   | Admin laptops | `10.10.0.10`–`10.10.0.19` | Roaming (no endpoint); `PersistentKeepalive = 25` |

   On a provider without private networking (e.g. OVH VPS), A↔B endpoints switch to public IPs. This is the only change.
2. **Peers and routing:**
   - A ↔ B peer each other (`AllowedIPs` = the peer's `/32` only).
   - Each admin laptop has **two peers** (A and B), each with `AllowedIPs` = that server's `/32`. Split tunnel: only `10.10.0.1/32` and `10.10.0.2/32` go through the VPN.
   - Servers list admin peers with `AllowedIPs` = the laptop's `/32`.
   - **No IP forwarding between peers:** admin-to-A traffic never transits B.
3. **Keys:**
   - Each device generates its own private key locally (`wg genkey`, mode 0600). **Private keys never leave the device and are never committed.**
   - A **PresharedKey per peer pair** adds a symmetric layer (post-quantum hardening).
   - Public keys and the peer map are committed in `infra/host/wireguard/peers.yaml`; PSKs are stored as SOPS secrets (ADR-0016).
   - **Rotation:** every 6 months, and immediately on device loss or staff change (remove the peer from both servers).
4. **Services bound to WireGuard:**
   - `sshd` (`ListenAddress 10.10.0.x`).
   - Portainer Server (B) and Agent (A).
   - Keycloak (B:8080) and FastAPI (B:8000).
   - Access per source is further restricted in `DOCKER-USER` / nftables (ADR-0014).
5. **Break-glass access:** the UpCloud web console (serial/VNC) with the admin's local password (stored in the password manager; SSH password login stays disabled). Documented in the runbook.
6. **Ordering and resilience:**
   - `wg-quick@wg0` enabled at boot, before Docker (the `After=`/`Wants=` on docker.service makes WireGuard IP binds succeed).
   - A watchdog check of the A↔B handshake age is part of health monitoring (ADR-0024).

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Tailscale (free tier) | Easiest and very popular, but the control plane is proprietary SaaS; the owner prefers FOSS. Good option if the team grows. |
| Headscale | Self-hosted Tailscale control plane; an extra service to run and secure for 2 servers + 1 admin |
| NetBird (self-hosted) | Nice UI/SSO, but needs a management server; overkill now |
| Public SSH with keys + CrowdSec | SSH remains an internet-visible target; the VPN-only approach removes it |
| UpCloud SDN private network without WireGuard | Not portable to OVH VPS; plaintext on the provider network |

## Consequences

**Positive**
- Zero internet-visible admin services; encrypted, authenticated cross-server traffic; identical design across providers; no extra services to run.

**Negative / risks**
- Manual key and peer management (acceptable for ≤10 peers).
- If WireGuard breaks, only the provider console is available for access. Mitigated by host-native setup and boot ordering.
- Services bound to WireGuard IPs fail to start if `wg0` is down. Systemd ordering handles this.

**Follow-ups**
- Re-evaluate NetBird/Headscale/Tailscale when there are >3 admins or when SSO-based device access is needed.

## References

- https://www.wireguard.com/
- https://www.wireguard.com/quickstart/
- https://serverside.com/blog/wireguard-vs-tailscale-vs-headscale-vs-netbird
- https://www.portainer.io/blog/should-you-expose-portainer-or-agent-to-the-internet
