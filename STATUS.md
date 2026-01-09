# Graft-CI Workspace Integration - Current Status

**Date:** 2026-01-09
**Status:** Implementation Complete, Workflow Debugging In Progress

## Summary

The workspace-based dependency update automation has been **fully implemented and security hardened**, but the Forgejo Actions workflow is **not yet operational** due to workflow triggering issues.

## ✅ What's Complete

### 1. Core Implementation (Commits: e439c7e, 8cdc65d)

**Files:**
- `src/workspace-upgrade.sh` (468 lines) - Workspace orchestration
- `src/workspace-upgrade-exec.sh` (296 lines) - In-workspace execution
- `.forgejo/workflows/dependency-update.yml` (189 lines) - CI/CD workflow

**Features:**
- ✅ Workspace creation per dependency update
- ✅ Graft upgrade execution in isolated environment
- ✅ PR creation with workspace URL
- ✅ PR update/reuse logic with work preservation
- ✅ Stale PR cleanup
- ✅ Fail-safe workspace change detection

### 2. Security & Safety Improvements (Commit: 8cdc65d)

**Critical fixes applied:**
- ✅ Secure token passing via `--env` flags (not visible in ps/top)
- ✅ Workspace readiness validation with SSH connectivity checks
- ✅ Fail-safe `workspace_has_changes()` prevents accidental work loss
- ✅ Repository clone validation
- ✅ graft.lock validation before committing
- ✅ Input validation for all required environment variables
- ✅ Constants for timeouts and retry attempts

### 3. Specification Updates (Commit: 36895b2)

**Updated:** `/home/coder/graft-knowledge/docs/specification/dependency-update-notification.md`

Added comprehensive documentation for:
- PR Update and Lifecycle Strategy
- Work preservation (LLM token protection)
- Stale PR detection and cleanup
- Workspace integration architecture

### 4. Documentation

**Comprehensive guides created:**
- `docs/testing-workspace-integration.md` - Local testing procedures (9 test scenarios)
- `notes/2026-01-07-implementation-critique.md` - 18 issues identified across 8 categories
- `notes/2026-01-07-testing-limitation.md` - Network isolation blocker
- `notes/2026-01-09-coder-auth-alternatives.md` - 8 token rotation solutions
- `notes/2026-01-09-workflow-not-triggering.md` - Debugging analysis

## ❌ Current Blocker

### Forgejo Actions Workflow Not Running

**Symptom:** `dependency-update.yml` visible in Actions UI but has never executed.

**Root cause identified:** The `||` operator for default values is not supported:
```yaml
# This doesn't work in Forgejo:
env:
  FORGEJO_URL: ${{ vars.FORGEJO_URL || 'http://platform-vm.local/git' }}
```

**Fixed:** Changed to simple hardcoded values (Commit: 0fe4696)

**Remaining issue:** Workflow still won't trigger on push events, even though:
- ✅ Syntax is valid (other test workflows ran successfully)
- ✅ Push trigger is defined
- ✅ File is in `.forgejo/workflows/` directory
- ✅ FORGEJO_TOKEN secret exists
- ✅ CODER_TOKEN secret exists (max 168h lifetime)

**Theory:** Forgejo may require workflows to successfully run once before they can be manually triggered, creating a chicken-and-egg problem.

## 🔧 Current Configuration

### Workflow Location
**Single source of truth:** `.forgejo/workflows/dependency-update.yml`

All test artifacts cleaned up:
- Removed `.github/workflows/`
- Removed `.gitea/workflows/`
- Removed test workflows (test-actions, test-no-secrets, dependency-update-v2, etc.)

### Workflow Triggers

```yaml
on:
  # TEMPORARY: Push trigger to initialize workflow
  push:
    branches:
      - main

  # Webhook trigger for organization push events
  repository_dispatch:
    types: [org_push]

  # Scheduled fallback (weekly Monday 2am)
  schedule:
    - cron: '0 2 * * 1'

  # Manual trigger
  workflow_dispatch:
    inputs:
      upstream_repo:
        type: string
      dry_run:
        type: boolean
        default: true
```

### Required Secrets

**Configured in Forgejo:**
- ✅ `FORGEJO_TOKEN` - API access (permanent)
- ✅ `CODER_TOKEN` - Workspace management (max 168h, requires weekly rotation)

## 🎯 Next Steps

### Option 1: Wait for Scheduled Run
Wait until Monday 2am for the cron schedule to trigger the workflow for the first time.

**Pros:** No intervention needed
**Cons:** Delays testing by several days

### Option 2: Debug Push Trigger
Investigate why the push trigger isn't working:
- Check Forgejo server logs for workflow parsing errors
- Verify webhook configuration for push events
- Compare with a minimal working workflow

**Required:** SSH access to platform-vm to check logs

### Option 3: Use Repository Dispatch
Set up webhook to trigger via `repository_dispatch` instead:
- Configure organization-level webhook
- Test dispatch event manually via API

