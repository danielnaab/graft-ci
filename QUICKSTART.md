# graft-ci Quick Start

Fast track to get graft-ci running in 10 minutes.

## Step 1: Configure Secrets (2 minutes)

### Required: FORGEJO_TOKEN

1. Go to Forgejo → User Settings → Applications
2. Generate New Token with scopes: `repo`, `read:user`, `read:org`
3. Copy the token
4. Go to graft-ci repository → Settings → Secrets → Actions
5. Add Secret:
   - Name: `FORGEJO_TOKEN`
   - Value: `<paste-token>`

**Current working token**: stored only as this repo's `FORGEJO_TOKEN` Actions secret

### Optional: SSH_PRIVATE_KEY

If using SSH for git operations:

1. Generate key: `ssh-keygen -t ed25519 -C "graft-ci-bot@homelab.local" -f graft-ci-key`
2. Add public key (`graft-ci-key.pub`) to Forgejo:
   - User Settings → SSH Keys → Add Key (for all repos)
   - OR Repository → Settings → Deploy Keys (per repo with write access)
3. Add private key to secret:
   - Name: `SSH_PRIVATE_KEY`
   - Value: `<contents of graft-ci-key>`

## Step 2: Test with Dry Run (3 minutes)

1. graft-ci Repository → Actions
2. Select "Dependency Update Automation"
3. Click "Run workflow"
4. Settings:
   - Branch: `main`
   - upstream_repo: (leave empty)
   - dry_run: ✓ **CHECKED**
5. Click "Run workflow"

**Wait for workflow to complete** (~30 seconds)

**Success indicators**:
- All steps green ✓
- "Dry run summary" shows detected updates
- Artifacts uploaded

**If it fails**:
- Check logs for errors
- Verify FORGEJO_TOKEN is set
- See [Troubleshooting](docs/workflow-setup.md#troubleshooting)

## Step 3: Create Real PR (2 minutes)

Once dry run succeeds:

1. Run workflow again with:
   - dry_run: ☐ **UNCHECKED**
   - upstream_repo: `graft-knowledge` (or leave empty)

**Expected**:
- PRs created in consumer repositories
- Check graft, graft-ci repos for new PRs

**If no PRs created**:
- All dependencies may be up to date (expected)
- Check artifacts → updates.json to see detected updates

## Step 4: Verify Idempotency (1 minute)

Run workflow again with same settings.

**Expected**:
- Logs show "PR already exists"
- No duplicate PRs created

## Step 5: Enable Automation (2 minutes)

### Option A: Keep Hourly Schedule (Default)

No changes needed. Workflow runs every hour automatically.

### Option B: Adjust Schedule

Edit `.forgejo/workflows/dependency-update.yml`:

```yaml
schedule:
  - cron: '0 0 * * *'  # Daily at midnight
```

Commit and push.

## Quick Reference

### View Workflow Runs
graft-ci → Actions → Dependency Update Automation

### Download Artifacts
Workflow run → Artifacts → dependency-update-results

### Disable Workflow
Repository → Settings → Actions → Disable

### Re-enable Workflow
Repository → Settings → Actions → Enable

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "FORGEJO_TOKEN not set" | Add secret in Settings → Secrets |
| "Permission denied" on clone | Add SSH_PRIVATE_KEY secret |
| "Could not fetch graft.yaml" | Check token has `repo` scope |
| No PRs created | Dependencies are up to date OR dry_run is enabled |
| Workflow doesn't run | Check cron schedule, verify Actions enabled |

## Next Steps

After successful setup:

- Monitor first automated PRs
- Review PRs before merging
- Adjust schedule if needed
- See [Workflow Setup](docs/workflow-setup.md) for details

## Getting Help

- Full documentation: [docs/workflow-setup.md](docs/workflow-setup.md)
- Testing guide: [docs/testing-plan.md](docs/testing-plan.md)
- Setup guide: [docs/setup.md](docs/setup.md)
