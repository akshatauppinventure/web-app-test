# Runbook: deploy and rollback (ADR-0018)

**Purpose:** how a change reaches the servers, and how to undo it.
**Last tested:** 2026-09-16 (T13).

## Normal flow (no human step)

1. A PR merges into `main`.
2. `build-publish` builds the changed components, gates them with Trivy, pushes `ghcr.io/akshatauppinventure/<component>:sha-<sha>` with SBOM + provenance, signs with cosign, and records each digest.
3. Its `deploy PR` job (GitHub App `DEPLOY_APP_ID`) opens **one PR per component**: branch `deploy/<component>-<short sha>`, title `deploy(<component>): sha-<short sha>`, changing only that component's `image:` lines in `infra/stacks/*/compose.yaml` (`scripts/ci/bump-digest.py`).
4. `verify-deploy` runs on that PR: compose validation, port allowlist, hardening baseline, and `cosign verify` of **every** `ghcr.io` digest in the stacks against `build-publish.yml@refs/heads/main`. When green, its `merge deploy PR` job squash-merges the PR with the App token (POC auto-merge; switch to `gh pr merge --auto` behind required checks once rulesets exist, P12).
5. Portainer (VPS-B) polls `main` every 5 minutes, pulls the new digest and redeploys the stack (T21).

Nothing merges if a digest is unsigned, a port is not allowlisted, or a service breaks the hardening baseline.

## Rollback

```bash
git log --oneline -- infra/stacks | head          # find the deploy(<component>) commit
git revert <commit> && git push                   # via a PR like any change; verify-deploy re-verifies the old digest
```
The old digest is still signed (signatures are per digest), so the revert PR passes and Portainer redeploys it within 5 minutes. Emergency: redeploy the previous digest by hand in Portainer over WireGuard, then commit the revert so git matches.

Database migrations are expand/contract (ADR-0018 §4): a backend rollback never needs a schema rollback.

## Manual deploy PR (rare)

Pin a specific signed digest: `python3 scripts/ci/bump-digest.py --component backend --tag sha-<sha> --digest sha256:<digest>`, open a PR; verify-deploy must pass. Digests never built on `main` cannot be merged (negative test in T13).

## Checks and where to look

- Deploy PRs: label `deploy`, author `<app>[bot]`.
- Failed verification: the `verify-deploy` run on the PR lists which reference failed.
- Signed digests of the latest builds: the `build-publish` run summary.
