# ADR-0019: Software supply-chain security

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0007, ADR-0008, ADR-0017, ADR-0018, ADR-0020

## Context

Supply-chain attacks are among the most likely ways to breach a small team.

- **2026-03-19/20:** attackers force-pushed **75 of 76 version tags** of `aquasecurity/trivy-action` and stole CI secrets from pipelines that ran it (CVE-2026-33634 / GHSA-69fq-xp46-6x23). Only SHA-pinned consumers were safe.
- The npm and PyPI ecosystems regularly see malicious packages and hijacked maintainer accounts.
- Next.js and React had critical CVEs in Dec 2025 and Aug 2026.

We need controls from source code through to the running image.

## Decision

1. **GitHub Actions hardening:**
   - **Every `uses:` is pinned to a full 40-character commit SHA**, with a version comment (e.g. `# v4.2.2`). Renovate updates the SHAs.
   - **Trivy action:** pin to a known-good commit (at research time `57a97c7e7821a5776cebc9bb87c984fa69cba8f1` = trivy-action v0.35.0) or run a pinned Trivy binary/container by digest.
   - **zizmor** lints workflows in CI (template injection, excessive permissions, `pull_request_target`, unpinned actions).
   - Minimal `permissions:` per job; `persist-credentials: false`; no untrusted input interpolated into `run:` scripts.
2. **Source and dependency controls:**
   - **gitleaks** in CI and as a pre-commit hook. GitHub push protection on.
   - **Lockfiles are mandatory:** `pnpm-lock.yaml` (`--frozen-lockfile`) and `uv.lock` (`--locked`).
   - **pnpm:** dependency lifecycle scripts blocked by default; allow only reviewed packages via `onlyBuiltDependencies`.
   - `actions/dependency-review-action` fails PRs that add dependencies with known high-severity vulnerabilities or disallowed licenses.
   - **Renovate release-age cooldown:** `minimumReleaseAge: "3 days"` for non-security updates, to avoid adopting freshly hijacked releases. Security updates skip the cooldown.
3. **Image build controls:**
   - Base images pinned by digest (ADR-0020); multi-stage builds; minimal final stages; non-root users.
   - **hadolint** on Dockerfiles.
   - **Trivy image scan gate before push:** fail on `CRITICAL`/`HIGH` vulnerabilities **that have a fix available**. Exceptions go in `.trivyignore` with a justification comment and an expiry date, reviewed in PRs.
   - Downloaded artifacts (Keycloak Apple extension JAR, Traefik local plugins) are **verified by SHA-256 checksum** committed in the repo.
4. **Provenance and signing:**
   - Buildx **SBOM** (SPDX) and **SLSA provenance** (`mode=max`) attestations pushed with the image.
   - **cosign keyless signing** of each pushed digest via GitHub OIDC (`id-token: write`), recorded in the Sigstore transparency log.
   - **Verification:** the deploy PR check (ADR-0018) runs `cosign verify` with `--certificate-identity-regexp` pinned to this repo's `build-publish.yml` on `refs/heads/main` and `--certificate-oidc-issuer https://token.actions.githubusercontent.com` for every digest referenced in compose files.
5. **Third-party images we don't build** (PostgreSQL, CrowdSec, Portainer): pinned by digest; scanned by a scheduled Trivy job (weekly) that opens an issue on new fixable CRITICAL/HIGH findings.
6. **Scheduled rescans:** weekly Trivy scans of all currently deployed digests (new CVEs appear after build time).

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Pin actions by version tag | Tags are mutable, as the trivy-action incident proved |
| Grype instead of Trivy | Viable; Trivy remains the most widely used. Trivy is used SHA-pinned; switch if trust erodes further. |
| Docker Scout | Tied to Docker's platform/account; Trivy is FOSS |
| Signing with long-lived keys | Key management burden; keyless OIDC signing is standard for GitHub |
| Harden-Runner (StepSecurity) | Useful outbound monitoring for runners; optional later |

## Consequences

**Positive**
- Tamper-evident, scanned, signed images; CI resistant to tag hijacking; fresh-malware exposure reduced by the cooldown.

**Negative / risks**
- More CI time and occasional false positives (scanner findings without real impact).
- The cooldown delays non-security updates by 3 days.
- Portainer doesn't verify signatures at pull time (compensated in ADR-0018).

**Follow-ups**
- Production: signature verification at deploy time (e.g. a verification step before redeploy), VEX data with Docker Hardened Images (ADR-0020), OpenSSF Scorecard for the repo.

## References

- https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23
- https://socket.dev/blog/trivy-under-attack-again-github-actions-compromise
- https://github.com/woodruffw/zizmor
- https://github.com/gitleaks/gitleaks
- https://docs.docker.com/build/metadata/attestations/
- https://docs.sigstore.dev/cosign/signing/signing_with_containers/
- https://docs.renovatebot.com/configuration-options/#minimumreleaseage
- https://pnpm.io/settings
