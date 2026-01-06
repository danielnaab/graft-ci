---
title: "Testing Plan"
status: working
---

# Testing Plan for graft-ci

Progressive testing strategy to validate the dependency update automation system.

## Testing Phases

### Phase 1: Local Script Validation

Test each script individually on your local machine before running in CI.

#### 1.1 Graph Builder Test

```bash
cd /home/coder/graft-ci

# Set up environment
export FORGEJO_TOKEN="your-token-here"
export FORGEJO_URL="ssh://forgejo@platform-vm:2222"
export GRAFT_ORG="daniel"

# Run graph builder
./src/graph-builder.sh > test-graph.json

# Verify output
cat test-graph.json | jq .

# Expected: JSON object mapping upstream repos to their consumers
# Example:
# {
#   "graft-knowledge": [
#     {"repo": "graft", "dep_name": "graft-knowledge"},
#     {"repo": "graft-ci", "dep_name": "graft-knowledge"}
#   ],
#   "meta-knowledge-base": [
#     {"repo": "graft-ci", "dep_name": "meta-knowledge-base"}
#   ]
# }
```

**Validation checklist:**
- [ ] All repositories in organization listed
- [ ] Repositories with graft.yaml have dependencies mapped
- [ ] Upstream → consumer relationships correct
- [ ] No JSON syntax errors
- [ ] No API errors in stderr

#### 1.2 Update Detector Test

```bash
# Test with a known upstream that has consumers
./src/check-updates.sh graft-knowledge test-graph.json > test-updates.json

# View results
cat test-updates.json | jq .

# Expected: JSON array of updates (may be empty if all up to date)
# Example:
# [
#   {
#     "consumer": "graft",
#     "dep_name": "graft-knowledge",
#     "upstream": "graft-knowledge",
#     "old_ref": "main",
#     "old_sha": "abc123...",
#     "new_sha": "def456...",
#     "git_url": "ssh://forgejo@platform-vm:2222/daniel/graft-knowledge.git",
#     "commit_info": {
#       "message": "Add new feature",
#       "author": "John Doe",
#       "date": "2026-01-06..."
#     }
#   }
# ]
```

**Validation checklist:**
- [ ] git ls-remote succeeds for all dependencies
- [ ] SHA comparison logic works correctly
- [ ] Commit info fetched successfully
- [ ] No false positives (repos already up to date)
- [ ] No errors accessing private repositories

#### 1.3 PR Creator Dry Run Test

```bash
# IMPORTANT: Start with dry run to avoid creating actual PRs
export DRY_RUN=true

# Test with update data from previous step
./src/create-pr.sh test-updates.json

# Expected: Logs showing what WOULD be done, no actual PRs
```

**Validation checklist:**
- [ ] Branch names generated correctly
- [ ] graft.yaml update logic correct
- [ ] PR title and body formatted properly
- [ ] No actual branches or PRs created
- [ ] Existing PR check works

### Phase 2: Test Repository Setup

Create dedicated test repositories to validate end-to-end without affecting production.

#### 2.1 Create Test Repositories

```bash
# Create three test repos:
# 1. test-upstream-a (will be an upstream dependency)
# 2. test-upstream-b (another upstream)
# 3. test-consumer (will depend on both upstreams)

# On Forgejo web interface or via API:
# Create: daniel/test-upstream-a (empty repo with README)
# Create: daniel/test-upstream-b (empty repo with README)
# Create: daniel/test-consumer (with graft.yaml)
```

#### 2.2 Configure Test Consumer

Create graft.yaml in test-consumer:

```yaml
apiVersion: graft/v0
deps:
  test-upstream-a: "ssh://forgejo@platform-vm:2222/daniel/test-upstream-a.git#main"
  test-upstream-b: "ssh://forgejo@platform-vm:2222/daniel/test-upstream-b.git#main"
```

Commit and push.

#### 2.3 Get Current State

```bash
# Build graph including test repos
./src/graph-builder.sh > test-graph.json

# Verify test repos appear
cat test-graph.json | jq '.["test-upstream-a"], .["test-upstream-b"]'

# Expected:
# [{"repo": "test-consumer", "dep_name": "test-upstream-a"}]
# [{"repo": "test-consumer", "dep_name": "test-upstream-b"}]
```

### Phase 3: End-to-End Workflow Test

Test the complete automation cycle.

#### 3.1 Make Change to Upstream

```bash
# Clone test-upstream-a
git clone ssh://forgejo@platform-vm:2222/daniel/test-upstream-a.git
cd test-upstream-a

# Make a change
echo "Test change $(date)" >> README.md
git add README.md
git commit -m "test: trigger dependency update"
git push

# Note the new commit SHA
git rev-parse HEAD
```

