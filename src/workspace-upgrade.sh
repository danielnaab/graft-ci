#!/bin/bash
set -euo pipefail

# workspace-upgrade.sh - Orchestrate workspace-based dependency upgrades
#
# This script processes dependency updates by creating Coder workspaces,
# executing graft upgrade within them, and creating/updating PRs.
#
# Usage:
#   ./workspace-upgrade.sh <updates.json>
#
# Input: JSON array of update objects from check-updates.sh
# Output: JSON array of results (PR URLs, workspace URLs, errors)
#
# Environment variables:
#   FORGEJO_URL - Forgejo instance URL (default: http://platform-vm.local/git)
#   FORGEJO_TOKEN - Forgejo API token (required)
#   CODER_URL - Coder instance URL (default: http://192.168.1.51:7080)
#   GRAFT_ORG - Organization/user name (default: daniel)

# Configuration
FORGEJO_URL="${FORGEJO_URL:-http://platform-vm.local/git}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
CODER_URL="${CODER_URL:-http://192.168.1.51:7080}"
GRAFT_ORG="${GRAFT_ORG:-daniel}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging helpers
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Validate environment
validate_environment() {
    if [ -z "$FORGEJO_TOKEN" ]; then
        error "FORGEJO_TOKEN environment variable is required"
        return 1
    fi

    if ! command -v coder &>/dev/null; then
        error "coder CLI not found. Install it first."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        error "jq is required but not found"
        return 1
    fi

    log "Environment validated"
    return 0
}

# Get dependency version from main branch
get_version_from_main() {
    local consumer="$1"
    local dep_name="$2"

    local lock_content
    lock_content=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/raw/graft.lock?ref=main" 2>/dev/null || echo "{}")

    echo "$lock_content" | jq -r ".\"$dep_name\".commit // empty"
}

# Get dependency version from PR branch
get_version_from_pr() {
    local consumer="$1"
    local pr_number="$2"
    local dep_name="$3"

    # Get PR details to find head branch
    local pr_data
    pr_data=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/pulls/$pr_number")

    local head_branch
    head_branch=$(echo "$pr_data" | jq -r '.head.ref')

    if [ -z "$head_branch" ] || [ "$head_branch" = "null" ]; then
        error "Could not determine PR branch for PR #$pr_number"
        return 1
    fi

    # Get graft.lock from PR branch
    local lock_content
    lock_content=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/raw/graft.lock?ref=$head_branch" 2>/dev/null || echo "{}")

    echo "$lock_content" | jq -r ".\"$dep_name\".commit // empty"
}

# Check if an existing PR is stale (main branch has newer version)
check_pr_stale() {
    local consumer="$1"
    local pr_number="$2"
    local dep_name="$3"

    local main_version
    main_version=$(get_version_from_main "$consumer" "$dep_name")

    local pr_version
    pr_version=$(get_version_from_pr "$consumer" "$pr_number" "$dep_name")

    if [ -z "$pr_version" ]; then
        # Can't determine PR version - assume not stale
        return 1
    fi

    if [ -z "$main_version" ]; then
        # Main doesn't have this dependency - PR is not stale
        return 1
    fi

    # If main has same or newer version, PR is stale
    if [ "$main_version" = "$pr_version" ] || [ "${#main_version}" -ge "${#pr_version}" ]; then
        log "PR #$pr_number is stale: main has $main_version, PR has $pr_version"
        return 0
    fi

    return 1
}

# Close a stale PR
close_pr() {
    local consumer="$1"
    local pr_number="$2"
    local reason="$3"

    log "Closing PR #$pr_number in $consumer: $reason"

    # Add comment explaining closure
    curl -s -X POST \
        -H "Authorization: token $FORGEJO_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$reason" '{body: $body}')" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/issues/$pr_number/comments" >/dev/null

    # Close the PR
    curl -s -X PATCH \
        -H "Authorization: token $FORGEJO_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"state": "closed"}' \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/pulls/$pr_number" >/dev/null
}

