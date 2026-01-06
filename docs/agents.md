---
title: "Agent Entrypoint for graft-ci"
status: working
---

# Agent Entrypoint

This document provides operational guidance for agents working on graft-ci.

## Repository Purpose

graft-ci is the central automation service for Graft dependency management. It implements automated dependency update detection and pull request creation.

## Current Implementation Status

The repository is being set up to implement the dependency update notification specification from graft-knowledge.

## Key Constraints

- Zero upstream configuration: Upstream repositories require no changes
- Fast execution: Update checks complete in seconds without clones
- Minimal dependencies: Use standard tools (shell, git, curl, yq)
- Idempotent: Multiple runs do not create duplicate PRs

## Implementation Components

### Planned Components

1. **Dependency Graph Builder** (src/graph-builder.sh)
   - Scans organization repositories
   - Parses graft.yaml files
   - Builds inverted index: upstream → consumers
   - Caches results for efficiency

2. **Update Detector** (src/check-updates.sh)
   - Uses git ls-remote to check upstream refs
   - Compares with pinned refs in consumer graft.yaml
   - Returns list of outdated dependencies

3. **PR Creator** (src/create-pr.sh)
   - Updates graft.yaml with new refs
   - Creates pull request with context
   - Includes upstream commit information

4. **Forgejo Workflow** (.forgejo/workflows/dependency-update.yml)
   - Triggered by organization push events
   - Scheduled fallback (hourly)
   - Orchestrates graph building and update checking

## Write Boundaries

Agents may write to:
- docs/
- notes/
- src/
- .forgejo/

Never write to:
- secrets/
- .env files

## References

- [Dependency Update Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md)
- [Decision 0006: Event Strategy](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/decisions/decision-0006-dependency-update-events.md)
- [Human Entrypoint](README.md)
- [Domain Configuration](../knowledge-base.yaml)
