# Production hardening list

Work that is deliberately **not** done in the POC and must be done, or consciously re-decided, before
production. Each item names the decision it comes from. `PLAN.md` T25 turns the open items into GitHub
issues. Update the status column in the same PR that does the work.

Status values: `todo` · `in progress` · `done` · `dropped (reason)`.

| # | Item | Source | Status |
|---|---|---|---|
| 1 | Restore a VPN (WireGuard) for admin access and site-to-site traffic | ADR-0026, ADR-0015 | todo |
| 2 | Encrypt edge-to-core traffic (TLS or VPN) | ADR-0026 | todo |
| 3 | Lock SSH down: source allowlist, CrowdSec firewall bouncer | ADR-0026, ADR-0013 | todo |
| 4 | 3-tier topology (separate data server) | ADR-0003 | todo |
| 5 | Point-in-time recovery backups for PostgreSQL | ADR-0021, ADR-0009 | todo |
| 6 | Cloudflare edge proxy | ADR-0023 | todo |
| 7 | Real domain and Apple login | ADR-0022, ADR-0010 | todo |
| 8 | Full observability stack | ADR-0024 | todo |
| 9 | Outbound (egress) filtering on the hosts | ADR-0014 | todo |
| 10 | Hardened base images (DHI) | ADR-0019, ADR-0020 | todo |
| 11 | Secrets manager evaluation (Vault / OpenBao) | ADR-0016 | todo |

## 1. Restore a VPN (WireGuard) for admin access and site-to-site traffic

**Why it matters.** Without a VPN, SSH is reachable from the internet on both servers, and admin UIs depend on SSH port forwarding. A VPN removes every admin service from the internet: only 80/443 on edge stay public, plus one UDP port that does not answer unauthenticated packets.

**What the POC does instead (ADR-0026).** Key-only SSH on the public interface, rate-limited, with optional source allowlists (`ADMIN_SSH_CIDRS`, `admin_ssh_cidrs`). Portainer and the Keycloak admin console are reached through `ssh -L`.

**Starting point.** ADR-0015 describes the full design: kernel WireGuard, `wg0` on UDP 51820, `10.10.0.0/24`, a pre-shared key per peer pair, and sshd, Portainer, Keycloak and FastAPI bound to WireGuard addresses. The implementation was removed in the PR that added ADR-0026. The last `main` commit that contains it is `fe89dd9`, and `git show fe89dd9:<path>` recovers any file:

- `infra/host/wireguard/` (interface templates, `peers.yaml`), `infra/host/scripts/wg-apply-psks.sh`, `infra/host/scripts/wg-rotate-key.sh`
- `scripts/host/finalize-wireguard.sh`, `scripts/host/render-laptop-wg.sh`, `scripts/test/host-bootstrap.sh`
- the WireGuard parts of the cloud-init templates, nftables rulesets, `docker-user-rules.sh`, `healthcheck.sh`, both OpenTofu modules and the secrets tooling

**Lessons from T20 to fix before re-enabling.**
- sshd listened on the WireGuard address only, so a tunnel that never came up left the hosts reachable only through the provider console. Keep a fallback, for example SSH from one fixed admin address, until the tunnel is verified.
- First boot needs valid peer keys. The POC rendered a bootstrap key pair on the laptop and rotated it on first contact, which was the most fragile step. Evaluate NetBird, Headscale or Tailscale here too, because ADR-0015 asked for a re-evaluation when the team grows.
- UpCloud trial accounts have a fixed stateless firewall that blocks WireGuard, so use a funded account.

**Done when.** SSH, Portainer and the Keycloak admin console are unreachable from the public internet. `nmap -Pn -p-` against both public IPs shows only 80/443 on edge. Edge-to-core traffic runs inside the tunnel, and the health check alerts on a stale handshake.

## 2. Encrypt edge-to-core traffic

The POC sends plain HTTP from Traefik and Next.js on edge to Keycloak and FastAPI on core over the provider's private network. That includes OAuth codes, tokens and the BFF client secret. Either item 1's tunnel or TLS between the tiers with an internal CA fixes it. With a 3-tier topology (item 4), PostgreSQL connections need TLS too.

## 3. Lock SSH down

Until item 1 is done, narrow `ADMIN_SSH_CIDRS` and `admin_ssh_cidrs` from `0.0.0.0/0` to the admin addresses. Add the CrowdSec firewall bouncer (nftables) so sshd brute-force decisions block at the host, not only at the HTTP layer. Core has no CrowdSec engine at all, so it needs one too, or its auth log must be shipped to edge.

## 4–11. Deferred ADR follow-ups

These were out of scope for the POC from the start (`PLAN.md` § Summary). Each ADR's "Follow-ups" section has the detail.
