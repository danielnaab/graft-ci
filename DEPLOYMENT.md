# Deployment Checklist

Complete deployment checklist for graft-ci automation.

## Current Status

**Implementation**: ✓ Complete
**Local Testing**: ✓ Passed
**Workflow Configuration**: ✓ Ready
**Production Deployment**: ⏳ Pending

## Pre-Deployment

### Code Validation ✓

- [x] All scripts execute without errors
- [x] Graph builder tested with real repositories
- [x] Update detector tested with real dependencies
- [x] PR creator tested in dry run mode
- [x] Workflow YAML syntax validated
- [x] User vs organization auto-detection working

### Documentation ✓

- [x] Setup guide complete
- [x] Testing plan documented
- [x] Workflow setup guide created
- [x] Quick start guide available
- [x] Troubleshooting documented
- [x] Decision records created

### Configuration Files ✓

- [x] graft.yaml with dependencies
- [x] knowledge-base.yaml configured
- [x] .forgejo/workflows/dependency-update.yml created
- [x] .gitignore configured
- [x] .shellcheckrc for linting

## Deployment Steps

### Step 1: Configure Secrets

**Location**: graft-ci Repository → Settings → Secrets → Actions

#### FORGEJO_TOKEN (Required)

- [ ] Token generated with scopes: `repo`, `read:user`, `read:org`
- [ ] Secret added to repository
- [ ] Token tested with API call

**Current token**: `766f3e650b14bca1063b0ddf3a16740634121905`
- ✓ Has read scopes
- ? Unknown if has write scope for PRs
- **Action**: Test in workflow or generate new token with confirmed write access

#### SSH_PRIVATE_KEY (Optional but Recommended)

- [ ] SSH key pair generated
- [ ] Public key added to Forgejo (user SSH keys or deploy keys)
- [ ] Private key added to secret
- [ ] SSH access tested

**If skipped**: Workflow will attempt to use runner's default SSH or HTTPS with token

### Step 2: Configure Variables (Optional)

**Location**: graft-ci Repository → Settings → Variables → Actions

#### FORGEJO_URL

- [ ] Set if different from default: `http://platform-vm:9001`
- [x] Default is correct for this installation

#### GRAFT_ORG

- [ ] Set if different from default: `daniel`
- [x] Default is correct (user account)

### Step 3: Test Workflow (Dry Run)

- [ ] Navigate to Actions → Dependency Update Automation
- [ ] Run workflow with:
  - Branch: `main`
  - upstream_repo: (empty)
  - dry_run: ✓ (checked)
- [ ] Workflow completes successfully
- [ ] All steps show green ✓
- [ ] Artifacts uploaded
- [ ] Review graph.json and updates.json

**Expected duration**: ~30 seconds

### Step 4: Test Workflow (Real Run - Single Upstream)

- [ ] Run workflow with:
  - upstream_repo: `graft-knowledge`
  - dry_run: ☐ (unchecked)
- [ ] Workflow completes successfully
- [ ] Check if PRs created (may be none if up to date)
- [ ] If PR created, verify content:
  - [ ] Title format correct
  - [ ] Body includes upstream commit info
  - [ ] graft.yaml updated correctly
  - [ ] Branch naming correct

### Step 5: Verify Idempotency

- [ ] Run workflow again with same settings
- [ ] Logs show "PR already exists"
- [ ] No duplicate PRs created

### Step 6: Test Full Scan

- [ ] Run workflow with:
  - upstream_repo: (empty - checks all)
  - dry_run: ☐ (unchecked)
- [ ] Workflow scans all upstreams
- [ ] All detected updates processed
- [ ] No errors in logs

### Step 7: Schedule Configuration

Current schedule: Every hour (`0 * * * *`)

- [ ] Schedule is appropriate for organization
- [ ] OR schedule adjusted in workflow file
- [ ] Changes committed and pushed

**Recommended schedules**:
- High activity: Every hour (default)
- Medium activity: Every 4 hours (`0 */4 * * *`)
- Low activity: Daily (`0 0 * * *`)

