---
date: 2026-01-09
status: debugging
---

# Why dependency-update.yml Doesn't Trigger

## Current Status

- ✅ Test Actions workflow visible and ran successfully (runs/1)
- ✅ dependency-update.yml is visible in Actions UI
- ❌ dependency-update.yml has ZERO invocations/runs
- ❌ Never triggered despite having `push` to main branch trigger

## The Mystery

Both workflows have the same trigger:
```yaml
on:
  push:
    branches:
      - main
```

**test-actions.yml:** Pushed today → Ran successfully
**dependency-update.yml:** Pushed Jan 7 → Never ran, even on subsequent pushes

## Possible Causes

### 1. Unsupported Syntax (Most Likely)

**Line 31-32 of dependency-update.yml:**
```yaml
env:
  FORGEJO_URL: ${{ vars.FORGEJO_URL || 'http://platform-vm.local/git' }}
  GRAFT_ORG: ${{ vars.GRAFT_ORG || 'daniel' }}
```

**Issues:**
- `vars` context is a newer GitHub Actions feature
- `||` operator for default values might not be supported in Forgejo
- If Forgejo can't parse this, the workflow might be visible but unable to run

**Test:** Created `dependency-update-simple.yml` with hardcoded values instead

### 2. Forgejo Only Runs One Workflow Per Push

**Hypothesis:** Maybe Forgejo limits to one workflow per trigger?

**Test:** After pushing `dependency-update-simple.yml`, check if:
- Only one workflow runs (test-actions OR dependency-update-simple)
- Or both run

If only one runs, Forgejo might have a single-workflow-per-push limitation.

### 3. Workflow Directory Priority

**Question:** Which directory did test-actions run from?

Check the UI to see the file path:
- `.github/workflows/test-actions.yml`
- `.gitea/workflows/test-actions.yml`
- `.forgejo/workflows/test-actions.yml`

**Hypothesis:** If Forgejo only reads from `.github/`, then workflows in `.gitea/` won't run.

**Current state:**
- test-actions.yml exists in all 3 directories
- dependency-update.yml only in `.gitea/` and `.forgejo/`

### 4. Workflow Disabled Flag

**Check:** In the Actions UI, is there a "disabled" indicator on dependency-update.yml?

Some CI systems allow workflows to be visible but disabled.

### 5. First Push After Workflow Added

**Timeline:**
- Jan 7: dependency-update.yml added
- Jan 7 - Jan 9: No pushes? (or pushes didn't trigger it)
- Jan 9: test-actions.yml added → Ran successfully

**Hypothesis:** Maybe there were no pushes between Jan 7 and Jan 9?

**Check git log:**
```bash
cd /home/coder/graft-ci
git log --oneline --since="2026-01-07" --until="2026-01-09" origin/main
```

## Diagnostic Steps

### Step 1: Check Which Directory Ran

In the Actions UI at http://platform-vm/git/daniel/graft-ci/actions/runs/1:
- Click on the "Test Actions" run
- Look at the workflow file path shown
- Note whether it's from `.github/`, `.gitea/`, or `.forgejo/`

### Step 2: Check If dependency-update-simple Runs

After the push we just did:
- Check if "Dependency Update (Simple)" appears and runs
- Check if BOTH test-actions and dependency-update-simple run
- Or if only one runs

### Step 3: Manual Trigger Test

Try manually triggering the original dependency-update.yml:
1. Go to http://platform-vm/git/daniel/graft-ci/actions
2. Click on "Dependency Update Automation"
3. Click "Run workflow"
4. Set dry_run = true
5. Click "Run workflow"

**If it runs:** Problem is with automatic triggers
**If it fails:** Check the error message for syntax issues

### Step 4: Compare Working vs Non-Working

Create a diff between test-actions (works) and dependency-update (doesn't):

**test-actions.yml:**
- Simple structure
- No `vars` context
- No `||` operators
- No secrets required initially
- Just echo commands

**dependency-update.yml:**
- Complex structure
- Uses `vars` context
- Uses `||` for defaults
- Requires secrets (FORGEJO_TOKEN, CODER_TOKEN)
- Complex bash scripts

### Step 5: Check Secrets

Maybe the workflow fails immediately because required secrets are missing?

**Required secrets:**
- `FORGEJO_TOKEN`
- `CODER_TOKEN`

**Check:** Repository Settings → Secrets → Actions

If secrets are missing, the workflow might fail before even appearing in runs.

## Testing Plan

### Test A: Simplified Workflow (Just Pushed)

**dependency-update-simple.yml** removes:
- `vars` context
- `||` operators
- `repository_dispatch` trigger
- `schedule` trigger
- Coder CLI steps
- Workspace creation

**Just does:**
- Checkout
- Install yq
- Build dependency graph
- Show result

**Expected:** Should trigger on this push and run successfully

### Test B: Manual Trigger Original

Try running dependency-update.yml manually via workflow_dispatch.

**Expected:** Will reveal if there are syntax errors or missing secrets

### Test C: Add Secrets

If CODER_TOKEN or FORGEJO_TOKEN are missing, add them:

1. Generate CODER_TOKEN:
   ```bash
   coder tokens create --name forgejo-actions --lifetime 8760h
   ```

2. Add to repo:
   - Settings → Secrets → Actions
   - Add `CODER_TOKEN`
   - Add `FORGEJO_TOKEN` (if not present)

## Expected Outcomes

### Outcome 1: dependency-update-simple runs

**Conclusion:** Original workflow has unsupported syntax
**Fix:** Update dependency-update.yml to remove `vars` and `||`

### Outcome 2: dependency-update-simple doesn't run

**Conclusion:** Forgejo might only read from one directory
**Fix:** Move all workflows to the directory that works

### Outcome 3: Manual trigger works, auto trigger doesn't

**Conclusion:** Issue with push trigger specifically
**Fix:** Use workflow_dispatch and schedule only

### Outcome 4: Manual trigger fails with error

**Conclusion:** Syntax error or missing secret
**Fix:** Read error message and fix accordingly

## Next Steps

1. **Check Actions UI** - Did dependency-update-simple trigger?
2. **Note which directory** - Which path did test-actions run from?
3. **Try manual trigger** - Does dependency-update.yml run manually?
4. **Check secrets** - Are FORGEJO_TOKEN and CODER_TOKEN configured?
5. **Report findings** - Share what happened with each test

## Quick Commands

```bash
# Check recent commits that should have triggered workflow
cd /home/coder/graft-ci
git log --oneline --since="2026-01-07" origin/main

# Check which workflows exist on remote
git ls-tree -r main:.github/workflows/
git ls-tree -r main:.gitea/workflows/
git ls-tree -r main:.forgejo/workflows/
```

## Resolution Paths

**If syntax issue:**
- Update dependency-update.yml to use simple env values
- Remove `vars` context usage
- Remove `||` operators

**If directory issue:**
- Standardize on one directory (likely `.github/`)
- Move all workflows there

**If secrets issue:**
- Add missing secrets to repository settings
- Verify secret names match exactly

**If trigger issue:**
- Remove push trigger, use only workflow_dispatch
- Trigger manually or via schedule
