#!/bin/bash
set -euo pipefail

# workspace-upgrade-exec.sh - Execute dependency upgrade inside Coder workspace
#
# This script runs inside a Coder workspace to:
# 1. Install graft if needed
# 2. Run graft upgrade
# 3. Create/update PR via Forgejo API
#
# Arguments:
#   $1 - consumer repo name
#   $2 - dependency name
#   $3 - new SHA
#   $4 - old SHA
#   $5 - git URL
#   $6 - commit info JSON
#
# Environment variables (from workspace):
#   FORGEJO_TOKEN - Forgejo API token
#   FORGEJO_URL - Forgejo instance URL
#   GRAFT_ORG - Organization name
#
# Outputs JSON result on stdout

# Configuration from environment or defaults
FORGEJO_URL="${FORGEJO_URL:-http://platform-vm.local/git}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
GRAFT_ORG="${GRAFT_ORG:-daniel}"
CODER_URL="${CODER_URL:-http://192.168.1.51:7080}"

# Arguments
CONSUMER="${1:-}"
DEP_NAME="${2:-}"
NEW_SHA="${3:-}"
OLD_SHA="${4:-}"
GIT_URL="${5:-}"
COMMIT_INFO="${6:-{}}"

# Logging
log() {
    echo "[workspace-exec] $*" >&2
}

error() {
    echo "[workspace-exec] ERROR: $*" >&2
}

# Validate arguments
if [ -z "$CONSUMER" ] || [ -z "$DEP_NAME" ] || [ -z "$NEW_SHA" ]; then
    error "Missing required arguments"
    error "Usage: $0 <consumer> <dep_name> <new_sha> <old_sha> <git_url> <commit_info_json>"
    exit 1
fi

# Install graft if needed
install_graft() {
    if command -v graft &>/dev/null; then
        log "graft already installed: $(graft --version 2>&1 | head -1 || echo 'version unknown')"
        return 0
    fi

    log "Installing graft..."

    # Try to install from consumer's dependencies first
    if [ -d "$HOME/$CONSUMER/.graft/deps/graft" ]; then
        log "Installing graft from consumer's dependencies"
        cd "$HOME/$CONSUMER/.graft/deps/graft"
        pip install -e . >/dev/null 2>&1
        cd - >/dev/null
    else
        log "Installing graft from git"
        pip install "git+ssh://forgejo@platform-vm:2222/daniel/graft.git@main" >/dev/null 2>&1
    fi

    if command -v graft &>/dev/null; then
        log "graft installed successfully"
        return 0
    else
        error "Failed to install graft"
        return 1
    fi
}

# Run graft upgrade
run_upgrade() {
    log "Running graft upgrade for $DEP_NAME to $NEW_SHA"

    cd "$HOME/$CONSUMER" || {
        error "Consumer directory not found: $HOME/$CONSUMER"
        return 1
    }

    # Ensure we're on main branch and up to date
    git fetch origin main >/dev/null 2>&1 || true
    git checkout main >/dev/null 2>&1 || true
    git pull origin main >/dev/null 2>&1 || true

    # Run graft upgrade
    local upgrade_output
    if upgrade_output=$(graft upgrade "$DEP_NAME" --to "$NEW_SHA" 2>&1); then
        log "Graft upgrade succeeded"
        echo "$upgrade_output" >&2
        return 0
    else
        error "Graft upgrade failed:"
        echo "$upgrade_output" >&2
        return 1
    fi
}

# Check if PR already exists
find_existing_pr() {
    local prs
    prs=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$CONSUMER/pulls?state=open" 2>/dev/null || echo "[]")

    echo "$prs" | jq -r ".[] | select(.head.ref | startswith(\"deps/update-$DEP_NAME-\")) | .number" | head -1
}

