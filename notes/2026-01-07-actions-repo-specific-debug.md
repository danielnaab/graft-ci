---
date: 2026-01-07
status: debugging
---

# Repository-Specific Actions Debugging

## Context

Forgejo Actions **work fine in another repository** but not in graft-ci. This means:
- ✅ Actions are enabled globally
- ✅ Runners are configured and working
- ✅ Forgejo version is correct
- ❌ Something specific to graft-ci is blocking Actions

## Debugging Checklist

### 1. Compare Repository Settings

**Working repo settings:**
- Go to working repo → Settings → Actions
- Note the exact settings enabled

**graft-ci settings:**
- Go to http://platform-vm.local/git/daniel/graft-ci/settings
- Repository → Actions section
- **Check:** "Enable Repository Actions" checkbox

**Likely fix:** Repository Actions might be disabled for graft-ci specifically.

### 2. Check .gitea vs .github Directory

**Question:** Which directory does the working repo use?
- `.github/workflows/` (GitHub compatibility mode)
- `.gitea/workflows/` (Forgejo native)

**Current status:** graft-ci uses `.gitea/workflows/`

**Test:** Also create `.github/workflows/` with same file and see if that works

### 3. Verify Workflow File is Committed

```bash
cd /home/coder/graft-ci
git log --oneline -5 -- .gitea/workflows/

# Check what's actually on the remote
git ls-tree -r main:.gitea/workflows/
```

### 4. Check Repository Permissions

**Working repo:**
- What are the repository permissions?
- Who is the owner?
- Is it a fork?

**graft-ci:**
- Owner: daniel
- Permissions: Check if there are any restrictive settings

### 5. Compare Workflow Syntax

**Working repo workflow:**
```bash
# SSH to platform-vm or use API to fetch
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/<WORKING_REPO>/contents/.gitea/workflows/
```

**Look for differences:**
- `runs-on` value
- Actions versions (e.g., `actions/checkout@v3` vs `@v4`)
- Trigger syntax
- Environment variable syntax

### 6. Check Webhook Configuration

**Working repo:**
- Settings → Webhooks
- Check if there's an Actions webhook

**graft-ci:**
- Settings → Webhooks
- Verify webhook exists and is active

### 7. Check Repository .gitattributes or .gitignore

Sometimes `.gitignore` or `.gitattributes` can prevent workflow files from being processed:

```bash
cd /home/coder/graft-ci
cat .gitignore | grep -i workflow
cat .gitattributes 2>/dev/null | grep -i workflow
```

### 8. Test with Minimal Workflow

**Created:** `.gitea/workflows/test-actions.yml`

**After pushing:**
1. Check Actions tab for "Test Actions" workflow
2. Try manual trigger via workflow_dispatch
3. Push a commit to main and see if it triggers

**If minimal workflow works:**
- Problem is in dependency-update.yml syntax
- Compare line by line with working repo workflow

**If minimal workflow doesn't work:**
- Repository-level configuration issue
- Focus on settings comparison

### 9. Check for Repository-Level Variables/Secrets

The workflow uses:
```yaml
env:
  FORGEJO_URL: ${{ vars.FORGEJO_URL || 'http://platform-vm.local/git' }}
```

**Check:**
- Does working repo define `vars.FORGEJO_URL`?
- Are repository variables causing the workflow to fail silently?

**Test:** Remove all variable references from minimal workflow

### 10. API Verification

Check if Forgejo API shows the workflow:

```bash
# List workflows
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/workflows

# Compare with working repo
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/<WORKING_REPO>/actions/workflows
```

## Quick Diagnostic Script

```bash
#!/bin/bash
# Run this on platform-vm or a machine with network access

FORGEJO_TOKEN="your-token-here"
REPO="graft-ci"
WORKING_REPO="name-of-working-repo"

echo "=== Comparing $REPO with $WORKING_REPO ==="

echo -e "\n1. Repository Actions enabled?"
curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$REPO" | \
  jq '.has_actions'

curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$WORKING_REPO" | \
  jq '.has_actions'

echo -e "\n2. Workflows detected?"
curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$REPO/actions/workflows" | \
  jq '.workflows[] | .name'

curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$WORKING_REPO/actions/workflows" | \
  jq '.workflows[] | .name'

echo -e "\n3. Recent workflow runs?"
curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$REPO/actions/runs" | \
  jq '.workflow_runs[] | {name: .name, status: .status, conclusion: .conclusion}'

curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  "http://platform-vm.local/git/api/v1/repos/daniel/$WORKING_REPO/actions/runs" | \
  jq '.workflow_runs[] | {name: .name, status: .status, conclusion: .conclusion}'
```

## Most Likely Causes

Based on "Actions work in another repo":

1. **Repository Actions disabled** (95% likely)
   - Go to Settings → Actions
   - Enable "Enable Repository Actions"

2. **Workflow directory mismatch** (3% likely)
   - Working repo uses `.github/workflows/`
   - graft-ci uses `.gitea/workflows/`
   - Try copying workflow to both directories

3. **Workflow syntax issue** (2% likely)
   - Some feature not supported in graft-ci's workflow
   - Test with minimal workflow first

## Next Steps

1. **Push minimal test workflow**
   ```bash
   cd /home/coder/graft-ci
   git add .gitea/workflows/test-actions.yml
   git commit -m "test: add minimal Actions workflow for debugging"
   git push origin main
   ```

2. **Check Actions tab in Forgejo UI**
   - Go to http://platform-vm.local/git/daniel/graft-ci/actions
   - Look for "Test Actions" workflow
   - Try manual trigger

3. **If minimal workflow works:**
   - Problem is in dependency-update.yml
   - Compare syntax with working repo
   - Simplify dependency-update.yml step by step

4. **If minimal workflow doesn't work:**
   - Check repository settings (Actions enabled?)
   - Compare API response with working repo
   - Check webhooks configuration

5. **Report findings:**
   - Which repo is working? (name)
   - What does its workflow look like?
   - What's different in the settings?

## Commands to Run

**From any machine with homelab network access:**

```bash
# 1. Check if repo has Actions enabled
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci | \
  jq '.has_actions'

# 2. Enable Actions via API if disabled
curl -X PATCH \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"has_actions": true}' \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci

# 3. List detected workflows
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/workflows | \
  jq '.workflows[] | {name: .name, path: .path, state: .state}'

# 4. Trigger workflow manually
WORKFLOW_ID=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/workflows | \
  jq -r '.workflows[0].id')

curl -X POST \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ref": "main"}' \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/workflows/$WORKFLOW_ID/dispatches
```
