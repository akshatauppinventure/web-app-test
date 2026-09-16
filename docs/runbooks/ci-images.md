# Runbook: container images from CI (ADR-0017 §4, ADR-0019 §3–§4, ADR-0020)

**Purpose:** how images get built, gated, published, signed, and how to verify or force a rebuild.
**Last tested:** 2026-09-16 (T12).

## What `build-publish.yml` does

| Event | Components | Steps |
|---|---|---|
| pull request touching a component | changed ones (`scripts/ci/changed-components.sh`) | build (`linux/amd64`) → **Trivy gate** (CRITICAL/HIGH with a fix, `.trivyignore` honoured) — no push |
| push to `main` | changed since the previous commit; everything if the workflow/script/`.trivyignore` changed | build → Trivy gate → push `ghcr.io/akshatauppinventure/<component>:sha-<full git sha>` with **SBOM** (SPDX) and **SLSA provenance** (`mode=max`) → **cosign keyless sign** → self-verify |
| `workflow_dispatch` | all six | same as push (first publish, base-image refresh) |

Components: `frontend`, `backend` (contexts `frontend/`, `backend/`), `keycloak`, `traefik`, `crowdsec`, `postgres` (contexts `infra/<name>/`). Tags are immutable in practice; the deploy PR bot (T13) writes `tag@sha256:digest` into `infra/stacks/*/compose.yaml`.

## Verify an image

Every push-to-main run already asserts, per image: provenance present, SBOM non-empty, and `cosign verify` against this workflow's identity (see the job log and the run summary for the `tag@digest` lines). To repeat it from a laptop the CLI token needs the `read:packages` scope (`gh auth refresh -h github.com -s read:packages`, then `gh auth token | docker login ghcr.io -u <user> --password-stdin`):

```bash
IMG=ghcr.io/akshatauppinventure/backend:sha-<sha>
docker buildx imagetools inspect "$IMG" --format '{{json .Provenance}}' | jq '.["linux/amd64"].SLSA.builder'
docker buildx imagetools inspect "$IMG" --format '{{json .SBOM}}' | jq '.["linux/amd64"].SPDX.packages | length'
cosign verify \
  --certificate-identity-regexp '^https://github.com/akshatauppinventure/web-app-test/.github/workflows/build-publish.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$IMG" | jq -r '.[0].optional.Issuer'
```
`cosign verify` fails for anything not built by this workflow on `main` — that is the property T13's `verify-deploy` check relies on.

## Trivy exceptions

Add a line to `.trivyignore`: `CVE-XXXX-YYYY exp:YYYY-MM-DD  # component: reason`. Trivy ignores expired entries, so the gate fails again on expiry. Prefer bumping the base image (Renovate) over an exception; ADR-0020 patch SLAs apply.

## Force a rebuild / first publish

GitHub → Actions → **build-publish** → *Run workflow* (`all = true`), or `gh workflow run build-publish.yml -f all=true`. Base-image digest bumps from Renovate rebuild only the affected components.

## Pulling on the servers (T21)

Portainer uses a dedicated read-only credential (`read:packages` classic token of a machine user, or a fine-grained token if GHCR supports it at setup time), never a personal token. Packages stay **private** (P3).
