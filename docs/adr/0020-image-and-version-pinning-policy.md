# ADR-0020: Image and version pinning policy

- **Status:** Accepted (2026-09-15); WireGuard references superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0004 to ADR-0013, ADR-0017, ADR-0019

## Context

The owner wants the **latest** base images and software versions. "Latest" must not mean floating `latest` tags, which make deployments unreproducible and let an upstream change or hijack slip into production silently. We need current versions, reproducible builds and fast security patching at the same time.

## Decision

1. **Pinning rules:**
   - Container images: `name:<exact-version>[-variant]@sha256:<digest>` in every Dockerfile `FROM` and compose `image:`. **Never `latest`** or floating major/minor tags without a digest.
   - Application dependencies: exact versions via lockfiles (`pnpm-lock.yaml`, `uv.lock`).
   - GitHub Actions: full commit SHAs (ADR-0019).
   - Host packages: distro LTS repos + Docker's official apt repo; security updates automatic (ADR-0004).
2. **Automated updates: Renovate** (`renovate.json`) covers Dockerfiles, compose files, npm/pnpm, uv/PEP 621, GitHub Actions, and custom regex managers (Keycloak Apple extension, Traefik plugin versions + checksums).
   - Groups: patch/minor per ecosystem weekly; majors as individual PRs; security updates immediately, without cooldown.
   - `minimumReleaseAge: 3 days` for non-security updates (ADR-0019).
3. **Patch SLAs** (from public disclosure / fix availability):

   | Severity | Internet-facing (Traefik, Next.js, Keycloak, CrowdSec) | Internal (FastAPI deps, Postgres, Portainer) |
   |---|---|---|
   | Critical / known exploited | **≤ 48 hours** | ≤ 72 hours |
   | High | ≤ 7 days | ≤ 14 days |
   | Medium / Low | Next weekly batch | Next weekly batch |

4. **Version baseline at 2026-09-14** (reviewed at implementation time):

   | Component | Version / tag | Track and upgrade rule |
   |---|---|---|
   | Ubuntu Server | 26.04 LTS | LTS only (fallback 24.04) |
   | Docker Engine / Compose | 29.7.x / v5.5.x | Latest stable |
   | Node.js (frontend image) | `node:24-alpine` | Active LTS; move to **Node 26 after it becomes LTS (Oct 2026)** |
   | Next.js / React | 16.3.4 / 19.2.x | Latest 16.x; **floor ≥ 16.3.3** |
   | Python (backend image) | `python:3.14-slim-trixie` (3.14.7) | Latest stable minor after ecosystem wheels are ready (3.15 evaluated after Oct 2026) |
   | FastAPI | 0.141.x | Latest, exact pin |
   | PostgreSQL | `postgres:18.6-trixie` | Latest 18.x minor; **PG 19 only from 19.1+ via a new ADR** |
   | Keycloak | 26.7.2 | **Latest release** (no LTS upstream); within 2 weeks for minors |
   | Keycloak Apple extension | klausbetz 1.17.x (≥ Keycloak 26.5) | Latest compatible; smoke test on upgrade |
   | Traefik | v3.7.13 | Latest 3.x |
   | CrowdSec | latest stable | Latest |
   | Portainer CE / Agent | 2.45 LTS | LTS to LTS (~every 6 months) + patches |
   | WireGuard | distro kernel module / `wireguard-tools` | Distro updates |
   | restic | distro or official binary | Latest stable |

5. **Base image source:**
   - **Official Docker Hub images** (docker-library / upstream) for the POC.
   - **Docker Hardened Images** (free, Apache-2.0 since Dec 2025; rootless, minimal, VEX) are evaluated as a **production-hardening step** for the runtime stages of frontend, backend and Postgres.
6. **End-of-life guard:** CI checks (e.g. via endoflife.date data) warn when a pinned major version is within 90 days of EOL.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Floating tags (`latest`, `24-alpine` without digest) | Non-reproducible; silent upstream changes; exposure to hijacked tags |
| Manual updates only | Patches get missed; can't meet SLAs |
| Dependabot version updates | Good, but Renovate handles Dockerfile digests, compose, regex managers and grouping more flexibly; Dependabot alerts remain on |
| Docker Hardened Images from day one | Adds registry auth and debugging friction to the POC; planned for production |

## Consequences

**Positive**
- Reproducible builds and deploys; always-current versions through reviewable PRs; clear patch timelines.

**Negative / risks**
- A steady stream of update PRs needs regular review time.
- Pinned digests need Renovate to track upstream rebuilds.

**Follow-ups**
- Set up Renovate when the repo is created. Schedule the Node 26 and Portainer next-LTS upgrades.

## References

- https://docs.renovatebot.com/docker/#digest-pinning
- https://endoflife.date/
- https://nextjs.org/blog/august-2026-security-release
- https://www.keycloak.org/2026/08/keycloak-2672-released
- https://docs.portainer.io/start/lifecycle
- https://www.docker.com/blog/docker-hardened-images-for-every-developer/