#### 3.2 Run Update Detection

```bash
cd /home/coder/graft-ci

# Rebuild graph
./src/graph-builder.sh > test-graph.json

# Check for updates
./src/check-updates.sh test-upstream-a test-graph.json > test-updates.json

# Verify update detected
cat test-updates.json | jq .
```

**Expected result:**
```json
[
  {
    "consumer": "test-consumer",
    "dep_name": "test-upstream-a",
    "upstream": "test-upstream-a",
    "old_sha": "<previous-sha>",
    "new_sha": "<new-sha-from-push>",
    ...
  }
]
```

#### 3.3 Create PR (Dry Run First)

```bash
# Dry run to verify PR content
DRY_RUN=true ./src/create-pr.sh test-updates.json

# Review logs - check PR title, body, branch name

# If looks good, create actual PR
DRY_RUN=false ./src/create-pr.sh test-updates.json
```

#### 3.4 Verify PR Created

Check Forgejo web interface:
- [ ] PR exists in test-consumer repository
- [ ] Branch named `deps/update-test-upstream-a-<short-sha>`
- [ ] PR title: "chore(deps): update test-upstream-a to <short-sha>"
- [ ] PR body includes upstream commit info
- [ ] graft.yaml diff shows old SHA → new SHA

#### 3.5 Test Idempotency

```bash
# Run PR creator again with same updates
./src/create-pr.sh test-updates.json

# Expected: Logs show "PR already exists: #1" (no duplicate PR)
```

### Phase 4: Workflow Test in Forgejo Actions

Test the automated workflow before enabling it.

#### 4.1 Configure Secrets

In graft-ci repository settings:

1. Add FORGEJO_TOKEN secret
2. Add SSH_PRIVATE_KEY secret (if using SSH for pushing)
3. Add any other required secrets

#### 4.2 Manual Workflow Trigger (Dry Run)

```
Forgejo UI:
  Repository: graft-ci
  Actions → Dependency Update Automation → Run workflow

  Inputs:
    upstream_repo: test-upstream-a
    dry_run: true

  Click "Run workflow"
```

**Check workflow output:**
- [ ] Graph builds successfully
- [ ] Updates detected
- [ ] Dry run logs show what would be done
- [ ] No errors
- [ ] Artifacts uploaded (graph.json, updates.json)

#### 4.3 Manual Workflow Trigger (Real Run)

Same as above but with `dry_run: false`

**Verify:**
- [ ] Workflow completes successfully
- [ ] PR created in test-consumer
- [ ] No duplicate PRs on second run

#### 4.4 Test Scheduled Trigger

```yaml
# Temporarily change schedule to run every 5 minutes for testing
# Edit .forgejo/workflows/dependency-update.yml

schedule:
  - cron: '*/5 * * * *'  # Every 5 minutes (for testing only)
```

Commit, push, wait 5 minutes, verify workflow runs automatically.

**Remember to revert to hourly after testing:**
```yaml
schedule:
  - cron: '0 * * * *'  # Every hour
```

### Phase 5: Production Rollout

Progressive rollout to real repositories.

#### 5.1 Opt-In Testing

Choose 1-2 low-risk repositories to start:
- Pick repos with active maintainers who can review PRs
- Ensure they have graft.yaml with dependencies
- Notify maintainers about the automation

#### 5.2 Monitor First PRs

Watch the first few automated PRs:
- [ ] PRs created correctly
- [ ] No duplicate PRs
- [ ] Commit messages accurate
- [ ] Dependencies updated to correct SHAs
- [ ] No false positives

#### 5.3 Gradual Expansion

After successful testing:
1. Enable for all repositories with graft.yaml
2. Monitor for issues
3. Adjust schedule if needed (hourly may be too frequent)
4. Document any edge cases discovered

### Phase 6: Edge Case Testing

Test specific scenarios that might cause issues.

#### 6.1 Test: No Updates Available

```bash
# Ensure consumer is already up to date
./src/check-updates.sh graft test-graph.json

# Expected: Empty array []
# Verify: No errors, clean exit
```

#### 6.2 Test: Repository Without graft.yaml

```bash
# Create test repo without graft.yaml
# Run graph builder
./src/graph-builder.sh > test-graph.json

# Expected: Repo not in graph, no errors
```

#### 6.3 Test: Invalid graft.yaml

Create test-invalid-yaml repo with malformed YAML:

```yaml
apiVersion: graft/v0
deps:
  bad: "not a valid url
```