# Create or update PR
create_or_update_pr() {
    local branch_name="deps/update-${DEP_NAME}-${NEW_SHA:0:8}"

    cd "$HOME/$CONSUMER" || return 1

    # Create branch
    git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"

    # Stage changes
    git add graft.lock

    # Check if there are changes to commit
    if ! git diff --staged --quiet; then
        # Commit changes
        git commit -m "chore(deps): update $DEP_NAME to ${NEW_SHA:0:8}"

        # Push to origin (force push to update existing branch)
        git push -u origin "$branch_name" --force
    else
        log "No changes to commit (already up to date)"
    fi

    # Extract commit info
    local commit_message commit_author
    commit_message=$(echo "$COMMIT_INFO" | jq -r '.message // "Update dependency"')
    commit_author=$(echo "$COMMIT_INFO" | jq -r '.author.name // "Unknown"')

    # Get current workspace name (from hostname or CODER_WORKSPACE env var)
    local workspace_name="${CODER_WORKSPACE:-${HOSTNAME:-unknown}}"
    local workspace_url="$CODER_URL/workspaces/$workspace_name"

    # Prepare PR body
    local pr_body
    pr_body=$(cat <<EOF
## Summary
Updates \`$DEP_NAME\` dependency to latest upstream commit.

**Upstream commit:** \`${NEW_SHA:0:8}\` - $commit_message
**Author:** $commit_author

## Workspace

Upgrade performed in workspace: [$workspace_name]($workspace_url)

**Status:**
✓ Graft upgrade completed
✓ Lock file updated

The workspace is available for debugging or additional changes. Connect with:
\`\`\`
coder ssh $workspace_name
\`\`\`

---
Automated by graft-ci
EOF
)

    # Check for existing PR
    local existing_pr
    existing_pr=$(find_existing_pr)

    if [ -n "$existing_pr" ]; then
        log "Updating existing PR #$existing_pr"

        # Update PR title
        curl -s -X PATCH \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg title "chore(deps): update $DEP_NAME to ${NEW_SHA:0:8}" --arg body "$pr_body" '{title: $title, body: $body}')" \
            "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$CONSUMER/pulls/$existing_pr" >/dev/null

        # Add comment about update
        local comment="Updated to include upstream commit \`${NEW_SHA:0:8}\`: $commit_message"
        curl -s -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg body "$comment" '{body: $body}')" \
            "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$CONSUMER/issues/$existing_pr/comments" >/dev/null

        echo "$existing_pr"
    else
        log "Creating new PR"

        # Create PR
        local pr_response
        pr_response=$(curl -s -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg title "chore(deps): update $DEP_NAME to ${NEW_SHA:0:8}" \
                --arg body "$pr_body" \
                --arg head "$branch_name" \
                --arg base "main" \
                '{title: $title, body: $body, head: $head, base: $base}')" \
            "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$CONSUMER/pulls")

        local pr_number
        pr_number=$(echo "$pr_response" | jq -r '.number // empty')

        if [ -z "$pr_number" ]; then
            error "Failed to create PR"
            error "Response: $pr_response"
            return 1
        fi

        log "Created PR #$pr_number"
        echo "$pr_number"
    fi
}

# Main execution
main() {
    log "Starting upgrade execution"
    log "Consumer: $CONSUMER, Dependency: $DEP_NAME"
    log "Old SHA: ${OLD_SHA:0:8}, New SHA: ${NEW_SHA:0:8}"

    # Install graft
    if ! install_graft; then
        jq -n \
            --arg consumer "$CONSUMER" \
            --arg dep_name "$DEP_NAME" \
            --arg error "Failed to install graft" \
            '{consumer: $consumer, dep_name: $dep_name, success: false, error: $error}'
        exit 1
    fi

    # Run upgrade
    if ! run_upgrade; then
        jq -n \
            --arg consumer "$CONSUMER" \
            --arg dep_name "$DEP_NAME" \
            --arg workspace "${CODER_WORKSPACE:-${HOSTNAME:-unknown}}" \
            --arg workspace_url "$CODER_URL/workspaces/${CODER_WORKSPACE:-${HOSTNAME:-unknown}}" \
            --arg error "Graft upgrade failed - see workspace for details" \
            '{consumer: $consumer, dep_name: $dep_name, workspace: $workspace, workspace_url: $workspace_url, success: false, error: $error}'
        exit 1
    fi

    # Create or update PR
    local pr_number
    if pr_number=$(create_or_update_pr); then
        local workspace_name="${CODER_WORKSPACE:-${HOSTNAME:-unknown}}"
        local workspace_url="$CODER_URL/workspaces/$workspace_name"
        local pr_url="$FORGEJO_URL/$GRAFT_ORG/$CONSUMER/pulls/$pr_number"

        log "Success! PR #$pr_number created/updated"

        # Output success result as JSON
        jq -n \
            --arg consumer "$CONSUMER" \
            --arg dep_name "$DEP_NAME" \
            --arg pr_number "$pr_number" \
            --arg pr_url "$pr_url" \
            --arg workspace "$workspace_name" \
            --arg workspace_url "$workspace_url" \
            --arg new_sha "$NEW_SHA" \
            --arg old_sha "$OLD_SHA" \
            '{consumer: $consumer, dep_name: $dep_name, pr_number: $pr_number, pr_url: $pr_url, workspace: $workspace, workspace_url: $workspace_url, new_sha: $new_sha, old_sha: $old_sha, success: true}'
        exit 0
    else
        jq -n \
            --arg consumer "$CONSUMER" \
            --arg dep_name "$DEP_NAME" \
            --arg error "Failed to create/update PR" \
            '{consumer: $consumer, dep_name: $dep_name, success: false, error: $error}'
        exit 1
    fi
}

# Run main
main "$@"
