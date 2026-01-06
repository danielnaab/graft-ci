---
date: 2026-01-06
status: working
---

# Testing Blocker - Token Scope for Repository Creation

## Issue

Cannot create test repositories via API due to insufficient token scope.

**Error**:
```json
{
  "message": "token does not have at least one of required scope(s): [write:user]",
  "url": "http://192.168.1.51/git/api/swagger"
}
```

## Current Token Scopes

The token `766f3e650b14bca1063b0ddf3a16740634121905` has:
- ✓ `read:user` - Can read user information
- ✓ `read:org` - Can read organization data
- ✓ `repo` (read access) - Can fetch repository contents
- ✗ `write:user` - **MISSING** - Required to create repositories
- ? `repo` (write access) - Unknown if includes PR creation

## Impact

**Phase 2 Testing Blocked**: Cannot create test repositories to validate:
- Real PR creation (non-dry-run)
- Idempotency testing
- End-to-end workflow validation

**Workarounds**:
1. Create repositories manually via Forgejo UI
2. Generate new token with additional scopes
3. Skip Phase 2, proceed to Phase 4 (workflow testing with existing repos)

## Required Scopes for Full Testing

For complete graft-ci functionality:

| Scope | Purpose | Current Status |
|-------|---------|----------------|
| `read:user` | Read user info, list repos | ✓ Have |
| `read:org` | Read organization data | ✓ Have |
| `repo` (read) | Fetch graft.yaml, check repos | ✓ Have |
| `repo` (write) | Create PRs, push branches | ? Unknown |
| `write:user` | Create test repositories | ✗ Missing |

## Recommendation

### Option 1: Manual Repository Creation (Quickest)

Create test repositories via Forgejo UI:
1. Go to Forgejo → New Repository
2. Create:
   - `test-upstream-a` (empty repo with README)
   - `test-upstream-b` (empty repo with README)
   - `test-consumer` (empty repo, will add graft.yaml)
3. Continue testing with existing approach

### Option 2: New Token with All Scopes (Most Complete)

Generate new token with all scopes:
- `repo` - Full repository access (read + write)
- `write:user` - Create repositories
- `read:user` - Read user information
- `read:org` - Read organization data

This enables fully automated testing including repository creation.

### Option 3: Skip to Phase 4 (Alternative Path)

Skip test repository creation and proceed directly to:
- Configure Forgejo Actions workflow in graft-ci
- Test workflow with existing real repositories
- Monitor first automated PR in production

**Risk**: Less isolated testing, but validates real-world usage immediately.

## What We Can Test Now

Even without creating new repositories, we can:
1. ✓ Test update detection on existing repos (already done)
2. ✓ Test PR creation in dry-run mode (already done)
3. Test Forgejo Actions workflow configuration
4. Test manual workflow triggers
5. Monitor actual PR creation when real updates occur

## Next Steps

Awaiting user decision:
- [ ] Create test repos manually and provide names
- [ ] Generate new token with `write:user` scope
- [ ] Skip Phase 2, proceed to workflow configuration

## References

- [Forgejo API Token Documentation](https://forgejo.org/docs/latest/api/)
- [Testing Plan Phase 2](../docs/testing-plan.md#phase-2-test-repository-setup)