**Expected:** Script logs error, continues with other repos

#### 6.4 Test: Private Upstream Dependency

Test with private repository as dependency.

**Expected:** git ls-remote succeeds if SSH keys configured

#### 6.5 Test: Multiple Updates at Once

Push changes to multiple upstreams, verify:
- [ ] All consumers get PRs
- [ ] No race conditions
- [ ] Each PR is independent

#### 6.6 Test: Large Organization

If you have access to an org with >50 repos:
- [ ] Pagination works correctly
- [ ] All repos fetched
- [ ] Execution time reasonable

### Phase 7: Performance Testing

Measure execution time and resource usage.

```bash
# Time graph building
time ./src/graph-builder.sh > /dev/null

# Target: <5 seconds for typical organization (10-20 repos)

# Time update checking
time ./src/check-updates.sh graft-knowledge test-graph.json > /dev/null

# Target: <2 seconds per upstream

# Monitor workflow duration in Actions tab
# Target: <10 seconds end-to-end for single update
```

## Testing Checklist

Before production deployment:

### Functionality
- [ ] Graph builder fetches all repositories
- [ ] Graph builder handles pagination
- [ ] Update detector finds outdated dependencies
- [ ] Update detector resolves branch refs to SHAs
- [ ] PR creator updates graft.yaml correctly
- [ ] PR creator generates proper PR content
- [ ] PR creator is idempotent (no duplicates)
- [ ] Workflow runs on schedule
- [ ] Workflow can be triggered manually
- [ ] Dry run mode works correctly

### Error Handling
- [ ] API errors logged clearly
- [ ] git ls-remote failures handled gracefully
- [ ] SSH connection issues reported
- [ ] Invalid YAML files don't crash scripts
- [ ] Missing graft.yaml handled correctly
- [ ] Token auth failures detected

### Security
- [ ] Secrets configured correctly
- [ ] SSH keys have minimal permissions
- [ ] Tokens scoped appropriately
- [ ] No secrets in logs
- [ ] Branch protection respected

### Documentation
- [ ] Setup guide accurate
- [ ] Troubleshooting section helpful
- [ ] Examples work as documented
- [ ] Configuration options documented

## Troubleshooting Test Failures

### "FORGEJO_TOKEN environment variable not set"

**Cause:** Token not exported in environment

**Fix:**
```bash
export FORGEJO_TOKEN="your-token"
```

### "git ls-remote failed: Permission denied"

**Cause:** SSH keys not configured

**Fix:**
```bash
# Test SSH access
ssh -T git@platform-vm -p 2222

# If fails, set up SSH key (see docs/setup.md)
```

### "No consumers found for upstream"

**Cause:** No repositories depend on the tested upstream

**Fix:** This is expected if no dependencies exist. Use test repositories.

### PR not created in workflow

**Causes:**
1. Dry run mode enabled
2. SSH access not configured in Actions
3. No updates available

**Debug:**
1. Check Actions logs
2. Download artifacts (graph.json, updates.json)
3. Verify SSH_PRIVATE_KEY secret set
4. Test scripts locally with same inputs

### "Error fetching repos: 401 Unauthorized"

**Cause:** Invalid or expired token

**Fix:** Generate new token with correct scopes (repo, read:org)

## Next Steps After Testing

Once all tests pass:

1. Update schedule to production frequency (hourly → daily/etc)
2. Enable organization webhook (optional, for event-driven)
3. Document any organization-specific configuration
4. Set up monitoring/alerting (optional)
5. Train team on reviewing automated PRs
6. Establish runbook for common issues

## Test Results Documentation

Record test results in notes:

```markdown
# Test Results - YYYY-MM-DD

## Phase 1: Local Scripts
- Graph builder: ✓ Pass
- Update detector: ✓ Pass
- PR creator (dry run): ✓ Pass

## Phase 2: Test Repositories
- Test setup: ✓ Complete
- Graph includes test repos: ✓ Pass
- Updates detected: ✓ Pass

## Phase 3: End-to-End
- PR created: ✓ Pass
- Idempotency: ✓ Pass
- PR content correct: ✓ Pass

## Phase 4: Workflow
- Manual trigger: ✓ Pass
- Dry run: ✓ Pass
- Real run: ✓ Pass

## Issues Found
1. [Issue description] - [Resolution]

## Ready for Production
- [x] All tests passing
- [x] Documentation complete
- [x] Team trained
```

## Sources

- [Dependency Update Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md)
- [Setup Guide](setup.md)
- [Implementation Critique](../notes/2026-01-06-implementation-critique.md)
