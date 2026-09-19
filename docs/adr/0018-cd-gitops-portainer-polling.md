# ADR-0018: CD: GitOps with Portainer polling

- **Status:** Accepted (2026-09-15); access model superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0006, ADR-0014, ADR-0015, ADR-0016, ADR-0017, ADR-0019

## Context

Built images must reach the servers automatically, without:
- exposing a deploy endpoint to the internet,
- giving CI SSH keys or network access to production.

Portainer is only reachable over WireGuard (ADR-0006). Portainer CE supports Git-backed stacks with **automatic updates by polling** or by webhook. A webhook would require Portainer to be reachable from GitHub, so it's excluded.

Watchtower (automatic container updates) was **archived in December 2025**.

## Decision

1. **Pull-based GitOps with Portainer CE:**
   - Two Git-backed stacks, created once by an admin in Portainer (on VPS-B):
     - `edge` → environment **VPS-A (Agent)**, compose path `infra/stacks/edge/compose.yaml`
     - `core` → environment **VPS-B (local)**, compose path `infra/stacks/core/compose.yaml`
   - Settings:
     - Branch: `main`.
     - **GitOps updates: polling every 5 minutes.**
     - **"Re-pull image" on;** "Force redeployment" off.
   - Git access: a GitHub **fine-grained, read-only token** limited to this repository's contents, or a read-only deploy key.
   - Registry access: GHCR credentials stored in Portainer, from a dedicated account/token with **read-only package access**. If fine-grained tokens still don't support GHCR at setup time, use a classic token scoped to `read:packages` only, owned by a machine user.
2. **Git is the deployment source of truth; images are referenced by digest:**
   - Compose files reference `ghcr.io/<owner>/<component>:sha-<git-sha>@sha256:<digest>`.
   - Only digests signed and scanned by CI (ADR-0019) are written there.
3. **Promotion flow:**
   1. `build-publish.yml` pushes, attests and signs the image (ADR-0017/0019).
   2. A bot opens a **deploy PR** (`deploy(frontend): sha-abc123`) that changes only the digest line(s). It uses a **GitHub App installation token** (created via `actions/create-github-app-token`), so the PR triggers required checks; `GITHUB_TOKEN`-created PRs don't.
   3. Required checks run: compose validation, published-port allowlist, and `cosign verify` of the referenced digests.
   4. **POC:** auto-merge is enabled on deploy PRs once checks pass. **Production:** require human approval via a protected environment or CODEOWNERS review.
   5. Portainer detects the new commit within about 5 minutes, pulls the digest and redeploys the stack.
4. **Database migrations:**
   - The `core` stack includes a one-shot `migrate` service (backend image, `alembic upgrade head`, `app_migrator` credentials).
   - `backend` uses `depends_on: migrate: condition: service_completed_successfully`.
   - Migrations must be **backward compatible** with the previous backend version (expand/contract), so rollback is a digest revert.
5. **Rollback:** `git revert` the deploy commit (or open a PR pinning the previous digest). Portainer redeploys within about 5 minutes. For emergencies, an admin can redeploy manually in Portainer over WireGuard; the drift is then reconciled in git.
6. **Keycloak configuration:**
   - The custom image is deployed the same way.
   - Realm JSON is imported only on first start.
   - Later realm changes are made via the admin console and exported back to git (documented runbook).
   - Automated realm config (keycloak-config-cli) is deferred.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| GitHub Actions SSH deploy (via Tailscale ephemeral node / public SSH) | Puts production access and secrets in CI; opens an inbound path |
| Portainer webhooks | Requires Portainer reachable from GitHub (internet) |
| Watchtower | Archived Dec 2025; tag-based, no git audit trail |
| Self-hosted runner on VPS | Runner compromise = host compromise |
| Argo CD / Flux | Kubernetes-only |
| Direct bot push to `main` | Bypasses required checks/rulesets; PR-based is auditable |

## Consequences

**Positive**
- No inbound deploy surface; every deployment is a reviewed, auditable git commit; rollback is `git revert`; CI never touches servers.

**Negative / risks**
- Up to about 5 minutes of deploy latency (polling).
- Portainer CE doesn't verify cosign signatures at pull time. Compensated by verifying digests in the deploy PR checks and pinning by digest (ADR-0019).
- Auto-merge in the POC means a compromised build pipeline could deploy. Mitigated by SHA-pinned actions, zizmor, and branch rulesets. Production adds human approval.
- Secrets are delivered separately (ADR-0016); a new secret requires a manual `secrets-push` before merging.

**Follow-ups**
- Production: environment approvals, staging environment, signature verification at deploy time.

## References

- https://docs.portainer.io/user/docker/stacks/add
- https://oneuptime.com/blog/post/2026-03-20-portainer-stack-autoupdate-polling/view
- https://github.com/actions/create-github-app-token
- https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow#triggering-a-workflow-from-a-workflow
- https://linuxiac.com/docker-update-tool-watchtower-reaches-end-of-maintenance/
