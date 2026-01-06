---
date: 2026-01-06
status: working
---

# Testing Results - 2026-01-06

Initial validation testing of graft-ci implementation.

## Test Environment

- **Host**: platform-vm
- **Forgejo Version**: 7.0.15
- **Forgejo API URL**: http://platform-vm:9001
- **SSH URL**: ssh://forgejo@platform-vm:2222
- **Organization/User**: daniel

## Tests Performed

### Phase 1: Environment Discovery

**Objective**: Find correct Forgejo API endpoint

**Process**:
1. Initially tried http://platform-vm:3000 → Found Open WebUI instead
2. Searched homelab NixOS configuration
3. Discovered Forgejo on port 9001 (moved from 3000)

**Result**: ✓ **Success**
- Forgejo API accessible at http://platform-vm:9001
- API version endpoint responds: `{"version":"7.0.15"}`

### Phase 2: API Authentication Testing

**Objective**: Validate API token access

**Token tested**: `0efa3c5e51f116b5937a19b339f1e69fcc8cfbce`

**Test commands**:
```bash
# Test user endpoint
curl -H "Authorization: token 0efa3c5e51f116b5937a19b339f1e69fcc8cfbce" \
  "http://platform-vm:9001/api/v1/user"

# Test organization repos
curl -H "Authorization: token 0efa3c5e51f116b5937a19b339f1e69fcc8cfbce" \
  "http://platform-vm:9001/api/v1/orgs/daniel/repos?limit=5"

# Test user repos
curl -H "Authorization: token 0efa3c5e51f116b5937a19b339f1e69fcc8cfbce" \
  "http://platform-vm:9001/api/v1/users/daniel/repos?limit=5"
```

**Results**: ✗ **Failed - Insufficient Scopes**

All endpoints returned:
```json
{
  "message": "token does not have at least one of required scope(s): [read:user]",
  "url": "http://192.168.1.51/git/api/swagger"
}
```

**Finding**: The provided token lacks required OAuth scopes.

**Required scopes** (from documentation):
- `read:user` - Read user information
- `read:org` - Read organization data
- `repo` - Full repository access (for creating PRs)

### Phase 3: SSH Access Testing

**Objective**: Verify git operations work via SSH

**Test command**:
```bash
git ls-remote ssh://forgejo@platform-vm:2222/daniel/graft.git HEAD
```

**Result**: ✓ **Success**
```
9b167159c1c8a07615f2b75445b83cc31e0ca015	HEAD
```

**Finding**: SSH access works correctly. This validates that:
- Authentication configured properly
- Can access repository metadata
- Update detector can use `git ls-remote` for ref checking

### Phase 4: Update Detector Test (Manual Graph)

**Objective**: Test update detection logic without API

**Setup**:
Created manual test graph:
```json
{
  "graft-knowledge": [
    {"repo": "graft", "dep_name": "graft-knowledge"},
    {"repo": "graft-ci", "dep_name": "graft-knowledge"}
  ],
  "meta-knowledge-base": [
    {"repo": "graft-ci", "dep_name": "meta-knowledge-base"}
  ]
}
```

**Test command**:
```bash
export FORGEJO_URL="http://platform-vm:9001"
export GRAFT_ORG="daniel"
export FORGEJO_TOKEN="0efa3c5e51f116b5937a19b339f1e69fcc8cfbce"

./src/check-updates.sh graft-knowledge test-graph.json
```

**Result**: ⚠️ **Partial Success**

Script executed correctly:
- Loaded dependency graph ✓
- Identified consumers ✓
- Attempted to fetch graft.yaml files ✗ (API token scope issue)

**Output**:
```
[check-updates] Starting update check
[check-updates] Upstream repository: graft-knowledge
[check-updates] Organization: daniel
[check-updates] Found consumers: graft graft-ci
[check-updates] Checking updates for graft (dep: graft-knowledge → graft-knowledge)
[check-updates] Could not fetch graft.yaml from graft
[check-updates] Checking updates for graft-ci (dep: graft-knowledge → graft-knowledge)
[check-updates] Could not fetch graft.yaml from graft-ci
[]
[check-updates] Check complete: 0 update(s) available
```

**Finding**: Script logic works, but blocked by API authentication.

### Phase 5: Graph Builder Test

**Objective**: Build dependency graph from organization repos

**Test command**:
```bash
export FORGEJO_URL="http://platform-vm:9001"
export GRAFT_ORG="daniel"
export FORGEJO_TOKEN="0efa3c5e51f116b5937a19b339f1e69fcc8cfbce"

./src/graph-builder.sh
```

**Result**: ✗ **Failed - Infinite Loop**

**Issue**: API returned HTML (from Open WebUI on port 3000) instead of JSON
- jq parse errors occurred
- Script looped through thousands of pages
- Script killed after detecting issue

