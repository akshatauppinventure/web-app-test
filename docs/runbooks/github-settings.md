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

> **Result on 2026-09-15:** the API returned `403 Upgrade to GitHub Pro or make this repository public to enable this feature.` Rulesets (and classic branch protection) are **not available on private repositories under the GitHub Free personal plan**.
>
> **Owner decision needed (P12):** either (a) upgrade the account to **GitHub Pro** (about $4/month) and re-run the command above, or (b) accept *process-only* protection for the POC (all changes still go through PRs by convention; `main` is technically pushable). Until decided, (b) is in effect and is a documented deviation from ADR-0017 §1.

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

**Result on 2026-09-15:** Dependabot alerts + dependency graph: enabled. Secret scanning: `422 Secret scanning is not available for this repository` (needs GitHub Secret Protection, a paid add-on, on private repos). Compensating control: `gitleaks` runs in CI (T11); re-run the PATCH if the plan changes.

Applied on 2026-09-15 via API: merge commits off (squash/rebase only), auto-delete head branches on, wiki and projects off.



## 3. Packages (P3, T12)

`Settings → Packages` (organization/user level): keep container packages **private**; link each package to this repository after the first push so repo collaborators inherit access.

## 4. Renovate and Dependabot (T10)

Extended in T10: install the Renovate GitHub App on this repository only; leave Dependabot **security updates** off (Renovate opens the update PRs) but keep Dependabot **alerts** on.

## 5. GitHub App for deploy PRs (P4, T13)

Extended in T13.
