---
date: 2026-01-09
status: research
---

# Coder Authentication Alternatives for CI/CD

## Problem

Coder tokens have a maximum lifetime of 168 hours (7 days), requiring weekly rotation. This is impractical for automated CI/CD workflows.

## Current Approach (Problematic)

```yaml
- name: Setup Coder CLI
  run: |
    coder login http://192.168.1.51:7080 --token "${{ secrets.CODER_TOKEN }}"
```

**Issues:**
- Token expires after 7 days max
- Requires manual rotation
- Workflow breaks when token expires

## Alternative Solutions

### Option 1: Environment Variable Authentication

The Coder CLI respects the `CODER_SESSION_TOKEN` environment variable, bypassing the need for `coder login`.

**Implementation:**
```yaml
- name: Create workspace
  env:
    CODER_SESSION_TOKEN: ${{ secrets.CODER_TOKEN }}
    CODER_URL: http://192.168.1.51:7080
  run: |
    # No need for coder login
    coder create workspace-name --template repo-generic ...
```

**Pros:**
- Still uses tokens (same security model)
- Cleaner in workflow (no login step)

**Cons:**
- Still requires token rotation every 7 days

### Option 2: Coder Config Directory

Coder stores session information in `~/.config/coder/session`. We could potentially mount a persistent config directory.

**Implementation:**
```yaml
- name: Restore Coder session
  uses: actions/cache@v3
  with:
    path: ~/.config/coder
    key: coder-session-${{ github.repository }}

- name: Setup Coder
  run: |
    if ! coder list &>/dev/null; then
      coder login http://192.168.1.51:7080 --token "${{ secrets.CODER_TOKEN }}"
    fi
```

**Pros:**
- Only login when session expired
- Reduces login frequency

**Cons:**
- Still requires eventual rotation
- Cache might be cleared
- Complexity

### Option 3: Coder API Direct (No CLI)

Instead of using `coder` CLI, use the Coder REST API directly with curl.

**Implementation:**
```yaml
- name: Create workspace via API
  env:
    CODER_TOKEN: ${{ secrets.CODER_TOKEN }}
  run: |
    curl -X POST \
      -H "Coder-Session-Token: $CODER_TOKEN" \
      -H "Content-Type: application/json" \
      http://192.168.1.51:7080/api/v2/workspaces \
      -d '{...}'
```

**Pros:**
- No CLI installation needed
- Direct control

**Cons:**
- Still requires token
- More complex API calls
- Need to handle pagination, errors, etc.

### Option 4: Service Account with Longer Token

Check if Coder has a concept of "service accounts" or "bot users" that might have different token lifetime limits.

**Research needed:**
1. Can we create a dedicated `forgejo-actions` Coder user?
2. Does that user have different token lifetime limits?
3. Are there API tokens vs session tokens with different lifetimes?

**Commands to try:**
```bash
# Check Coder version and features
coder version --output json

# List token create options
coder tokens create --help

# Check if there are different token types
coder tokens list --help
```

### Option 5: Automated Token Rotation

Create a separate workflow that rotates the token automatically.

**Implementation:**
```yaml
# .forgejo/workflows/rotate-coder-token.yml
name: Rotate Coder Token

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  rotate:
    runs-on: ubuntu-latest
    steps:
      - name: Revoke old token
        env:
          CODER_SESSION_TOKEN: ${{ secrets.CODER_TOKEN }}
        run: |
          coder tokens rm forgejo-actions

      - name: Create new token
        run: |
          NEW_TOKEN=$(coder tokens create --name forgejo-actions --lifetime 168h)

          # Use Forgejo API to update the secret
          curl -X PUT \
            -H "Authorization: token ${{ secrets.FORGEJO_TOKEN }}" \
            -H "Content-Type: application/json" \
            "http://platform-vm.local/git/api/v1/repos/daniel/graft-ci/actions/secrets/CODER_TOKEN" \
            -d "{\"data\": \"$NEW_TOKEN\"}"
```

**Pros:**
- Fully automated
- Works within existing constraints

**Cons:**
- Complex
- Might fail and break everything
- Circular dependency (needs working token to rotate)

### Option 6: Coder Deploy Key / SSH Key

Some systems support SSH key authentication for CI/CD that doesn't expire.

**Research needed:**
- Does Coder support SSH key authentication for the CLI?
- Can we generate a deploy key for the workspace?

### Option 7: Run Coder Locally on CI Runner

If the Forgejo Actions runner is on the same machine as Coder (or has network access), we might be able to use local authentication.

**Implementation:**
```yaml
- name: Use local Coder
  run: |
    # If runner is on same host as Coder, might be able to use local socket
    export CODER_URL=http://localhost:7080
    coder list
```

**Pros:**
- No token needed if using local authentication

**Cons:**
- Requires runner to be on same host or network
- Depends on Coder's local auth model

### Option 8: Hybrid Approach - Manual Token, Automated Notification

Accept that tokens need rotation, but add monitoring:

**Implementation:**
```yaml
- name: Check token expiry
  run: |
    # Try to use Coder
    if ! coder list &>/dev/null; then
      echo "::error::CODER_TOKEN has expired! Please rotate it."
      # Send notification (email, webhook, etc.)
      exit 1
    fi
```

**Pros:**
- Simple
- Clear failure mode

**Cons:**
- Still manual rotation
- Workflow fails when token expires

## Recommended Approach

### Short Term: Environment Variable + Monitoring

```yaml
- name: Setup Coder
  env:
    CODER_SESSION_TOKEN: ${{ secrets.CODER_TOKEN }}
    CODER_URL: http://192.168.1.51:7080
  run: |
    # Verify token is valid
    if ! coder list &>/dev/null; then
      echo "::error::CODER_TOKEN expired or invalid. Please rotate."
      echo "Generate new token: coder tokens create --name forgejo-actions --lifetime 168h"
      exit 1
    fi

    # Continue with workspace creation
    coder create ...
```

**Benefits:**
- Cleaner than login command
- Clear error message when expired
- Minimal changes to workflow

### Long Term: Research Service Accounts

**Action items:**
1. Check Coder documentation for service account support
2. Check if Coder API has different token types with longer lifetimes
3. Open issue/discussion with Coder project about CI/CD use case
4. Consider if Coder version upgrade offers better token management

## Investigation Commands

Run these to gather more info:

```bash
# Check Coder version
coder version

# Check token options
coder tokens create --help

# List existing tokens
coder tokens list

# Check API documentation
curl http://192.168.1.51:7080/api/v2/docs

# Check if there's a config file with session info
cat ~/.config/coder/session

# See if there are different authentication methods
coder login --help
```

## Questions for User

1. **What version of Coder are you running?**
   ```bash
   coder version
   ```

2. **Are there any service account or bot user features in your Coder instance?**

3. **Is the Forgejo Actions runner running on the same machine as Coder or with network access?**

4. **Would you be open to a weekly manual token rotation, or is that too frequent?**

5. **Are you using Coder OSS or Enterprise?** (Enterprise might have different features)

## Workaround for Now

Until we find a better solution:

**Set a calendar reminder:**
- Every 6 days (to be safe before 7-day expiry)
- Run: `coder tokens create --name forgejo-actions --lifetime 168h`
- Update the secret in Forgejo

**Or use a shorter automation schedule:**
```yaml
# Run dependency updates less frequently to reduce token usage
schedule:
  - cron: '0 0 * * 1'  # Weekly on Monday only
```

This reduces how often the token is used, making the 7-day lifetime more manageable.
