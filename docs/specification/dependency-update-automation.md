---
title: "Dependency Update Automation Implementation"
date: 2026-01-06
status: working
---

# Dependency Update Automation Implementation

## Overview

This specification defines the implementation of automated dependency update detection and propagation for graft-ci, based on the [Dependency Update Notification Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md) from graft-knowledge.

## Objectives

Implement a central service that:

1. Detects when upstream dependencies have new commits
2. Creates pull requests in consuming repositories with updated refs
3. Operates with zero configuration in upstream repositories
4. Executes quickly using minimal dependencies

## Components

### 1. Dependency Graph Builder

**Location**: src/graph-builder.sh

**Purpose**: Build inverted dependency index from organization repositories.

**Algorithm**:
```
For each repository in organization:
  Fetch graft.yaml
  Parse dependencies section
  For each dependency:
    Add consumer to upstream's consumer list

Output: JSON map of upstream → [consumers]
```

**Implementation Details**:
- Uses Forgejo API to enumerate repositories
- Fetches only graft.yaml file (no full clone)
- Caches results with invalidation on graft.yaml changes
- Execution time: under 5 seconds for typical organization

### 2. Update Detector

**Location**: src/check-updates.sh

**Purpose**: Identify consumers with outdated dependency refs.

**Algorithm**:
```
Input: upstream repository name, pushed commit SHA

Load dependency graph
Find all consumers of upstream

For each consumer:
  Fetch consumer's graft.yaml
  Extract pinned ref for upstream dependency

  If pushed_sha != pinned_ref:
    Add to update list with:
      - consumer repo
      - current ref
      - new ref
      - upstream commit details

Output: JSON list of required updates
```

**Implementation Details**:
- Uses git ls-remote for ref checking (no clone required)
- Parallel checking for multiple consumers
- Returns empty list if no updates needed

### 3. PR Creator

**Location**: src/create-pr.sh

**Purpose**: Create or update pull requests in consumer repositories.

**Algorithm**:
```
Input: consumer repo, dependency name, old ref, new ref

1. Check for existing PR for this dependency
   - If exists and open: update branch
   - If exists and merged: skip
   - If not exists: create new

2. Create branch: "deps/update-{dep_name}-{short_sha}"

3. Update graft.yaml:
   - Replace old ref with new ref in dependency URL

4. Commit with message:
   "chore(deps): update {dep_name} to {short_sha}"

5. Create PR with body:
   ## Summary
   Updates {dep_name} dependency to latest upstream commit.

   **Upstream commit:** {sha} - {commit_message}
   **Author:** {author}
   **Date:** {date}

   ## Changes
   - {dep_name}: {old_short_sha} → {new_short_sha}

   ---
   Automated by graft-ci

6. Push branch and create/update PR
```

**Implementation Details**:
- Uses Forgejo API for PR operations
- Idempotent: safe to run multiple times
- Includes upstream commit context for reviewers

### 4. Forgejo Workflow

**Location**: .forgejo/workflows/dependency-update.yml

**Triggers**:
- Organization webhook on push events (primary)
- Schedule: hourly (fallback)

**Workflow Steps**:

```yaml
1. Build dependency graph
   - Caches result
   - Invalidates on graft.yaml changes

2. On push event:
   - Extract pushed repo and commit
   - Check for affected consumers
   - Create PRs for outdated consumers

3. On schedule:
   - Check all dependencies in all consumers
   - Create PRs for any outdated refs
```

**Environment Requirements**:
- FORGEJO_TOKEN: API token with repo read/write access
- FORGEJO_URL: Base URL of Forgejo instance

## Workflow Sequence

### Event-Driven Flow

```
1. Developer pushes to graft-knowledge
2. Forgejo fires organization webhook
3. graft-ci workflow triggered with event data
4. Graph builder identifies graft as consumer
5. Update detector compares refs
6. PR creator updates graft repository
7. Pull request appears in graft for review
```

### Scheduled Flow

```
1. Hourly cron triggers workflow
2. Graph builder scans all repositories
3. Update detector checks all dependencies
4. PR creator generates PRs for outdated refs
5. Developers review and merge PRs
```

## Configuration

### Organization Webhook Setup

```
Forgejo Organization Settings → Webhooks → Add Webhook
  URL: https://{forgejo-url}/api/v1/repos/daniel/graft-ci/dispatches
  Content Type: application/json
  Secret: {webhook-secret}
  Events:
    - Push
  Active: ✓
```

### Repository Secrets

Required in graft-ci repository settings:

- FORGEJO_TOKEN: Personal access token with repo scope
- WEBHOOK_SECRET: Shared secret for webhook validation

## Efficiency Considerations

### Performance Targets

- Graph building: under 5 seconds for 50 repositories
- Update checking: under 2 seconds per upstream
- PR creation: under 3 seconds per consumer
- Total end-to-end: under 10 seconds for typical update

### Optimization Strategies

1. **Minimal fetches**: Use git ls-remote instead of clone
2. **Parallel operations**: Check multiple consumers concurrently
3. **Caching**: Store dependency graph between runs
4. **Incremental updates**: Only rebuild graph when graft.yaml changes

## Security

### Access Control

- Service uses deploy key or token with minimal scope
- PRs created by bot account: graft-ci-bot
- All changes go through normal review process
- Branch protection rules apply to automated PRs

### Webhook Validation

- Verify webhook signatures using shared secret
- Reject requests without valid signature
- Log all webhook events for audit

## Testing

### Unit Tests

- Graph builder: Parse various graft.yaml formats
- Update detector: Compare ref strings correctly
- PR creator: Generate correct commit messages

### Integration Tests

- End-to-end: Push to test repo triggers PR in consumer
- Idempotency: Multiple runs do not create duplicates
- Error handling: Graceful failure on API errors

## Monitoring

### Metrics

- Update detection latency (event to PR creation)
- Success rate of PR creation
- Number of updates processed per day

### Logging

- All webhook events received
- Graph rebuild operations
- PR creation attempts and results
- API errors and retries

## Limitations

### Current Scope

- Single organization only (cross-org requires separate configuration)
- Works with Forgejo (GitHub/GitLab need adapter)
- Handles graft.yaml format v0 only

### Future Enhancements

- Support for update policies (auto-merge, notify-only)
- Cross-organization dependency tracking
- Support for semantic versioning constraints
- Integration with graft CLI (graft check-updates)

## Sources

- [graft-knowledge: Dependency Update Notification Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md)
- [graft-knowledge: Decision 0006 - Dependency Update Events](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/decisions/decision-0006-dependency-update-events.md)
- [Forgejo Actions Documentation](https://forgejo.org/docs/latest/user/actions/)
- [Forgejo Webhooks Documentation](https://forgejo.org/docs/latest/user/webhooks/)
