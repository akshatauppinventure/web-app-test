# ADR-0005: Docker Compose for services; host-native security components

- **Status:** Accepted (2026-09-15); access model superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0006, ADR-0009, ADR-0014, ADR-0015, ADR-0020

## Context

The owner wants to deploy as Docker containers as much as possible, and asked which components should *not* be containerized. The POC spans two hosts, is managed through Portainer, and doesn't need clustering.

Versions as of 2026-09-14:
- **Docker Engine 29.7.x.** The containerd image store is the default; the nftables firewall backend is still experimental.
- **Docker Compose v5.5.x.**

## Decision

1. **Orchestration: Docker Engine + Docker Compose (standalone, one Compose project per host).**
   - `infra/stacks/edge/compose.yaml` (VPS-A)
   - `infra/stacks/core/compose.yaml` (VPS-B)
   - No Swarm, no Kubernetes.
   - Keep Docker's default **iptables** firewall backend. Don't enable experimental nftables support.
2. **What runs where:**

   | Component | Runs as | Reason |
   |---|---|---|
   | Traefik, CrowdSec, Next.js, FastAPI, Keycloak, Portainer Server/Agent | **Container** | Rebuildable, versioned, deployed via GitOps (ADR-0018) |
   | Alembic migrations | **One-shot container** (`migrate` service) before FastAPI starts | Migrations run with the dedicated migrator role, and the same image as the backend |
   | PostgreSQL 18 | **Container** for the POC (ADR-0009) | Standard and adequate on a single host. Native install to be reconsidered for production. |
   | WireGuard | **Host (kernel)** | Admin and site-to-site lifeline; must work when Docker or Portainer is broken |
   | nftables firewall, sshd, unattended-upgrades, auditd, AppArmor | **Host** | They protect the host; putting them in containers defeats the purpose |
   | Backup schedule (restic + `pg_dump`) | **Host systemd timer** | Survives Docker problems; auditable; keeps backup credentials out of containers |
   | Docker Engine | **Host** | — |

3. **Container hardening baseline** (every service unless an exception is documented in the compose file):
   - Runs as a **non-root user** (numeric UID/GID).
   - `read_only: true` root filesystem, with `tmpfs` for writable paths.
   - `cap_drop: [ALL]`, adding back only what's needed (e.g. Traefik: `NET_BIND_SERVICE`).
   - `security_opt: ["no-new-privileges:true"]` and Docker's default seccomp and AppArmor profiles.
   - `mem_limit` / `cpus` (or `deploy.resources.limits`) and `pids_limit`.
   - A `healthcheck` on every long-running service; `depends_on` with `condition: service_healthy` or `service_completed_successfully`.
   - `restart: unless-stopped`.
   - **No Docker socket mounts** except Portainer Server/Agent (ADR-0006).
   - **No `privileged: true`, no `network_mode: host`.**
   - User-defined networks only. Networks that must not reach outside are marked `internal: true` (e.g. `db` on VPS-B).
   - Images referenced as `name:version@sha256:digest` (ADR-0020).

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Kubernetes (k3s, etc.) | Overkill for two nodes and a hello-world app; a much larger attack surface and more operational work |
| Docker Swarm | Adds cluster state and overlay networking across hosts with little benefit; declining community |
| Podman (rootless) + Quadlet | Good security properties, but Portainer and most Compose tooling target Docker; weaker fit with the requested Portainer |
| Everything containerized, including WireGuard and firewall | Loses the management lifeline when Docker fails; containerized firewalls need privileged/host networking |
| Rootless Docker / userns-remap | Extra protection, but complicates Portainer, volume permissions and binding low ports; reconsider for production |

## Consequences

**Positive**
- Simple, well-understood tooling; a consistent hardening baseline; the host keeps a working security layer independent of containers.

**Negative / risks**
- No automatic failover or rescheduling across hosts. Acceptable for the POC.
- Docker's iptables management interacts with host firewalls (mitigated in ADR-0014).

**Follow-ups**
- Production: evaluate userns-remap/rootless mode, and native PostgreSQL (ADR-0009).

## References

- https://docs.docker.com/engine/release-notes/29/
- https://docs.docker.com/engine/security/
- https://github.com/docker/docker-bench-security
