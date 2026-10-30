---
title: "Forgejo Actions Workflow Setup"
status: working
---

# Forgejo Actions Workflow Setup

Complete guide for configuring and deploying the graft-ci automation workflow.

## Prerequisites

- graft-ci repository pushed to Forgejo
- Forgejo Actions enabled on platform-vm
- API token with required scopes
- SSH access configured

## Required Secrets

Configure these secrets in the graft-ci repository settings:

### 1. FORGEJO_TOKEN

**Purpose**: API authentication for repository operations

**Required Scopes**:
- `repo` - Repository access (read graft.yaml, create PRs)
- `read:user` - List user repositories
- `read:org` - List organization repositories (if applicable)

**How to Generate**:
1. Forgejo UI → User Settings → Applications
2. Generate New Token
3. Name: "graft-ci-automation"
4. Select scopes: `repo`, `read:user`, `read:org`
5. Generate Token
6. Copy the token value

**How to Add Secret**:
1. graft-ci Repository → Settings → Secrets → Actions
2. Add Secret
3. Name: `FORGEJO_TOKEN`
4. Value: `<paste-token-here>`
5. Save

**Current Token**: stored only as this repo's `FORGEJO_TOKEN` Actions secret
- ✓ Has required read scopes
- ? Unknown if has PR creation write scope
- Test by running workflow

### 2. SSH_PRIVATE_KEY (Optional but Recommended)

**Purpose**: SSH authentication for git clone/push operations

**Why Needed**:
- PR creator clones repositories to update graft.yaml
- Pushes branches with updated dependencies
- Alternative to using HTTPS with token

**How to Generate**:
```bash
# Generate new SSH key for graft-ci bot
ssh-keygen -t ed25519 -C "graft-ci-bot@homelab.local" -f graft-ci-bot-key

# This creates:
# - graft-ci-bot-key (private key - add to secrets)
# - graft-ci-bot-key.pub (public key - add to Forgejo)
```

**Add Public Key to Forgejo**:

**Option A: Deploy Key (Per Repository)**
For each repository that graft-ci will update:
1. Repository → Settings → Deploy Keys
2. Add Deploy Key
3. Title: "graft-ci-bot"
4. Key: `<contents of graft-ci-bot-key.pub>`
5. ✓ Allow write access
6. Add Key

**Option B: User SSH Key (All Repositories)**
Create a bot user account:
1. Create user: `graft-ci-bot`
2. Add to organization with write access
3. User Settings → SSH Keys → Add Key
4. Paste public key
5. Use bot user's SSH key

**Add Private Key to Secret**:
1. graft-ci Repository → Settings → Secrets → Actions
2. Add Secret
3. Name: `SSH_PRIVATE_KEY`
4. Value: `<paste contents of graft-ci-bot-key private key>`
5. Save

**Note**: If SSH_PRIVATE_KEY is not provided, the workflow will attempt to use the runner's default SSH configuration.

## Optional Variables

Configure these in Repository → Settings → Variables → Actions:

### FORGEJO_URL

**Default**: `http://platform-vm:9001`

Override if your Forgejo instance is at a different URL:
1. Add Variable
2. Name: `FORGEJO_URL`
3. Value: `http://your-forgejo-host:port`

### GRAFT_ORG

**Default**: `daniel`

Override to use a different user/organization:
1. Add Variable
2. Name: `GRAFT_ORG`
3. Value: `your-username-or-org`

## Workflow Configuration

The workflow file is at `.forgejo/workflows/dependency-update.yml`

### Triggers

#### 1. Manual Trigger (workflow_dispatch)

Run on demand for testing:
```
Repository → Actions → Dependency Update Automation → Run workflow

Inputs:
  upstream_repo: (optional) Specific upstream to check
  dry_run: (checkbox) Run without creating PRs
```

**Use cases**:
- Initial testing
- Checking specific upstream
- Dry run validation

#### 2. Scheduled Trigger (cron)

Runs automatically on schedule:
```yaml
schedule:
  - cron: '0 * * * *'  # Every hour
```

**Recommended schedules**:
- Hourly: `0 * * * *` (default)
- Every 4 hours: `0 */4 * * *`
- Twice daily: `0 0,12 * * *`
- Daily: `0 0 * * *`

#### 3. Repository Dispatch (webhook)

Triggered by organization webhooks (future enhancement):
```yaml
repository_dispatch:
  types: [org_push]
```

**Not yet configured** - requires organization webhook setup.

## Testing the Workflow

### Step 1: Verify Secrets

Check that secrets are configured:
1. Repository → Settings → Secrets → Actions
2. Verify `FORGEJO_TOKEN` is present
3. Verify `SSH_PRIVATE_KEY` is present (if using SSH)

### Step 2: Manual Dry Run

Test without creating PRs:

1. Repository → Actions
2. Select "Dependency Update Automation"
3. Click "Run workflow"
4. Fill in:
   - Branch: `main`
   - upstream_repo: (leave empty to check all)
   - dry_run: ✓ (checked)
5. Click "Run workflow"

**Expected outcome**:
- Workflow runs successfully
- Builds dependency graph
- Checks for updates
- Shows what PRs would be created
- No actual PRs created

**Check logs**:
- All steps should be green ✓
- "Dry run summary" shows detected updates
- No errors in logs

### Step 3: Manual Run (Specific Upstream)

Test with specific upstream in dry run:

1. Run workflow with:
   - upstream_repo: `graft-knowledge`
   - dry_run: ✓ (checked)