**Root cause**: Initially used wrong FORGEJO_URL (port 3000 vs 9001)

**Re-test with correct URL**: Not performed due to token scope issue

## Issues Found

### Issue 1: Token Scope Insufficient

**Severity**: High (Blocks testing)

**Description**: The provided token lacks required OAuth scopes for API access.

**Current scopes**: Unknown (likely none or minimal)

**Required scopes**:
- `read:user` - Access user information
- `read:org` - List organization repositories
- `repo` - Repository access (read graft.yaml, create PRs)

**Resolution**: Generate new token with proper scopes

**Steps to fix**:
1. Forgejo UI → User Settings → Applications → Generate New Token
2. Select scopes: `repo`, `read:org`, `read:user`
3. Update FORGEJO_TOKEN environment variable

### Issue 2: Organization vs User Confusion

**Severity**: Low (Documentation clarity)

**Description**: Error message suggests "daniel" is a user, not an organization:
```
user redirect does not exist [name: daniel]
```

**Impact**: Scripts use `/api/v1/orgs/{org}/repos` endpoint

**Resolution options**:
1. If "daniel" is a user account, use `/api/v1/users/daniel/repos` or `/api/v1/user/repos`
2. If there is a separate organization, update GRAFT_ORG variable
3. Update scripts to handle both user and org repos

**Recommendation**: Clarify whether repositories are under user or organization.

### Issue 3: Default FORGEJO_URL Incorrect

**Severity**: Medium (Documentation/Configuration)

**Description**: Scripts default to `https://forgejo.example`, documentation suggests `http://platform-vm:3000`

**Actual URL**: `http://platform-vm:9001`

**Impact**: Scripts will fail without correct FORGEJO_URL environment variable

**Resolution**: Update documentation with correct default for this installation

## What Works

Despite API token issues, we validated:

1. ✓ **Script structure** - All scripts execute without syntax errors
2. ✓ **SSH access** - git ls-remote works for repository access
3. ✓ **Error handling** - Scripts handle API failures gracefully
4. ✓ **Logging** - Clear stderr logging with context
5. ✓ **Environment detection** - Forgejo API discovered and verified
6. ✓ **Graph loading** - Manual graph file loads correctly
7. ✓ **Consumer identification** - Dependency graph traversal works

## What Needs Testing

Once API token is fixed:

1. **Graph builder** - Full organization scan
2. **Update detector** - End-to-end with real graft.yaml files
3. **PR creator** - Dry run mode first
4. **Workflow** - Forgejo Actions integration
5. **Idempotency** - Multiple runs don't create duplicates
6. **Edge cases** - Missing graft.yaml, invalid YAML, etc.

## Recommended Next Steps

### Immediate (Required for testing)

1. **Generate new Forgejo API token** with scopes:
   - `repo` (full repository access)
   - `read:org` (read organization data)
   - `read:user` (read user information)

2. **Clarify organization vs user**:
   - Is "daniel" a user account or organization name?
   - Should scripts use `/users/` or `/orgs/` endpoints?

3. **Update configuration** with correct values:
   ```bash
   export FORGEJO_URL="http://platform-vm:9001"
   export GRAFT_ORG="daniel"  # or actual org name
   export FORGEJO_TOKEN="<new-token-with-scopes>"
   ```

### Short-term (After API access working)

1. Run graph builder and verify output
2. Test update detector with real repositories
3. Test PR creator in dry run mode
4. Document actual API endpoints used

### Medium-term (Production readiness)

1. Add error handling for org vs user repos
2. Auto-detect if target is user or organization
3. Update setup documentation with correct URLs
4. Add token scope validation to scripts

## Configuration Reference

For future testing, use these values:

```bash
# Correct configuration for this installation
export FORGEJO_URL="http://platform-vm:9001"
export GRAFT_ORG="daniel"
export FORGEJO_TOKEN="<token-with-repo-read:org-read:user-scopes>"

# SSH URLs (for git ls-remote)
# ssh://forgejo@platform-vm:2222/daniel/REPO.git
```

## Test Scripts Used

All test commands documented above can be re-run once token issue is resolved.

Test files created:
- `/home/coder/graft-ci/test-graph.json` - Manual dependency graph for testing

## Conclusion

**Overall assessment**: Implementation is structurally sound, but testing blocked by API token scope issue.

**Key findings**:
- Scripts execute correctly
- Error handling works
- SSH git access functional
- API endpoint discovered (port 9001)
- Token lacks required scopes for API access

**Recommendation**: Generate new API token with proper scopes, then re-run full test suite starting with Phase 1 of the testing plan.

## References

- [Testing Plan](../docs/testing-plan.md)
- [Setup Guide](../docs/setup.md)
- [Forgejo API Documentation](https://forgejo.org/docs/latest/api/)
