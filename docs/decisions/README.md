# Architecture Decisions

This directory contains Architecture Decision Records (ADRs) for graft-ci.

## Active Decisions

- [Decision 0001: Shell Script Implementation](decision-0001-shell-script-implementation.md) - Use Bash scripts with standard Unix tools

## Decision Log

| Number | Title | Status | Date |
|--------|-------|--------|------|
| 0001 | Shell Script Implementation | Accepted | 2026-01-06 |

## Creating New Decisions

When documenting a significant architectural choice:

1. Create `decision-XXXX-descriptive-name.md`
2. Use the standard ADR format:
   - Context: What decision needs to be made and why
   - Decision: What was chosen
   - Alternatives Considered: What other options were evaluated
   - Consequences: Positive, negative, and mitigations
   - Sources: References that informed the decision

3. Update this index

## Related

- [meta-knowledge-base: Authority Policy](https://forgejo.example/daniel/meta-knowledge-base/src/branch/main/policies/authority.md) - Decisions are canonical for tradeoffs
- [graft-knowledge decisions](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/decisions/) - Upstream project decisions
