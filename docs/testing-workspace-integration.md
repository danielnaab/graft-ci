---
title: "Testing Workspace Integration Locally"
status: working
---

# Testing Workspace Integration Locally

This guide explains how to test the workspace-based dependency update automation locally, independent of Forgejo Actions.

## Prerequisites

1. **Coder CLI** installed and authenticated:
   ```bash
   curl -fsSL https://coder.com/install.sh | sh
   coder login http://192.168.1.51:7080
   ```

2. **Environment variables** configured:
   ```bash
   export FORGEJO_TOKEN="<your-forgejo-token>"
   export FORGEJO_URL="http://platform-vm.local/git"
   export CODER_URL="http://192.168.1.51:7080"
   export GRAFT_ORG="daniel"
   ```

3. **Required tools** available:
   - `jq` - JSON processing
   - `yq` - YAML processing
   - `git` - Version control
   - `curl` - HTTP requests

## Test 1: Build Dependency Graph

Test the graph builder to ensure it correctly scans repositories:

```bash
cd /home/coder/graft-ci

./src/graph-builder.sh > test-graph.json

# Verify output
cat test-graph.json | jq .

# Expected: JSON object mapping upstream repos to consumers
# Example:
# {
#   "graft-knowledge": ["graft", "graft-ci", "homelab"],
#   "meta-knowledge-base": ["graft-ci"]
# }
```

**Success criteria:**
- Returns valid JSON
- All repositories with graft.yaml are included
- Consumers are correctly mapped

## Test 2: Check for Updates

Test update detection for a specific upstream:

```bash
cd /home/coder/graft-ci

# Check updates for graft-knowledge
./src/check-updates.sh graft-knowledge test-graph.json > test-updates.json

# View results
cat test-updates.json | jq .

# Expected: JSON array of updates (may be empty if all up to date)
# Example:
# [
#   {
#     "consumer": "graft-ci",
#     "dep_name": "graft-knowledge",
#     "old_sha": "abc123...",
#     "new_sha": "def456...",
#     "git_url": "ssh://forgejo@platform-vm:2222/daniel/graft-knowledge.git"
#   }
# ]
```

**Success criteria:**
- Returns valid JSON array
- Correctly detects version differences
- If no updates, returns `[]`

## Test 3: Manual Workspace Creation

Test creating a workspace manually before running the full workflow:

```bash
# Create a test workspace
coder create test-graft-ci-deps-graft-knowledge \
  --template repo-generic \
  --parameter "repo_url=ssh://forgejo@platform-vm:2222/daniel/graft-ci.git" \
  --parameter "git_name=graft-ci-bot" \
  --parameter "git_email=graft-ci-bot@homelab.local" \
  --parameter "enable_claude=false" \
  --parameter "enable_codex=false" \
  --stop-after 2h \
  --yes

# Wait for workspace to be ready
sleep 30

# Verify workspace is running
coder list | grep test-graft-ci

# SSH into workspace to verify it's set up correctly
coder ssh test-graft-ci-deps-graft-knowledge -- "ls -la ~/ && cd ~/graft-ci && git status"

# Clean up
coder delete test-graft-ci-deps-graft-knowledge --yes
```

**Success criteria:**
- Workspace creates without errors
- Repository is cloned
- Git is configured
- Can execute commands via SSH

## Test 4: Workspace Upgrade Script (Dry Run)

Create a test updates.json file and run the workspace upgrade script:

```bash
cd /home/coder/graft-ci

# Create test updates file (modify SHAs as needed)
cat > test-updates.json <<'EOF'
[
  {
    "consumer": "graft-ci",
    "dep_name": "meta-knowledge-base",
    "old_sha": "abc123abc123abc123abc123abc123abc123abc1",
    "new_sha": "def456def456def456def456def456def456def4",
    "git_url": "http://platform-vm.local/git"
  }
]
EOF

# Test workspace creation (will fail on graft upgrade if SHAs are fake)
# This tests workspace orchestration logic
./src/workspace-upgrade.sh test-updates.json 2>&1 | tee test-workspace-output.log

# Check output
cat test-workspace-output.log

# Expected behavior:
# - Workspace created
# - Execution script runs
# - May fail at graft upgrade if SHAs are fake (expected)
# - Workspace remains available for debugging

# Check if workspace was created
coder list | grep graft-ci-deps

# Clean up
coder delete graft-ci-deps-meta-knowledge-base --yes 2>/dev/null || true
rm test-updates.json test-workspace-output.log
```

**Success criteria:**
- Script parses JSON correctly
- Workspace is created
- Execution script is transferred and run
- Errors are captured and logged

## Test 5: In-Workspace Execution Script

Test the execution script inside a workspace manually:

```bash
# Create a workspace manually
coder create test-upgrade-workspace \
  --template repo-generic \
  --parameter "repo_url=ssh://forgejo@platform-vm:2222/daniel/graft-ci.git" \
  --parameter "git_name=graft-ci-bot" \
  --parameter "git_email=graft-ci-bot@homelab.local" \
  --yes

sleep 30

# Transfer environment variables and run execution script
coder ssh test-upgrade-workspace -- bash -c "
  export FORGEJO_TOKEN='$FORGEJO_TOKEN'
  export FORGEJO_URL='$FORGEJO_URL'
  export GRAFT_ORG='$GRAFT_ORG'
  export CODER_URL='$CODER_URL'

  # Test with fake data (will fail at graft upgrade)
  bash -s graft-ci meta-knowledge-base abc123 def456 http://platform-vm.local/git '{}'
" < /home/coder/graft-ci/src/workspace-upgrade-exec.sh

# Clean up
coder delete test-upgrade-workspace --yes
```

