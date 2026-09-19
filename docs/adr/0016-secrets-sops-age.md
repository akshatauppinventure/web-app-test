# ADR-0016: Secrets management: SOPS + age

- **Status:** Accepted (2026-09-15); amended by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md) (tunnel pre-shared keys removed)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0006, ADR-0015, ADR-0017, ADR-0018

## Context

The system needs secrets:
- database role passwords, Keycloak DB password and bootstrap admin,
- `web-bff` client secret, Auth.js `AUTH_SECRET`, Google OAuth client secret,
- CrowdSec bouncer keys, Portainer `AGENT_SECRET`,
- restic repository password and object-storage keys,
- WireGuard preshared keys, GHCR pull token.

Requirements:
- Never stored in git as plain text.
- **VPS-A must never receive core secrets** (ADR-0003).
- Must work with Portainer GitOps. Portainer deploys compose files from git but **can't decrypt SOPS files**.
- FOSS; no extra always-on service for the POC.

## Decision

1. **Encryption at rest in git:**
   - **SOPS** with **age** keys.
   - Encrypted files live in `infra/secrets/`, split per host: `edge.sops.yaml` and `core.sops.yaml`.
   - `.sops.yaml` creation rules encrypt secrets **only to the admins' age public keys**. Servers hold no age private keys.
2. **Delivering secrets to the hosts:**
   - Secrets are written to hosts **out of band by an admin** over SSH on WireGuard, using a scripted command (e.g. `make secrets-push HOST=core`).
   - The script runs `sops -d` locally, writes each value to `/etc/app/secrets/<name>` (root-owned directory 0700; files owned by the container's UID, mode 0400), and never echoes values.
   - **`edge` secrets go only to VPS-A and `core` secrets only to VPS-B.**
3. **Consumption in containers:**
   - Compose **`secrets:`** with `file: /etc/app/secrets/<name>` (absolute host paths), mounted at `/run/secrets/<name>`.
   - Prefer images' `*_FILE` conventions (e.g. `POSTGRES_PASSWORD_FILE`) and application settings that read from files (pydantic-settings `secrets_dir`).
   - Where an image only accepts environment variables, a minimal entrypoint wrapper reads the file into the environment of that single process.
   - **Secrets are never put in Portainer stack environment variables, compose files or image layers.**
4. **CI secrets:**
   - GitHub Actions holds **no deployment or runtime secrets**.
   - CI uses `GITHUB_TOKEN` (GHCR push) and GitHub OIDC (cosign keyless signing, ADR-0019).
   - The GitHub App credentials for the digest-bump bot are a GitHub secret scoped to a protected environment (ADR-0018).
5. **Admin keys:**
   - Each admin's age private key lives in their password manager and on their machine. An **offline recovery copy** of an admin age key is kept (e.g. printed and stored securely) so backups and secrets remain recoverable.
6. **Rotation:**
   - Rotate on staff/device changes and after any suspected compromise.
   - Routine rotation every 6 months for high-value secrets (client secrets, DB passwords, `AUTH_SECRET`).
   - Procedure: edit with `sops`, commit, `secrets-push`, restart the affected stack.
7. **Detection:** gitleaks runs in CI and as a pre-commit hook (ADR-0019).

## Alternatives considered

| Option | Why not chosen |
|---|---|
| HashiCorp Vault / OpenBao | Strong, but an always-on, highly sensitive service to run and unseal; overkill for the POC. Reconsider for production. |
| Infisical (self-hosted) | Extra service and database; open-core model |
| Plain `.env` files on hosts (not in git) | No versioning/review; easy to lose or leak; no audit trail |
| GitHub Actions secrets + SSH deploy | Puts production secrets and access in CI (conflicts with the pull-based CD in ADR-0018) |
| Docker Swarm secrets | Requires Swarm (ADR-0005) |
| Hosts decrypt SOPS with their own age key | Viable, but keeps a decryption key on every server; the admin-push model keeps servers keyless for the POC |

## Consequences

**Positive**
- Secrets are versioned and reviewable (as encrypted diffs), segregated by host, never in CI, and never on the edge server if they belong to core.

**Negative / risks**
- Secret delivery is a manual admin step (not fully GitOps).
- A lost admin age key without a recovery copy means secrets must be regenerated.
- Secret files on disk are readable by host root. Accepted, since host root is already game over.

**Follow-ups**
- Production: evaluate OpenBao/Vault with short-lived dynamic DB credentials.

## References

- https://github.com/getsops/sops
- https://github.com/FiloSottile/age
- https://docs.docker.com/compose/how-tos/use-secrets/
- https://hub.docker.com/_/postgres/ (`POSTGRES_PASSWORD_FILE`)
