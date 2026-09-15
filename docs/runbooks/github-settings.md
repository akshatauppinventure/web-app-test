# Runbook: GitHub repository settings

**Purpose:** configure the repository `akshatauppinventure/web-app-test` per ADR-0017 (rulesets, security features) and ADR-0020 (Renovate, T10).
**Prerequisites:** repository admin, `gh` CLI authenticated (`gh auth status`).
**Last tested:** 2026-09-15 (T00).

## 1. Ruleset on `main` (ADR-0017 §1)

Requirements: pull request required, no force push, no deletion, linear history, required status checks (added in T11).
With a single maintainer the approval count is **0** (self-approval is impossible on GitHub); documented deviation from "≥1 approval".

```bash
gh api -X POST repos/akshatauppinventure/web-app-test/rulesets --input - <<'JSON'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash", "rebase"]
      } }
  ]
}
JSON
```

Verify: `gh api repos/akshatauppinventure/web-app-test/rulesets --jq '.[].name'` lists `main-protection`, and a direct `git push origin main` is rejected.

> **Plan note:** rulesets on **private** repositories are enforced only on GitHub Pro/Team/Enterprise. On a Free personal plan the ruleset is stored but reported as not enforced. If `gh api` returns an enforcement warning, either upgrade the plan or accept "process-only" protection for the POC and record that in this runbook.

## 2. Security features

```bash
# Dependabot alerts + dependency graph (free on private repos)
gh api -X PUT repos/akshatauppinventure/web-app-test/vulnerability-alerts
# Secret scanning + push protection (requires GitHub Secret Protection on private repos)
gh api -X PATCH repos/akshatauppinventure/web-app-test --input - <<'JSON'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
```

If the second call fails with `422`/`403`, Secret Protection is not licensed for this private repo. Compensating control: `gitleaks` runs in CI (T11) and locally via the pre-commit hook; keep push protection on the list to enable when the plan allows.

Also in the web UI (`Settings → General`): disable **Wiki** and **Projects** if unused; set **Allow merge commits** off (squash/rebase only); enable **Automatically delete head branches**.

## 3. Packages (P3, T12)

`Settings → Packages` (organization/user level): keep container packages **private**; link each package to this repository after the first push so repo collaborators inherit access.

## 4. Renovate and Dependabot (T10)

Extended in T10: install the Renovate GitHub App on this repository only; leave Dependabot **security updates** off (Renovate opens the update PRs) but keep Dependabot **alerts** on.

## 5. GitHub App for deploy PRs (P4, T13)

Extended in T13.
