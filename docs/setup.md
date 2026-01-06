---
title: "Setup Guide"
status: working
---

# graft-ci Setup Guide

Step-by-step guide for setting up graft-ci in your Forgejo organization.

## Prerequisites

- Forgejo instance with organization
- Personal access token with repo and org:read scopes
- SSH access to organization repositories
- Ubuntu/Debian runner for Forgejo Actions

## Installation Steps

### 1. Create graft-ci Repository

Create a new repository in your organization:

```bash
# On Forgejo web interface
Organization → New Repository
  Name: graft-ci
  Private: Yes (recommended)
```

Or via CLI:

```bash
gh repo create your-org/graft-ci --private
```

### 2. Clone and Configure

```bash
git clone ssh://forgejo@platform-vm:2222/your-org/graft-ci.git
cd graft-ci

# Copy files from this repository
# (assuming you have access to the template)
```

### 3. Configure Secrets

Add required secrets to the graft-ci repository:

**Via Forgejo Web Interface:**
```
Repository Settings → Secrets → Actions
  Add Secret:
    Name: FORGEJO_TOKEN
    Value: <your-personal-access-token>
```

**Via CLI (if available):**
```bash
forgejo-cli secret add FORGEJO_TOKEN <value>
```

#### Generating a Personal Access Token

1. User Settings → Applications → Generate New Token
2. Token name: "graft-ci-automation"
3. Scopes:
   - `repo` (full repository access)
   - `read:org` (read organization data)
4. Save the token securely

### 4. Configure SSH Access

The PR creator needs SSH access to push branches.

**Option A: Deploy Key (Recommended for single org)**

For each repository that graft-ci will update:

1. Generate SSH key pair:
   ```bash
   ssh-keygen -t ed25519 -C "graft-ci-bot@homelab.local" -f graft-ci-key
   ```

2. Add public key as deploy key with write access:
   ```
   Repository Settings → Deploy Keys → Add Key
     Title: graft-ci-bot
     Key: <content of graft-ci-key.pub>
     Write access: ✓
   ```

3. Add private key to graft-ci secrets:
   ```
   Repository Settings → Secrets → Actions
     Name: SSH_PRIVATE_KEY
     Value: <content of graft-ci-key>
   ```

**Option B: SSH Agent (Recommended for multiple repos)**

Use a bot account with organization access:

1. Create bot user: `graft-ci-bot`
2. Add bot to organization with write access
3. Generate SSH key for bot account
4. Add public key to bot's SSH keys
5. Add private key to graft-ci secrets

### 5. Configure Repository Variables

Add configuration variables:

```
Repository Settings → Variables → Actions
  Add Variable:
    Name: FORGEJO_URL
    Value: https://your-forgejo-instance.com

  Add Variable:
    Name: GRAFT_ORG
    Value: your-organization-name
```

### 6. Set Up Organization Webhook (Optional)

For event-driven updates instead of just scheduled:

```
Organization Settings → Webhooks → Add Webhook
  URL: <forgejo-actions-webhook-endpoint>
  Content Type: application/json
  Events: Push events
  Active: ✓
```

Note: Organization webhooks require manual setup by Forgejo administrators.

### 7. Configure SSH Known Hosts

For Forgejo Actions to connect via SSH, add your Forgejo host to known hosts.

Update the workflow file:

```yaml
- name: Configure SSH
  run: |
    mkdir -p ~/.ssh
    ssh-keyscan -p 2222 platform-vm >> ~/.ssh/known_hosts
```

### 8. Test the Setup

Run a manual workflow dispatch:

```
Repository → Actions → Dependency Update Automation → Run workflow
  Branch: main
  upstream_repo: (leave empty for test)
  dry_run: true
```

Expected output:
- Dependency graph built successfully
- No errors in logs
- Artifacts uploaded with graph.json

### 9. Enable Scheduled Runs

The workflow includes hourly scheduled runs by default:

```yaml
schedule:
  - cron: '0 * * * *'  # Every hour
```

Adjust the cron schedule as needed:
- Every 4 hours: `0 */4 * * *`
- Twice daily: `0 0,12 * * *`
- Daily: `0 0 * * *`

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| FORGEJO_TOKEN | Yes | - | Personal access token |
| FORGEJO_URL | No | https://forgejo.example | Forgejo instance URL |
| GRAFT_ORG | No | daniel | Organization name |
| DRY_RUN | No | false | Enable dry run mode |
| CACHE_FILE | No | .graph-cache.json | Graph cache file path |

### Secrets

| Secret | Required | Purpose |
|--------|----------|---------|
| FORGEJO_TOKEN | Yes | API authentication |
| SSH_PRIVATE_KEY | Yes | Git push authentication |
| WEBHOOK_SECRET | No | Webhook signature verification |

### Repository Structure

Required directories:
- `.forgejo/workflows/` - Forgejo Actions workflows
- `src/` - Shell scripts
- `docs/` - Documentation
- `notes/` - Working notes

## Verification

### Verify Graph Building

```bash
export FORGEJO_TOKEN="your-token"
export FORGEJO_URL="https://your-instance"
export GRAFT_ORG="your-org"

./src/graph-builder.sh > graph.json
cat graph.json | jq .
```

Expected: JSON map of upstream → consumers

### Verify Update Detection

```bash
./src/check-updates.sh graft-knowledge graph.json
```

Expected: JSON array of updates (may be empty)

### Verify SSH Access

```bash
ssh -T git@platform-vm -p 2222
```

Expected: Authentication success message

## Troubleshooting

### Error: "FORGEJO_TOKEN environment variable not set"

**Cause**: Token not configured in secrets

**Fix**: Add FORGEJO_TOKEN to repository secrets (Step 3)

### Error: "git ls-remote failed: Permission denied"

**Cause**: SSH keys not configured

**Fix**: Set up SSH access (Step 4)

### Error: "Could not fetch graft.yaml"

**Cause**: Repository doesn't have graft.yaml file

**Expected**: This is normal for repos without dependencies

### Error: "No repositories found in organization"

**Cause**: Token lacks org:read scope or wrong org name

**Fix**: Verify token scopes and GRAFT_ORG variable

### Workflow doesn't run on schedule

**Cause**: Forgejo Actions may require manual trigger for first run

**Fix**: Run workflow manually once, then schedule will activate

### PRs not created

**Causes**:
1. Dry run mode enabled
2. SSH access not configured
3. No updates available

**Fix**: Check logs in Actions tab for specific error

## Security Best Practices

1. **Use Bot Account**: Create dedicated bot user, don't use personal account
2. **Minimal Scopes**: Token should have only required permissions
3. **Rotate Tokens**: Change tokens periodically
4. **Branch Protection**: Require PR review even for automated PRs
5. **Audit Logs**: Monitor automated PR creation activity
6. **Secret Management**: Never commit secrets to repository

## Next Steps

After setup:

1. Review initial dependency graph
2. Test with dry run mode
3. Monitor first automated PR
4. Adjust schedule based on update frequency
5. Document organization-specific configuration

## Sources

- [Forgejo Actions Documentation](https://forgejo.org/docs/latest/user/actions/)
- [Forgejo Webhooks Documentation](https://forgejo.org/docs/latest/user/webhooks/)
- [Dependency Update Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md)
