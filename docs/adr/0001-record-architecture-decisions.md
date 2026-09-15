# ADR-0001: Record architecture decisions

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** all ADRs in this folder

## Context

The project starts as a proof of concept (POC) that is meant to grow into a production system. Many of the early choices are hard to reverse: hosting, topology, identity provider, security model and delivery pipeline. The reasons behind them (research findings, trade-offs, dated version facts) will be lost unless they are written down. People joining later, and reviewers, need to understand *why* the system looks the way it does.

## Decision

We will record every significant architecture decision as an Architecture Decision Record (ADR) in `docs/adr/`.

- **Format:** lightweight Michael Nygard style. Sections: Context, Decision, Alternatives considered, Consequences, References. Use [template.md](template.md).
- **One decision per file**, named `NNNN-kebab-case-title.md` with a zero-padded, never-reused number.
- **Status lifecycle:** `Proposed` → `Accepted` → `Deprecated` or `Superseded by ADR-NNNN`.
- **Accepted ADRs are immutable.** To change a decision, write a new ADR that supersedes the old one, and update the old ADR's status line only.
- **Version facts are dated.** Any statement about versions, prices or market adoption includes the research date, because these facts go stale.
- **Keep the index current.** [README.md](README.md) lists all ADRs and their status.
- **Review process:** the project owner reviews ADRs before implementation starts. Merging an ADR PR with status `Accepted` is the approval.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| A single architecture document | Hard to see when and why individual decisions changed; tends to rot |
| Wiki pages outside the repo | Not versioned with the code; not reviewed in PRs |
| No written decisions | Loses reasoning; repeats debates |

## Consequences

**Positive**
- Decisions are reviewable in PRs and versioned with the code.
- New contributors can read the reasons, not just the result.

**Negative / risks**
- Small ongoing writing effort. ADRs can drift from reality if superseding decisions aren't recorded.

**Follow-ups**
- Add a PR checklist item: "Does this change contradict or require an ADR?"

## References

- Michael Nygard, "Documenting Architecture Decisions" (2011)
- https://adr.github.io/
