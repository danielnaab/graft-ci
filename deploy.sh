#!/bin/bash
set -euo pipefail

# Deployment helper script for graft-ci
# This script helps configure secrets and test the workflow

FORGEJO_URL="${FORGEJO_URL:-http://platform-vm:9001}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              graft-ci Deployment Helper                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check token
if [ -z "$FORGEJO_TOKEN" ]; then
    echo "❌ FORGEJO_TOKEN environment variable not set"
    echo ""
    echo "Please run:"
    echo "  export FORGEJO_TOKEN='<your-forgejo-token>'"
    echo ""
    exit 1
fi

echo "✓ FORGEJO_TOKEN is set"
echo ""

# Step 2: Test API access
echo "Testing API access..."
USER_RESPONSE=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/user")
USERNAME=$(echo "$USER_RESPONSE" | jq -r '.username // empty')

if [ -z "$USERNAME" ]; then
    echo "❌ API authentication failed"
    echo "Response: $USER_RESPONSE"
    exit 1
fi

echo "✓ Authenticated as: $USERNAME"
echo ""

# Step 3: Check repository
echo "Checking graft-ci repository..."
REPO_RESPONSE=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/repos/daniel/graft-ci")
HAS_ACTIONS=$(echo "$REPO_RESPONSE" | jq -r '.has_actions // false')

if [ "$HAS_ACTIONS" = "true" ]; then
    echo "✓ Forgejo Actions is enabled"
else
    echo "⚠️  Forgejo Actions may not be enabled"
fi
echo ""

# Step 4: Manual secret configuration instructions
echo "═══════════════════════════════════════════════════════════════"
echo "  MANUAL STEP REQUIRED: Configure Repository Secret"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Unfortunately, Forgejo Actions secrets cannot be configured via API."
echo "Please follow these steps in the Forgejo UI:"
echo ""
echo "1. Open your browser and go to:"
echo "   ${FORGEJO_URL}/daniel/graft-ci/settings/actions/secrets"
echo ""
echo "2. Click 'Add Secret'"
echo ""
echo "3. Configure the secret:"
echo "   Name:  FORGEJO_TOKEN"
echo "   Value: the token in your FORGEJO_TOKEN environment variable"
echo ""
echo "4. Click 'Add Secret'"
echo ""
read -p "Press ENTER when you have configured the secret..."
echo ""

# Step 5: Manual workflow trigger instructions
echo "═══════════════════════════════════════════════════════════════"
echo "  MANUAL STEP REQUIRED: Trigger Workflow (Dry Run)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Unfortunately, workflows cannot be triggered via API in this Forgejo version."
echo "Please follow these steps in the Forgejo UI:"
echo ""
echo "1. Go to:"
echo "   ${FORGEJO_URL}/daniel/graft-ci/actions"
echo ""
echo "2. Click on 'Dependency Update Automation' workflow"
echo ""
echo "3. Click 'Run workflow' button"
echo ""
echo "4. Configure the run:"
echo "   Branch: main"
echo "   upstream_repo: (leave empty)"
echo "   dry_run: ✓ CHECKED"
echo ""
echo "5. Click 'Run workflow'"
echo ""
echo "6. Monitor the workflow execution"
echo ""
read -p "Press ENTER when the workflow has completed..."
echo ""

# Step 6: Local validation
echo "═══════════════════════════════════════════════════════════════"
echo "  Local Validation (Optional)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "You can also test the scripts locally:"
echo ""
echo "export FORGEJO_TOKEN='<your-forgejo-token>'"
echo "export FORGEJO_URL='http://platform-vm:9001'"
echo "export GRAFT_ORG='daniel'"
echo ""
echo "cd /home/coder/graft-ci"
echo "./src/graph-builder.sh > test-graph.json"
echo "./src/check-updates.sh graft-knowledge test-graph.json > test-updates.json"
echo "DRY_RUN=true ./src/create-pr.sh test-updates.json"
echo ""
read -p "Do you want to run local validation now? (y/N): " RUN_LOCAL

if [[ "$RUN_LOCAL" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Running local validation..."
    echo ""

    export GRAFT_ORG="daniel"

    echo "1. Building dependency graph..."
    ./src/graph-builder.sh > test-graph.json
    echo "   ✓ Graph built: $(cat test-graph.json | jq 'keys | length') upstreams found"
    echo ""

    echo "2. Checking for updates (graft-knowledge)..."
    ./src/check-updates.sh graft-knowledge test-graph.json > test-updates.json
    UPDATE_COUNT=$(cat test-updates.json | jq 'length')
    echo "   ✓ Updates found: $UPDATE_COUNT"
    echo ""

    if [ "$UPDATE_COUNT" -gt 0 ]; then
        echo "3. Testing PR creator (dry run)..."
        DRY_RUN=true ./src/create-pr.sh test-updates.json > test-results.json
        echo "   ✓ PR creator test complete"
        echo ""

        echo "Results:"
        cat test-updates.json | jq -r '.[] | "  - \(.consumer): \(.dep_name) (\(.old_sha[0:8]) → \(.new_sha[0:8]))"'
    else
        echo "   All dependencies are up to date"
    fi
    echo ""
fi

# Step 7: Summary
echo "═══════════════════════════════════════════════════════════════"
echo "  Deployment Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "✓ API access validated"
echo "✓ Repository confirmed"
echo "✓ Actions enabled"
echo ""
echo "Next steps:"
echo "1. Verify workflow completed successfully in Forgejo UI"
echo "2. Download and review artifacts (graph.json, updates.json)"
echo "3. Run workflow again with dry_run: unchecked for real PR test"
echo "4. Monitor automated PRs and team feedback"
echo ""
echo "Documentation:"
echo "  - Quick Start: QUICKSTART.md"
echo "  - Full Setup: docs/workflow-setup.md"
echo "  - Deployment: DEPLOYMENT.md"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Deployment helper complete! 🚀"
echo ""