# Find existing PR for a dependency
find_existing_pr() {
    local consumer="$1"
    local dep_name="$2"

    local prs
    prs=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/pulls?state=open")

    echo "$prs" | jq -r ".[] | select(.head.ref | startswith(\"deps/update-$dep_name-\")) | .number" | head -1
}

# Check if workspace exists
workspace_exists() {
    local workspace_name="$1"
    coder list 2>/dev/null | grep -q "^${workspace_name}\s"
}

# Check if workspace is running
workspace_is_running() {
    local workspace_name="$1"
    local status
    status=$(coder list 2>/dev/null | grep "^${workspace_name}\s" | awk '{print $2}')
    [ "$status" = "Running" ]
}

# Check if workspace has uncommitted changes or additional commits
workspace_has_changes() {
    local workspace_name="$1"
    local consumer="$2"

    log "Checking workspace $workspace_name for modifications..."

    # Check for uncommitted changes and unpushed commits
    local changes
    changes=$(coder ssh "$workspace_name" -- bash -c "
        cd ~/$consumer 2>/dev/null || exit 1
        git status --short
        git log origin/\$(git rev-parse --abbrev-ref HEAD)..HEAD --oneline 2>/dev/null || true
    " 2>/dev/null || echo "error")

    if [ "$changes" = "error" ]; then
        error "Could not check workspace state"
        return 1
    fi

    if [ -n "$changes" ]; then
        log "Workspace has modifications:"
        echo "$changes" | head -5 >&2
        return 0
    fi

    return 1
}

# Create Coder workspace
create_workspace() {
    local workspace_name="$1"
    local consumer="$2"

    log "Creating workspace: $workspace_name"

    local consumer_repo_url="ssh://forgejo@platform-vm:2222/$GRAFT_ORG/$consumer.git"

    coder create "$workspace_name" \
        --template repo-generic \
        --parameter "repo_url=$consumer_repo_url" \
        --parameter "git_name=graft-ci-bot" \
        --parameter "git_email=graft-ci-bot@homelab.local" \
        --parameter "enable_claude=false" \
        --parameter "enable_codex=false" \
        --parameter "forgejo_host=platform-vm" \
        --parameter "forgejo_ssh_port=2222" \
        --stop-after 24h \
        --yes

    log "Workspace $workspace_name created successfully"
}

# Delete workspace
delete_workspace() {
    local workspace_name="$1"

    log "Deleting workspace: $workspace_name"
    coder delete "$workspace_name" --yes 2>/dev/null || true
}

# Process a single dependency update
process_update() {
    local update_json="$1"

    # Parse update details
    local consumer dep_name new_sha old_sha git_url
    consumer=$(echo "$update_json" | jq -r '.consumer')
    dep_name=$(echo "$update_json" | jq -r '.dep_name')
    new_sha=$(echo "$update_json" | jq -r '.new_sha')
    old_sha=$(echo "$update_json" | jq -r '.old_sha')
    git_url=$(echo "$update_json" | jq -r '.git_url')

    log "Processing update: $consumer -> $dep_name ($old_sha -> $new_sha)"

    # Generate workspace name
    local workspace_name="${consumer}-deps-${dep_name}"

    # Check for existing PR
    local existing_pr
    existing_pr=$(find_existing_pr "$consumer" "$dep_name")

    if [ -n "$existing_pr" ]; then
        log "Found existing PR #$existing_pr for $dep_name in $consumer"

        # Check if PR is stale
        if check_pr_stale "$consumer" "$existing_pr" "$dep_name"; then
            close_pr "$consumer" "$existing_pr" "Closing: dependency already updated to newer version in main branch"
            delete_workspace "$workspace_name"

            # Return result
            jq -n \
                --arg consumer "$consumer" \
                --arg dep_name "$dep_name" \
                --arg action "closed_stale" \
                --arg pr "$existing_pr" \
                '{consumer: $consumer, dep_name: $dep_name, action: $action, pr_number: $pr, success: true}'
            return 0
        fi

        # Check workspace state if it exists
        if workspace_exists "$workspace_name"; then
            if workspace_has_changes "$workspace_name" "$consumer"; then
                log "Workspace has local changes - preserving and notifying"

                # Add comment to PR
                local comment="⚠️ **New upstream version available**: \`$new_sha\`\n\nWorkspace has uncommitted changes - not auto-updating. Please review and update manually if needed.\n\n[Workspace: $workspace_name]($CODER_URL/workspaces/$workspace_name)"

                curl -s -X POST \
                    -H "Authorization: token $FORGEJO_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$(jq -n --arg body "$comment" '{body: $body}')" \
                    "$FORGEJO_URL/api/v1/repos/$GRAFT_ORG/$consumer/issues/$existing_pr/comments" >/dev/null

                # Return result
                jq -n \
                    --arg consumer "$consumer" \
                    --arg dep_name "$dep_name" \
                    --arg action "preserved_workspace" \
                    --arg pr "$existing_pr" \
                    --arg workspace "$workspace_name" \
                    '{consumer: $consumer, dep_name: $dep_name, action: $action, pr_number: $pr, workspace: $workspace, success: true}'
                return 0
            fi

            log "Workspace is clean - will update PR"
        fi
    fi

    # Create or start workspace
    if workspace_exists "$workspace_name"; then
        if ! workspace_is_running "$workspace_name"; then
            log "Starting existing workspace: $workspace_name"
            coder start "$workspace_name" --yes
            sleep 10  # Wait for workspace to be ready
        else
            log "Reusing running workspace: $workspace_name"
        fi
    else
        create_workspace "$workspace_name" "$consumer"
        sleep 30  # Wait for workspace initialization
    fi

    # Get commit info for PR body
    local commit_info
    commit_info=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "$git_url/api/v1/repos/$GRAFT_ORG/$dep_name/git/commits/$new_sha" 2>/dev/null || echo "{}")

    # Execute upgrade in workspace
    log "Executing upgrade in workspace..."

    local exec_script="$SCRIPT_DIR/workspace-upgrade-exec.sh"
    if [ ! -f "$exec_script" ]; then
        error "Execution script not found: $exec_script"
        jq -n \
            --arg consumer "$consumer" \
            --arg dep_name "$dep_name" \
            --arg error "Execution script not found" \
            '{consumer: $consumer, dep_name: $dep_name, success: false, error: $error}'
        return 1
    fi

    # Execute via coder ssh
    local result
    result=$(coder ssh "$workspace_name" -- bash -s "$consumer" "$dep_name" "$new_sha" "$old_sha" "$git_url" "$(echo "$commit_info" | jq -c .)" < "$exec_script" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        error "Upgrade failed in workspace: $workspace_name"
        error "Output: $result"

        # Return error result with workspace URL for debugging
        jq -n \
            --arg consumer "$consumer" \
            --arg dep_name "$dep_name" \
            --arg workspace "$workspace_name" \
            --arg workspace_url "$CODER_URL/workspaces/$workspace_name" \
            --arg error "$result" \
            '{consumer: $consumer, dep_name: $dep_name, workspace: $workspace, workspace_url: $workspace_url, success: false, error: $error}'
        return 1
    fi

    # Parse result from execution script
    log "Upgrade succeeded"
    echo "$result" | tail -1  # Last line should be JSON result
}

# Main execution
main() {
    local updates_file="${1:-}"

    if [ -z "$updates_file" ]; then
        error "Usage: $0 <updates.json>"
        exit 1
    fi

    if [ ! -f "$updates_file" ]; then
        error "Updates file not found: $updates_file"
        exit 1
    fi

    validate_environment || exit 1

    log "Processing updates from: $updates_file"

    # Read updates
    local updates
    updates=$(cat "$updates_file")

    local update_count
    update_count=$(echo "$updates" | jq 'length')

    log "Found $update_count updates to process"

    # Process each update sequentially
    local results=()
    for i in $(seq 0 $((update_count - 1))); do
        local update
        update=$(echo "$updates" | jq ".[$i]")

        local result
        result=$(process_update "$update")

        results+=("$result")
    done

    # Output results as JSON array
    printf '%s\n' "${results[@]}" | jq -s .
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