### Step 8: Team Notification

- [ ] Team notified about automated PRs
- [ ] Review process explained
- [ ] Documentation shared:
  - [ ] QUICKSTART.md
  - [ ] docs/workflow-setup.md
- [ ] Contact person designated for issues

### Step 9: Monitoring Setup

- [ ] Workflow runs monitored in Actions tab
- [ ] Artifacts periodically reviewed
- [ ] Failed runs investigated promptly
- [ ] Optional: Set up notifications for failures

### Step 10: Documentation Updates

- [ ] Organization-specific settings documented
- [ ] Any deviations from defaults noted
- [ ] Custom configurations recorded
- [ ] Troubleshooting additions based on experience

## Post-Deployment

### Week 1: Close Monitoring

- [ ] Review all automated PRs
- [ ] Verify accuracy of dependency updates
- [ ] Check for any false positives
- [ ] Monitor workflow execution time
- [ ] Collect team feedback

### Week 2-4: Optimization

- [ ] Adjust schedule if needed
- [ ] Refine based on update frequency
- [ ] Document any issues encountered
- [ ] Update troubleshooting guide

### Month 1: Review

- [ ] Assess automation value
- [ ] Measure time saved
- [ ] Identify any improvements needed
- [ ] Plan future enhancements

## Rollback Plan

If automation causes issues:

### Immediate (Temporary Disable)

1. Repository → Settings → Actions
2. Disable Actions for repository
3. Investigate issue
4. Re-enable when resolved

### Permanent (Remove Automation)

```bash
git mv .forgejo/workflows/dependency-update.yml \
      .forgejo/workflows/dependency-update.yml.disabled
git commit -m "Disable dependency update automation"
git push
```

## Troubleshooting

### Common Issues

| Issue | Check | Fix |
|-------|-------|-----|
| Workflow doesn't run | Actions enabled? | Enable in Settings |
| "Token not set" error | FORGEJO_TOKEN secret? | Add secret |
| Permission denied on clone | SSH_PRIVATE_KEY? | Add SSH key or use HTTPS |
| No PRs created | Dependencies up to date? | Expected - no action needed |
| Duplicate PRs | Idempotency failing? | Check existing PR detection logic |
| API rate limits | Too frequent checks? | Adjust schedule |

### Getting Help

1. Check workflow logs in Actions tab
2. Download and review artifacts
3. Review [docs/workflow-setup.md](docs/workflow-setup.md)
4. Check [docs/testing-plan.md](docs/testing-plan.md)
5. Review testing results in notes/

## Success Criteria

Deployment is successful when:

- ✓ Workflow runs on schedule without errors
- ✓ Updates detected accurately
- ✓ PRs created with correct content
- ✓ No duplicate PRs generated
- ✓ Team can review and merge PRs easily
- ✓ Time saved on manual dependency checks

## Current Blockers

### Token Write Scope Unknown

**Issue**: Current token `766f3e...` has read scopes, but write scope for PR creation is unconfirmed.

**Risk**: Workflow may fail when attempting to create PRs.

**Mitigation**:
1. Test workflow in Step 4 to confirm
2. If fails, generate new token with explicit write scopes
3. Update documentation with confirmed working token

**Status**: ⏳ Pending workflow test

## Next Actions

1. **Immediate**: Configure FORGEJO_TOKEN secret
2. **Immediate**: Run dry run test (Step 3)
3. **Short-term**: Test real PR creation (Step 4)
4. **Short-term**: Verify idempotency (Step 5)
5. **Medium-term**: Monitor first week of automation
6. **Long-term**: Review and optimize based on usage

## Sign-Off

- [ ] Code reviewed and approved
- [ ] Secrets configured
- [ ] Workflow tested successfully
- [ ] Team notified
- [ ] Documentation complete
- [ ] Monitoring in place

**Deployed by**: _________________
**Date**: _________________
**Notes**: _________________

## References

- [Quick Start](QUICKSTART.md)
- [Workflow Setup](docs/workflow-setup.md)
- [Testing Results](notes/2026-01-06-testing-success.md)
