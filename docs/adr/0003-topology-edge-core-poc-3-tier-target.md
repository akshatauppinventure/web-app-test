# ADR-0003: Edge/core 2-VPS topology for the POC, 3-tier for production

- **Status:** Accepted (2026-09-15); amended by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md) (tunnel hops replaced by the provider private network)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0006, ADR-0010, ADR-0011, ADR-0014, ADR-0015

## Context

The POC has two VPS. An earlier draft put Traefik, Next.js, FastAPI and Keycloak on the internet-facing server (VPS-A) and only PostgreSQL on VPS-B. Review showed that **host separation only helps if the secrets also live on the protected host.**

| If an attacker gets root on VPS-A | Draft (API + Keycloak on A) | Edge/core (this ADR) |
|---|---|---|
| Database credentials (app + keycloak) | Yes: full read/write to all data | **No:** none exist on A |
| Keycloak signing keys (in the Keycloak DB) → forge any user's token | Yes | **No** |
| Keycloak admin → create admins, change login settings | Yes | **No** |
| Portainer control plane → take over the other server | No | **No** (Server on B) |
| What remains exposed | Everything | Next.js OIDC client secret and session key, TLS keys, tokens of users active *during* the compromise, the ability to serve malicious JavaScript. **Limited to individual users, not a bulk data dump.** |

## Decision

We will use an **edge/core split** for the POC. Both servers are in UpCloud us-nyc1.

```
Internet ── TCP 80/443 (+ UDP 51820 WireGuard) ──►
┌ VPS-A "edge"  2 vCPU / 4 GB ──────────────────────────────┐
│ Traefik (TLS, CrowdSec bouncer + AppSec WAF, rate limits) │
│   /                      → Next.js (login handled         │
│                             server-side; no DB creds)     │
│   /auth/realms, /auth/resources → Keycloak on B (via WG)  │
│ CrowdSec engine · Portainer Agent                         │
└─────────────┬─────────────────────────────────────────────┘
              │ WireGuard site-to-site 10.10.0.1 ⇄ 10.10.0.2
              │ B accepts from A only: Keycloak :8080, FastAPI :8000
┌─────────────▼ VPS-B "core"  4 vCPU / 8 GB ────────────────┐
│ Keycloak · FastAPI · PostgreSQL (internal Docker network) │
│ Portainer Server (WireGuard IP only) · restic backup      │
│ timer                                                     │
└───────────────────────────────────────────────────────────┘
No public TCP ports on B. Admin laptop reaches both servers over WireGuard (10.10.0.10).
```

**Rules:**
1. **VPS-A holds no database credentials, no Keycloak admin credentials and no backup keys.** This is tested in verification by searching A's files and volumes.
2. **FastAPI is never routed publicly.** Only the Next.js server calls it, over WireGuard.
3. **Only two public route groups exist:** `/` (Next.js) and `/auth/realms/*` + `/auth/resources/*` (Keycloak).
4. **PostgreSQL is never published** outside B's internal Docker network.
5. **The Portainer Server runs on B;** A runs only an Agent (ADR-0006).
6. **Short-lived tokens:** access tokens last 5 minutes and refresh tokens rotate (ADR-0010/0011). This limits what a compromised A can harvest.

**Production target (to be recorded as its own ADR before production): three servers.**
- VPS-A **edge**: Traefik, CrowdSec, Next.js.
- VPS-B **app**: Keycloak, FastAPI.
- VPS-C **data**: PostgreSQL, backups, Portainer Server. Port 5432 accepts connections only from VPS-B over WireGuard, with TLS.
- Moving there means moving the Postgres container and its volume to VPS-C and changing one connection host. Services already talk to each other by address over WireGuard.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Draft layout (API + Keycloak on edge) | A compromise of A exposes all data and lets the attacker forge identities |
| 3 VPS in the POC | Best isolation, but +$12–24/month and more operational work; the owner chose 2 servers for the POC |
| Everything on one VPS | No blast-radius separation at all |
| Next.js on B as well (A = proxy only) | Next.js server code is directly internet-facing through the proxy anyway; moving it adds WireGuard latency to every page without removing its exposure |

## Consequences

**Positive**
- A compromise of the internet-facing host no longer means a full data breach or identity forgery.
- A clean migration path to three tiers.

**Negative / risks**
- **App-level exploits are not stopped by host separation.** A FastAPI authorization bug, SQL injection or Keycloak CVE works on whatever host the service runs. Mitigations: object-level permission checks, least-privilege DB roles plus Row-Level Security (ADR-0009/0011), fast patching (ADR-0020), container hardening (ADR-0005).
- On VPS-B, internet-reachable code (Keycloak and FastAPI, via A) runs next to the database. A container escape on B reaches the data. This is accepted for the POC and fixed by the 3-tier target.
- Keycloak traffic takes an extra WireGuard hop (A→B). The latency is negligible within one data center.

**Follow-ups**
- Before production: an ADR for the 3-tier layout plus outbound traffic restrictions on B/C.

## References

- Research plan rev 2, §2 (blast-radius analysis)