**Success criteria:**
- Script receives arguments correctly
- Attempts to install graft (if not present)
- Error messages are clear and actionable

## Test 6: Full End-to-End (Safe Test)

Run a complete test with real data but without creating PRs:

```bash
cd /home/coder/graft-ci

# 1. Build graph
./src/graph-builder.sh > e2e-graph.json

# 2. Check for updates (pick an upstream that likely has updates)
./src/check-updates.sh graft-knowledge e2e-graph.json > e2e-updates.json

# 3. Check if there are any updates
UPDATE_COUNT=$(cat e2e-updates.json | jq 'length')
echo "Found $UPDATE_COUNT updates"

if [ "$UPDATE_COUNT" -gt 0 ]; then
  echo "Running workspace upgrade..."

  # Run workspace upgrade
  ./src/workspace-upgrade.sh e2e-updates.json > e2e-results.json 2>&1

  echo "Results:"
  cat e2e-results.json | jq .

  echo ""
  echo "Check workspaces:"
  coder list | grep deps

  echo ""
  echo "Check PRs created (if any):"
  curl -s -H "Authorization: token $FORGEJO_TOKEN" \
    "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/graft-ci/pulls?state=open" | \
    jq -r '.[] | select(.head.ref | startswith("deps/")) | "PR #\(.number): \(.title)"'
else
  echo "No updates available - all dependencies up to date"
fi

# Clean up
rm -f e2e-*.json
```

**Success criteria:**
- Complete workflow runs without errors
- Workspaces are created
- PRs are created in Forgejo (if updates exist)
- Workspace URLs are included in PR descriptions

## Test 7: PR Update Logic

Test that successive updates to the same dependency update the existing PR:

```bash
# This test requires manually creating a scenario with successive commits

# 1. Create a PR for a dependency (use Test 6)
# 2. Make a new commit to the upstream repository
# 3. Run workspace upgrade again
# 4. Verify that:
#    - Existing PR is detected
#    - Workspace is reused
#    - PR is force-pushed with new commit
#    - PR title/body are updated
#    - Comment is added about the new upstream commit
```

**Success criteria:**
- Existing PR is detected correctly
- No duplicate PRs created
- PR is updated with new commit info
- Force-push succeeds

## Test 8: Stale PR Cleanup

Test that PRs are closed when main branch already has a newer version:

```bash
# This test requires a manual scenario:

# 1. Create a PR for dependency X → version A
# 2. Manually merge a different PR updating to version B (newer)
# 3. Run workspace upgrade for dependency X → version C
# 4. Verify that:
#    - PR for version A is detected as stale
#    - PR is closed with explanation comment
#    - Workspace is deleted
#    - New PR is created for version C
```

**Success criteria:**
- Stale PR detection works correctly
- PRs are closed with clear explanation
- Workspaces are cleaned up
- New PR created for latest version

## Test 9: Work Preservation

Test that workspaces with uncommitted changes are preserved:

```bash
# 1. Create a workspace via update process
# 2. SSH into workspace and make changes:
coder ssh {workspace-name} -- bash -c "
  cd ~/graft-ci
  echo '# Test change' >> README.md
  # Don't commit
"

# 3. Run workspace upgrade again for same dependency with new upstream commit
# 4. Verify that:
#    - Workspace changes are detected
#    - Workspace is NOT force-pushed
#    - PR comment is added about new version available
#    - User can manually merge the work
```

**Success criteria:**
- Uncommitted changes are detected
- Workspace is preserved (no force-push)
- PR is updated with helpful comment
- User retains control

## Troubleshooting

### "coder: command not found"

Install Coder CLI:
```bash
curl -fsSL https://coder.com/install.sh | sh
```

### "401 Unauthorized" from Coder

Login to Coder:
```bash
coder login http://192.168.1.51:7080
```

### "FORGEJO_TOKEN not set"

Export the token:
```bash
export FORGEJO_TOKEN="<your-forgejo-token>"
```

### Workspace creation hangs

Check Coder service status:
```bash
ssh daniel@192.168.1.51 'systemctl status coder'
```

### "graft: command not found" in workspace

This is expected on first run. The execution script installs graft automatically.

### PR creation fails with 404

Verify Forgejo URL is correct:
```bash
curl -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/user"
```

## Cleanup

After testing, clean up resources:

```bash
# Delete test workspaces
coder list | grep test- | awk '{print $1}' | xargs -I {} coder delete {} --yes

coder list | grep -deps- | awk '{print $1}' | xargs -I {} coder delete {} --yes

# Close test PRs (if any)
# Manual: Go to Forgejo UI and close PRs with title starting with "chore(deps):"

# Remove test files
rm -f test-*.json e2e-*.json
```

## Next Steps

Once local testing is successful:

1. **Create CODER_TOKEN secret** in Forgejo:
   - Generate token: `coder tokens create --name forgejo-actions --lifetime 8760h`
   - Add to: http://platform-vm.local/git/daniel/graft-ci/settings/secrets

2. **Debug Forgejo Actions** to get workflows running

3. **Test via workflow trigger** once Actions is working

4. **Monitor first production run** and verify behavior

## Reference

- Plan file: `/home/coder/.claude/plans/glistening-kindling-quokka.md`
- Specification: `/home/coder/graft-knowledge/docs/specification/dependency-update-notification.md`
- Workflow: `/home/coder/graft-ci/.forgejo/workflows/dependency-update.yml`