**Expected outcome**:
- Only checks graft-knowledge consumers
- Faster execution
- Shows potential updates for that upstream only

### Step 4: Real PR Creation (When Ready)

Once dry runs succeed:

1. Run workflow with:
   - upstream_repo: (empty or specific upstream)
   - dry_run: ☐ (unchecked)

**Expected outcome**:
- Creates actual pull requests
- PRs appear in consumer repositories
- Workflow completes successfully

**Verify PRs**:
- Check consumer repositories for new PRs
- PR title: `chore(deps): update <dep-name> to <sha>`
- PR body includes upstream commit info
- graft.yaml updated with new SHA

### Step 5: Test Idempotency

Run the workflow again with same upstream:

**Expected outcome**:
- Detects existing PR
- Does not create duplicate
- Logs: "PR already exists: #X"

## Workflow Steps Explained

### 1. Checkout
Clones graft-ci repository to get scripts.

### 2. Install Dependencies
Installs `yq` for YAML parsing.

### 3. Make Scripts Executable
Ensures shell scripts can run.

### 4. Build Dependency Graph
Scans all repositories for graft.yaml files, builds upstream → consumer map.

**Output**: `graph.json`

### 5. Determine Upstream
Decides which upstream to check based on trigger type.

### 6. Check for Updates
Runs update detector against specified upstream(s).

**Output**: `updates.json`

### 7. Configure SSH
Sets up SSH key and known hosts for git operations.

### 8. Create Pull Requests
Generates PRs for detected updates (skipped in dry run).

**Output**: `results.json`

### 9. Upload Artifacts
Saves graph.json, updates.json, results.json for debugging.

**Retention**: 30 days

## Troubleshooting

### Workflow Doesn't Appear

**Cause**: Workflow file not in correct location or invalid YAML

**Fix**:
1. Verify file at `.forgejo/workflows/dependency-update.yml`
2. Check YAML syntax: `yq eval .forgejo/workflows/dependency-update.yml`
3. Push to main branch
4. Refresh Actions page

### "FORGEJO_TOKEN not set"

**Cause**: Secret not configured

**Fix**: Add FORGEJO_TOKEN secret (see above)

### "Permission denied" on git clone

**Cause**: SSH key not configured or incorrect

**Fix**:
1. Verify SSH_PRIVATE_KEY secret is set
2. Verify public key added to Forgejo
3. Check key has write access
4. Test SSH: `ssh -T git@platform-vm -p 2222`

### "Could not fetch graft.yaml"

**Cause**: Token lacks repo read scope

**Fix**: Regenerate token with `repo` scope

### "Failed to create PR"

**Possible causes**:
1. Token lacks write permissions
2. Branch already exists
3. PR already exists

**Debug**:
1. Check workflow logs for specific error
2. Download artifacts to see updates.json
3. Verify token has `repo` write scope

### Workflow Runs but No PRs Created

**Check**:
1. Dry run mode enabled? (should be disabled)
2. Are updates detected? (check updates.json artifact)
3. Are all dependencies up to date? (expected if no updates)

## Monitoring

### View Workflow Runs

1. Repository → Actions
2. Select "Dependency Update Automation"
3. View run history

### Check Artifacts

Download artifacts from workflow runs:
1. Click on a workflow run
2. Scroll to "Artifacts"
3. Download "dependency-update-results"
4. Contains:
   - `graph.json` - Full dependency graph
   - `updates.json` - Detected updates
   - `results.json` - PR creation results

### Scheduled Run Status

Scheduled runs appear automatically in Actions tab.

**Expected frequency**: Every hour (with default cron)

## Adjusting Schedule

Edit `.forgejo/workflows/dependency-update.yml`:

```yaml
schedule:
  - cron: '0 0 * * *'  # Change to daily at midnight
```

Commit and push to update schedule.

## Disabling Automation

### Temporary

Disable the workflow:
1. Repository → Settings → Actions
2. Disable Actions for this repository

### Permanent

Remove or rename the workflow file:
```bash
git mv .forgejo/workflows/dependency-update.yml .forgejo/workflows/dependency-update.yml.disabled
git commit -m "Disable dependency update automation"
git push
```

## Production Deployment Checklist

- [ ] FORGEJO_TOKEN secret configured with required scopes
- [ ] SSH_PRIVATE_KEY secret configured (if using SSH)
- [ ] Variables set (FORGEJO_URL, GRAFT_ORG) if needed
- [ ] Manual dry run successful
- [ ] Manual real run successful (test PR created)
- [ ] Idempotency verified (no duplicates)
- [ ] Schedule adjusted to desired frequency
- [ ] Team notified about automated PRs
- [ ] Documentation updated with org-specific settings

## Security Best Practices

1. **Use bot account**: Create `graft-ci-bot` user for SSH keys
2. **Minimal token scopes**: Only grant required permissions
3. **Rotate secrets**: Change tokens and keys periodically
4. **Branch protection**: Require PR review even for automated PRs
5. **Audit logs**: Monitor Actions runs regularly
6. **Secret access**: Limit who can view/edit repository secrets

## Next Steps

After successful workflow deployment:

1. Monitor first automated PRs
2. Adjust schedule if too frequent/infrequent
3. Document any organization-specific configuration
4. Train team on reviewing automated PRs
5. Set up notifications for workflow failures (optional)

## References

- [Forgejo Actions Documentation](https://forgejo.org/docs/latest/user/actions/)
- [GitHub Actions Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions) (similar to Forgejo)
- [Testing Plan](testing-plan.md)
- [Setup Guide](setup.md)
