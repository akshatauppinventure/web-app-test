# ADR-0006: Portainer CE LTS: placement and access

- **Status:** Accepted (2026-09-15); amended by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md) (Portainer Server on 127.0.0.1:9443 (SSH port forwarding), Agent on 10.0.0.11:9001)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0005, ADR-0015, ADR-0018

## Context

The owner requires Portainer for container management. Portainer has access to the Docker socket, which is **root-equivalent** on every host it manages. Whoever controls Portainer controls both servers. Portainer's own guidance is not to expose Portainer or the Agent to the internet, and to put them behind a VPN.

As of 2026-09-14: **Portainer CE 2.45 LTS** was released in August 2026, with support until May 2027. A new LTS comes out about every 6 months.

## Decision

1. **Edition and version:** Portainer **Community Edition, LTS track** (`portainer/portainer-ce:2.45.x` and `portainer/agent:2.45.x`, pinned by digest). Upgrade LTS to LTS (next expected about February 2027) and apply patch releases within the security SLA (ADR-0020).
2. **Placement:**
   - **Portainer Server on VPS-B (core)**, the server with no public TCP ports.
   - **Portainer Agent on VPS-A (edge).**
   - Rationale: compromising the internet-facing host must not hand over the control plane for the other host.
3. **Network exposure:**
   - Server UI/API: published **only** on `10.10.0.2:9443` (WireGuard IP), reachable only from admin WireGuard peers.
   - Agent: published **only** on `10.10.0.1:9001`, reachable **only from `10.10.0.2`** (enforced in `DOCKER-USER`, ADR-0014).
   - The Edge tunnel port (8000) is disabled or not published; we don't use Edge Agents.
   - Set a shared **`AGENT_SECRET`** on Server and Agent (a secret, ADR-0016).
4. **Authentication and hygiene:**
   - Initial admin created immediately after first start, with a long random password stored in the admin password manager. Never expose an un-initialized Portainer.
   - Personal named admin accounts for humans; no shared logins beyond break-glass.
   - Disable anonymous usage statistics.
   - Back up the Portainer data volume with the nightly backup (ADR-0021).
5. **Role:**
   - Portainer is the **deployment engine for GitOps** (ADR-0018) and the operations UI (logs, health, restarts).
   - Manual changes to stacks in the UI are discouraged. Git is the source of truth; drift is fixed by committing.

### Amendment (2026-09-15, PLAN task T00)

Portainer cannot deploy the Compose stack that contains itself. Therefore **Portainer Server (VPS-B) and Portainer Agent (VPS-A) are bootstrapped by cloud-init as a separate Compose project** (`infra/host/bootstrap/`), not from the GitOps stacks in `infra/stacks/*`. The GitOps stacks contain only application and edge services. Everything else in this ADR (placement, exposure, `AGENT_SECRET`, hygiene) is unchanged.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Portainer Server on VPS-A | A compromised edge host would control the core host |
| Portainer Business Edition | Paid; features (RBAC detail, relative-path volumes, etc.) not needed for the POC |
| Public Portainer behind SSO/2FA | Still internet-exposed and root-equivalent; the VPN-only approach is safer |
| No Portainer (plain Compose via SSH) | Contradicts the stated requirement |
| Dockge / Komodo | Smaller communities than Portainer |

## Consequences

**Positive**
- Container management without any public attack surface; control plane isolated from the edge.

**Negative / risks**
- If VPS-B is down, the management UI is down. Break-glass access: SSH over WireGuard, or the provider console.
- Portainer holds Docker socket access on both hosts. A compromised Portainer means both hosts are compromised. Mitigated by VPN-only access and strong authentication.
- Portainer CE doesn't verify image signatures (see ADR-0019 for compensating controls).

**Follow-ups**
- Production: evaluate OIDC login for Portainer via Keycloak if supported in CE at that time; move the Portainer Server to the data tier (ADR-0003 target).

## References

- https://www.portainer.io/blog/portainer-2-45-lts-release
- https://docs.portainer.io/start/lifecycle
- https://www.portainer.io/blog/should-you-expose-portainer-or-agent-to-the-internet
- https://docs.portainer.io/advanced/security
