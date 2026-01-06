# Manual Deployment Steps

Quick manual deployment guide since API automation is limited in this Forgejo version.

## Step 1: Configure Secret (2 minutes)

### Using Forgejo Web UI

1. **Open Forgejo** in your browser

2. **Navigate to repository settings**:
   ```
   http://platform-vm:9001/daniel/graft-ci/settings/actions/secrets
   ```

   Or manually:
   - Go to graft-ci repository
   - Click "Settings" (gear icon)
   - Click "Actions" in left sidebar
   - Click "Secrets"

3. **Add new secret**:
   - Click "Add Secret" button
   - Name: `FORGEJO_TOKEN`
   - Value: `766f3e650b14bca1063b0ddf3a16740634121905`
   - Click "Add Secret"

**✓ Secret configured!**

## Step 2: Run Workflow (Dry Run) (3 minutes)

### Trigger via Forgejo Web UI

1. **Navigate to Actions**:
   ```
   http://platform-vm:9001/daniel/graft-ci/actions
   ```

   Or manually:
   - Go to graft-ci repository
   - Click "Actions" tab

2. **Select workflow**:
   - Click on "Dependency Update Automation" in the workflows list

3. **Run workflow**:
   - Click "Run workflow" button (top right)

4. **Configure run**:
   - Branch: `main`
   - upstream_repo: (leave empty)
   - dry_run: ✓ **CHECKED**

5. **Execute**:
   - Click "Run workflow" button

6. **Monitor**:
   - Workflow run appears in list
   - Click on run to see details
   - Watch steps execute (should take ~30 seconds)

**Expected result**:
- All steps show green ✓
- "Dry run summary" step shows detected updates
- Artifacts section has "dependency-update-results"

## Step 3: Review Results (2 minutes)

### Download Artifacts

1. **In the workflow run details**:
   - Scroll to "Artifacts" section (bottom)
   - Click "dependency-update-results" to download

2. **Extract and review**:
   ```bash
   unzip dependency-update-results.zip
   cat graph.json | jq .
   cat updates.json | jq .
   ```

**What to check**:
- `graph.json`: Should show graft-knowledge and meta-knowledge-base as upstreams
- `updates.json`: List of detected updates (may be empty if all up to date)

## Step 4: Run Real Workflow (2 minutes)

**Only after dry run succeeds!**

1. **Run workflow again** (same as Step 2)

2. **Configure run**:
   - Branch: `main`
   - upstream_repo: (leave empty or specify one)
   - dry_run: ☐ **UNCHECKED**

3. **Execute and monitor**

**Expected result**:
- If updates available: PRs created in consumer repositories
- Check graft, graft-ci repos for new PRs
- If no updates: Workflow succeeds but no PRs (this is normal)

## Step 5: Verify PR (if created) (2 minutes)

If a PR was created:

1. **Navigate to consumer repository** (e.g., graft)

2. **Check Pull Requests tab**

3. **Review PR**:
   - Title: `chore(deps): update <dep> to <sha>`
   - Body includes upstream commit info
   - Files changed shows graft.yaml with updated SHA
   - Branch name: `deps/update-<dep>-<sha>`

4. **Verify idempotency**:
   - Run workflow again
   - Should detect existing PR
   - No duplicate created

## Alternative: Use Helper Script

Run the deployment helper script:

```bash
cd /home/coder/graft-ci
export FORGEJO_TOKEN="766f3e650b14bca1063b0ddf3a16740634121905"
./deploy.sh
```

This script will:
- Validate API access
- Check repository configuration
- Guide you through manual steps
- Optionally run local validation

## Troubleshooting

### "FORGEJO_TOKEN not set" in workflow

**Cause**: Secret not configured

**Fix**: Complete Step 1 above

### Workflow doesn't appear in Actions tab

**Cause**: Workflow file not detected

**Fix**:
- Verify file exists at `.forgejo/workflows/dependency-update.yml`
- Push to main branch if needed
- Refresh page

### "Permission denied" errors

**Cause**: Token lacks write permissions or SSH not configured

**Fix**:
- For now, this is expected (we haven't tested write operations yet)
- If dry run works but real run fails, may need SSH_PRIVATE_KEY secret

### No updates detected

**Cause**: All dependencies are up to date

**This is normal!** The workflow is working correctly.

## Quick Reference URLs

**Repository**: http://platform-vm:9001/daniel/graft-ci

**Actions**: http://platform-vm:9001/daniel/graft-ci/actions

**Secrets**: http://platform-vm:9001/daniel/graft-ci/settings/actions/secrets

**Settings**: http://platform-vm:9001/daniel/graft-ci/settings

## Next Steps After Successful Deployment

1. ✓ Workflow runs successfully
2. Monitor for real dependency updates
3. Review and merge automated PRs
4. Adjust schedule if needed (currently hourly)
5. Share feedback with team

## Support

See full documentation:
- [QUICKSTART.md](QUICKSTART.md)
- [docs/workflow-setup.md](docs/workflow-setup.md)
- [DEPLOYMENT.md](DEPLOYMENT.md)