### Option 4: Accept Manual API Triggering
Use Forgejo API to trigger workflow until UI button appears:
```bash
curl -X POST \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ref": "main", "inputs": {"dry_run": "true"}}' \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/workflows/dependency-update.yml/dispatches
```

## ⚠️ Known Limitations

### 1. Coder Token Rotation (168h Max)
**Impact:** Requires manual token rotation every 7 days

**Mitigations:**
- Workflow validates token and provides clear error messages
- Schedule reduced to weekly (reduces token usage)
- Calendar reminder needed for rotation

**Long-term solutions researched:** See `notes/2026-01-09-coder-auth-alternatives.md`

### 2. Local Testing Not Possible
**Reason:** Claude Code workspace has no network access to homelab infrastructure

**Impact:** Cannot run local tests from this environment

**Workaround:** Testing must be done via:
- Forgejo Actions (once workflow runs)
- Machine with homelab network access
- SSH into platform-vm

### 3. Forgejo Actions UI Limitations
**Discovered:** Manual trigger button may not appear until workflow runs once

**Impact:** Creates bootstrapping problem for new workflows

## 📊 Code Quality Metrics

**Total code written:** 954 lines (scripts + workflow)
**Documentation:** 1,800+ lines across 8 files
**Security issues fixed:** 4 critical, 4 high priority
**Test scenarios documented:** 9 comprehensive tests

## 🔐 Security Posture

**Before improvements:**
- ❌ Tokens visible in process listings
- ❌ No workspace readiness validation
- ❌ Risk of accidental work loss via force-push
- ❌ No input validation

**After improvements:**
- ✅ Secure credential passing
- ✅ Robust error handling
- ✅ Fail-safe work preservation
- ✅ Comprehensive validation

## 📁 Repository Structure

```
graft-ci/
├── .forgejo/
│   └── workflows/
│       └── dependency-update.yml          # Production workflow
├── src/
│   ├── workspace-upgrade.sh               # Orchestration (468 lines)
│   ├── workspace-upgrade-exec.sh          # Execution (296 lines)
│   ├── graph-builder.sh                   # Existing
│   ├── check-updates.sh                   # Existing
│   └── create-pr.sh                       # Legacy (replaced by workspace integration)
├── docs/
│   └── testing-workspace-integration.md   # Test procedures
├── notes/
│   ├── 2026-01-07-implementation-critique.md
│   ├── 2026-01-07-testing-limitation.md
│   ├── 2026-01-09-coder-auth-alternatives.md
│   ├── 2026-01-09-workflow-not-triggering.md
│   └── 2026-01-09-session-summary.md
└── STATUS.md                              # This file
```

## 🎓 Lessons Learned

### Forgejo vs GitHub Actions Compatibility

**Supported:**
- ✅ `workflow_dispatch` with typed inputs (`boolean`, `string`, etc.)
- ✅ `vars` context for repository variables
- ✅ `secrets` context
- ✅ Standard triggers (push, schedule, repository_dispatch)

**NOT Supported:**
- ❌ `||` operator for default values: `${{ vars.X || 'default' }}`
- ❌ Possibly other GitHub Actions expressions not documented

**Recommendation:** Use simple, explicit values instead of complex expressions.

### Debugging Strategy

**Effective approaches:**
1. Create minimal test workflows to isolate issues
2. Test one feature at a time (triggers, inputs, secrets)
3. Check which directory workflows actually run from
4. Use API as fallback when UI doesn't work

**Ineffective approaches:**
1. Creating multiple workflow copies across directories (causes confusion)
2. Assuming GitHub Actions syntax works identically
3. Relying on UI when API provides more control

## 💡 Recommendations

### Immediate (Next Session)
1. **Trigger workflow via API** to get first successful run
2. **Verify manual trigger button appears** after first run
3. **Test with dry_run=true** to validate dependency graph building
4. **Remove push trigger** once workflow is operational

### Short-term (Next Week)
1. **Set up CODER_TOKEN rotation reminder** (every Monday)
2. **Configure repository_dispatch webhook** for automatic triggers
3. **Test full workspace integration** with actual PR creation
4. **Monitor first production run** and iterate based on results

### Long-term (Next Month)
1. **Research Coder service accounts** for longer-lived authentication
2. **Add monitoring** for token expiration warnings
3. **Optimize workflow** based on production usage patterns
4. **Consider automated token rotation** if manual becomes too burdensome

## 🎯 Success Criteria (Not Yet Met)

- [ ] Workflow runs successfully (blocked on trigger issue)
- [ ] Manual trigger button appears in UI
- [ ] Dry-run mode works (graph building, update detection)
- [ ] Workspace creation succeeds
- [ ] PR creation with workspace URL works
- [ ] Token rotation process is sustainable

## 📞 Support Resources

**Forgejo Actions Documentation:**
https://forgejo.org/docs/next/user/actions/

**Coder CLI Documentation:**
https://coder.com/docs/cli

**Repository Issues:**
http://platform-vm/git/daniel/graft-ci/issues

**Related Specification:**
/home/coder/graft-knowledge/docs/specification/dependency-update-notification.md
