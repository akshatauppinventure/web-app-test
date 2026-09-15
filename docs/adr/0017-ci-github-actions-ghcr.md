# ADR-0017: CI: GitHub Actions and GHCR

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0016, ADR-0018, ADR-0019, ADR-0020

## Context

The owner confirmed **GitHub** for code hosting and wants CI/CD for the app containers (frontend, backend) plus our custom infrastructure images (Traefik with local plugins, Keycloak with the Apple extension).

Pricing facts (2026):
- GitHub-hosted runner prices dropped in January 2026.
- A $0.002/min fee for self-hosted runners was announced for March 2026, then **postponed**; self-hosted runners were still free as of August 2026.

GitHub Container Registry (GHCR) integrates with `GITHUB_TOKEN` and GitHub OIDC.

## Decision

1. **Repository:**
   - A single private **monorepo** on GitHub: `frontend/`, `backend/`, `infra/`, `docs/`.
   - **Repository ruleset on `main`:**
     - PR required, with ≥1 approval (can be self-approval-exempt in POC if there's a single maintainer; documented).
     - Required status checks.
     - No force pushes; linear history.
     - Signed commits recommended.
   - `CODEOWNERS` for `infra/`, `.github/` and `docs/adr/`.
   - GitHub secret scanning + push protection, Dependabot **alerts** and the dependency graph turned on. Update PRs come from Renovate (ADR-0020).
2. **Runners:** **GitHub-hosted** `ubuntu-24.04` runners, pinned by label rather than `ubuntu-latest`. **No self-hosted runners** (they would need Docker access and could reach our network).
3. **Workflow `ci.yml`** (on `pull_request` and `push` to `main`), with path filters per component:
   - **backend:** `uv sync --locked`, `ruff check`, `ruff format --check`, `pyright`, `pytest` (Postgres service container; RLS tests).
   - **frontend:** `pnpm install --frozen-lockfile`, `eslint`, `tsc --noEmit`, `vitest`, `next build`; plus a guard that fails if `next` < 16.3.3.
   - **infra:** `hadolint` (Dockerfiles), compose validation (`docker compose config`), a check that published ports match the allowlist (ADR-0014), and Traefik dynamic configuration lint.
   - **shared:** `zizmor` (workflow security), `gitleaks`, `actions/dependency-review-action` (fail on high-severity or disallowed licenses).
4. **Workflow `build-publish.yml`** (on `push` to `main`, for changed components only): build → scan → push → attest → sign → bump. Details in ADR-0019/0018.
   - `docker/build-push-action` with Buildx, **linux/amd64** only, GitHub Actions cache.
   - Tags: `ghcr.io/<owner>/<component>:sha-<git-sha>` (immutable in practice) plus OCI labels (source, revision, created).
   - **Trivy gate before push** (ADR-0019).
   - SBOM and provenance attestations (`sbom: true`, `provenance: mode=max`).
   - **cosign keyless signing** of the pushed digest.
   - Opens a **deploy PR** that updates image digests in `infra/stacks/*/compose.yaml` (ADR-0018).
5. **Registry:**
   - **GHCR**, packages **private**, linked to the repo.
   - Push uses `GITHUB_TOKEN` with `packages: write` in that job only.
   - Pulls from servers use a dedicated **read-only** token (ADR-0018).
   - Retention: keep the last 30 `sha-*` versions per component, plus any version currently referenced by `main`.
6. **Workflow security defaults:**
   - Top-level `permissions: contents: read`; elevated per job only.
   - `actions/checkout` with `persist-credentials: false`.
   - **No `pull_request_target`.**
   - All third-party actions **pinned to full commit SHAs** (ADR-0019).
   - Concurrency groups to avoid parallel publishes of the same component.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Forgejo + Forgejo Actions (self-hosted) | Fully FOSS, but adds a server to run and secure; owner chose GitHub |
| GitLab CI | Owner chose GitHub |
| Docker Hub / Quay / Harbor | GHCR is integrated with GitHub auth/OIDC at no extra cost; Harbor would be another service to run |
| Self-hosted runners on the VPS | Security risk (Docker socket, network position); unnecessary |
| Separate repos per component | More overhead for a small POC; the monorepo keeps ADRs, infra and code in lockstep |

## Consequences

**Positive**
- Ubiquitous tooling, no CI infrastructure to run, strong native security features (OIDC, attestations, secret scanning).

**Negative / risks**
- GitHub and GHCR are not FOSS and are a SaaS dependency. Migration to Forgejo is possible since workflows are largely compatible.
- Private-repo Actions minutes are metered beyond the free quota (acceptable at POC scale).

**Follow-ups**
- Set up branch rulesets and repo security settings when the repository is created.

## References

- https://github.com/resources/insights/2026-pricing-changes-for-github-actions
- https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- https://github.com/woodruffw/zizmor
