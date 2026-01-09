#!/bin/bash
# Script to manually trigger dependency-update.yml workflow via API

FORGEJO_TOKEN="766f3e650b14bca1063b0ddf3a16740634121905"
FORGEJO_URL="http://platform-vm.local/git"
REPO="graft-ci"
OWNER="daniel"
WORKFLOW="dependency-update.yml"

echo "Triggering workflow: $WORKFLOW"
echo "Repository: $OWNER/$REPO"
echo ""

# Trigger with dry_run=true for safe testing
curl -X POST \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ref": "main",
    "inputs": {
      "dry_run": "true",
      "upstream_repo": ""
    }
  }' \
  "$FORGEJO_URL/api/v1/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW/dispatches"

echo ""
echo ""
echo "Workflow triggered! Check at:"
echo "$FORGEJO_URL/$OWNER/$REPO/actions"
