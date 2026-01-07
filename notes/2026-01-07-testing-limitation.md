---
date: 2026-01-07
status: blocked
---

# Local Testing Limitation

## Issue

Cannot perform local tests from this Claude Code workspace environment because the homelab infrastructure (platform-vm.local) is not accessible from this network context.

## Error

```
curl: (6) Could not resolve host: platform-vm.local
```

## Root Cause

The testing guide in `docs/testing-workspace-integration.md` assumes execution from a development machine with network access to:
- `platform-vm.local` (Forgejo server at http://platform-vm.local/git)
- `192.168.1.51:7080` (Coder server)
- `platform-vm:2222` (Forgejo SSH)

The Claude Code workspace is isolated and doesn't have routes to the homelab network.

## Work Completed

✅ **Phase 1 Critical Fixes (Committed: 8cdc65d)**

All critical security and safety improvements identified in the implementation critique have been implemented and committed:

### Security Improvements
- Pass FORGEJO_TOKEN and sensitive data via `--env` flags (not visible in process listings)
- Secure credential passing through coder ssh

### Robustness Improvements
- Added `wait_for_workspace_ready()` with actual SSH connectivity verification
- Added repository clone validation
- Added graft.lock validation before committing
- Added input validation for required environment variables

### Error Handling Improvements
- Made `workspace_has_changes()` fail-safe (assumes has changes if unable to check)
- Added proper error messages and exit codes
- Added constants for timeouts and retry attempts

### Code Quality
- Comprehensive comments explaining fail-safe behavior
- Updated documentation
- Standardized error checking patterns

## Testing Options

### Option 1: Test from Homelab-Connected Machine
Run the tests from a machine that can reach the homelab network:
```bash
ssh daniel@192.168.1.51
cd /path/to/graft-ci
# Follow docs/testing-workspace-integration.md
```

### Option 2: Test via Forgejo Actions (Recommended)
Once Forgejo Actions is working, the workflow will run in an environment with proper network access. This is the **intended deployment method** anyway.

**Next steps:**
1. Debug why Forgejo Actions workflows aren't running
2. Test the workspace integration via CI/CD pipeline
3. Iterate based on real-world results

### Option 3: Mock Testing
Could potentially mock the API responses for unit testing, but integration testing requires real infrastructure.

## Recommendation

Focus on **Option 2: Debug Forgejo Actions** since:
- That's the intended deployment environment
- Will have proper network access
- Tests the complete end-to-end flow
- More valuable than local testing from dev machine

## Status

- ✅ Phase 1 fixes: Complete and committed
- ❌ Local testing: Blocked by network isolation
- ⏳ Next: Debug Forgejo Actions to enable CI/CD testing
