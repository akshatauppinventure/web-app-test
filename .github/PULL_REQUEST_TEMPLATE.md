## Task

<!-- PLAN.md task id and title, e.g. "T01 · Backend scaffold" -->

## ADRs implemented

<!-- e.g. ADR-0008. Note any deviation from the ADR and why. -->

## What changed

-

## Checks

- [ ] Tests were written first and fail without the change (TDD); all listed local checks / CI pass
- [ ] No secret, token or private key is committed (gitleaks clean; `.gitignore` covers local secret files)
- [ ] Every new image/version is pinned per ADR-0020 (exact version + digest, no `latest`)
- [ ] Docs touched by this task are updated in this PR (README, runbooks, ADR follow-ups, CLAUDE.md)
- [ ] Does this change contradict or require an ADR? If yes, the ADR is added or superseded in this PR
