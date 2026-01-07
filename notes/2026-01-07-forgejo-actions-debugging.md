---
date: 2026-01-07
status: debugging
---

# Forgejo Actions Debugging Guide

## Problem

Workflow file exists at `.gitea/workflows/dependency-update.yml` but the Actions tab in Forgejo shows no workflows or runs.

## Symptoms

- Push events to main branch don't trigger workflow
- Actions tab appears empty
- No workflow runs visible in UI

## Potential Root Causes

### 1. Forgejo Actions Not Enabled Globally

**Check:** Forgejo instance configuration on platform-vm

**Location:** `/etc/forgejo/app.ini` or equivalent

**Required settings:**
```ini
[actions]
ENABLED = true
```

**How to verify:**
```bash
ssh platform-vm
sudo cat /etc/forgejo/app.ini | grep -A 5 "\[actions\]"
```

### 2. No Actions Runners Configured

Even if Actions are enabled, there must be at least one runner registered and available.

**How to check:**
1. Login to Forgejo as admin: http://platform-vm.local/git
2. Go to Site Administration → Actions → Runners
3. Verify at least one runner is online

**How to register a runner:**
```bash
# On a machine that can reach both Forgejo and run Docker containers
forgejo-runner register \
  --instance http://platform-vm.local/git \
  --token <RUNNER_REGISTRATION_TOKEN>

# Start the runner
forgejo-runner daemon
```

**Get runner registration token:**
1. Forgejo UI → Site Administration → Actions → Runners
2. Click "Create new runner"
3. Copy registration token

### 3. Repository Actions Not Enabled

Actions might be disabled specifically for the graft-ci repository.

**How to check:**
1. Go to http://platform-vm.local/git/daniel/graft-ci/settings
2. Check "Actions" section
3. Ensure "Enable Repository Actions" is checked

### 4. Workflow File Syntax Issues

While the syntax looks correct, Forgejo might be stricter than GitHub Actions.

**Validation:**
- Workflow name is present ✅
- Trigger events are defined ✅
- Jobs and steps are defined ✅
- `runs-on: ubuntu-latest` is specified ✅

**Potential issues:**
- `actions/checkout@v4` - might need to be a different version for Forgejo
- Variables syntax `${{ vars.FORGEJO_URL }}` - might not be supported

### 5. Workflow Path Incorrect

Forgejo/Gitea expects workflows in specific paths.

**Correct paths:**
- `.gitea/workflows/*.yml` (current location ✅)
- OR `.github/workflows/*.yml` (also supported)

**Current status:** Workflow is in correct location

### 6. Forgejo Version Too Old

Forgejo Actions was added in Forgejo 1.19. Earlier versions don't support it.

**How to check:**
```bash
ssh platform-vm
forgejo --version
```

**Required:** Forgejo >= 1.19.0

### 7. Push Event Not Being Detected

The workflow has a push trigger, but Forgejo might not be detecting pushes properly.

**How to verify:**
1. Check webhook logs in Forgejo
2. Verify push events are being recorded
3. Check Forgejo system logs for errors

**Logs location:**
```bash
ssh platform-vm
sudo journalctl -u forgejo -n 100
# or
sudo tail -f /var/log/forgejo/forgejo.log
```

## Debugging Steps

### Step 1: Verify Forgejo Version
```bash
ssh daniel@platform-vm
forgejo --version
```

Expected: >= 1.19.0 (Actions support)

### Step 2: Check Global Actions Configuration
```bash
ssh daniel@platform-vm
sudo cat /etc/forgejo/app.ini | grep -A 10 "\[actions\]"
```

Expected:
```ini
[actions]
ENABLED = true
```

If not present or `ENABLED = false`, add/modify and restart Forgejo:
```bash
sudo systemctl restart forgejo
```

### Step 3: Check for Runners
```bash
# Via Forgejo UI
http://platform-vm.local/git/admin/actions/runners

# Or via API
curl -H "Authorization: token $FORGEJO_TOKEN" \
  http://platform-vm.local/git/api/v1/admin/runners
```

Expected: At least one runner with status "online"

If no runners: Need to register and start a runner (see above)

### Step 4: Enable Repository Actions
```bash
# Via Forgejo UI
http://platform-vm.local/git/daniel/graft-ci/settings

# Or via API
curl -X PATCH \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"has_actions": true}' \
  http://platform-vm.local/git/api/v1/repos/daniel/graft-ci
```

### Step 5: Test with Minimal Workflow

Create a minimal test workflow to isolate issues:

`.gitea/workflows/test.yml`:
```yaml
name: Test Actions
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Echo test
        run: echo "Actions working!"
```

Push and check if this simple workflow triggers.

### Step 6: Check Logs

```bash
ssh daniel@platform-vm
sudo journalctl -u forgejo -f
```

Watch for errors when pushing to repository.

### Step 7: Verify Workflow Syntax with act

Use `act` to test the workflow locally:
```bash
# Install act
brew install act  # or platform-specific method

# Test workflow locally
cd /path/to/graft-ci
act push -l  # List jobs
act push     # Run workflow
```

## Common Solutions

### Solution 1: Actions Not Enabled
```bash
ssh daniel@platform-vm
sudo nano /etc/forgejo/app.ini
# Add:
# [actions]
# ENABLED = true
sudo systemctl restart forgejo
```

### Solution 2: No Runners Available
```bash
# Install forgejo-runner
# https://forgejo.org/docs/latest/admin/actions/#forgejo-runner

# Register runner
forgejo-runner register \
  --instance http://platform-vm.local/git \
  --token <TOKEN_FROM_UI>

# Run as service (example with systemd)
sudo nano /etc/systemd/system/forgejo-runner.service
# Add runner service configuration
sudo systemctl enable --now forgejo-runner
```

### Solution 3: Simplify Workflow

Remove complex features that might not be supported:
```yaml
# Remove:
env:
  FORGEJO_URL: ${{ vars.FORGEJO_URL || 'http://platform-vm.local/git' }}

# Use simple:
env:
  FORGEJO_URL: 'http://platform-vm.local/git'
```

## Next Steps

1. SSH into platform-vm to check Forgejo configuration
2. Verify Actions are enabled globally
3. Check if any runners are registered and online
4. Test with minimal workflow
5. Review logs for errors
6. Report findings and proceed based on results

## References

- [Forgejo Actions Documentation](https://forgejo.org/docs/latest/admin/actions/)
- [Gitea Actions Documentation](https://docs.gitea.com/usage/actions/overview)
- [act - Test workflows locally](https://github.com/nektos/act)
