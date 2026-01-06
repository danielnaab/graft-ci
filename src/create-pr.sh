#!/bin/bash
set -euo pipefail

# PR Creator
# Creates or updates pull requests in consumer repositories
# Input: JSON with update information from check-updates.sh

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.example}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
ORG="${GRAFT_ORG:-daniel}"
DRY_RUN="${DRY_RUN:-false}"

# Check for required tools
for cmd in curl jq yq git; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed" >&2
        exit 1
    fi
done

# Check for required environment variables
if [ -z "$FORGEJO_TOKEN" ]; then
    echo "Error: FORGEJO_TOKEN environment variable not set" >&2
    exit 1
fi

log() {
    echo "[create-pr] $*" >&2
}

# Clone a repository to a temporary directory
clone_repo() {
    local org="$1"
    local repo="$2"
    local temp_dir="$3"

    local clone_url="ssh://forgejo@platform-vm:2222/${org}/${repo}.git"

    log "Cloning $org/$repo to $temp_dir"

    git clone --depth 1 "$clone_url" "$temp_dir" 2>&1 | sed 's/^/  /' >&2
}

# Check if a PR already exists for this update
check_existing_pr() {
    local org="$1"
    local repo="$2"
    local branch="$3"

    log "Checking for existing PR with head branch: $branch"

    local url="${FORGEJO_URL}/api/v1/repos/${org}/${repo}/pulls?state=open"
    local prs
    prs=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" "$url")

    local existing_pr
    existing_pr=$(echo "$prs" | jq --arg branch "$branch" '.[] | select(.head.ref == $branch) | .number' | head -n 1)

    echo "$existing_pr"
}

# Update graft.yaml with new ref
update_graft_yaml() {
    local graft_file="$1"
    local dep_name="$2"
    local git_url="$3"
    local new_sha="$4"

    log "Updating $graft_file: $dep_name → $new_sha"

    # Create new dependency URL with SHA
    local new_dep_url="${git_url}#${new_sha}"

    # Update using yq
    yq -i ".deps[\"$dep_name\"] = \"$new_dep_url\"" "$graft_file"
}

# Create PR via Forgejo API
create_pull_request() {
    local org="$1"
    local repo="$2"
    local title="$3"
    local body="$4"
    local head_branch="$5"
    local base_branch="${6:-main}"

    log "Creating pull request in $org/$repo"

    local url="${FORGEJO_URL}/api/v1/repos/${org}/${repo}/pulls"

    local pr_data
    pr_data=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --arg head "$head_branch" \
        --arg base "$base_branch" \
        '{title: $title, body: $body, head: $head, base: $base}')

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would create PR with data:"
        echo "$pr_data" | jq . >&2
        echo "dry-run"
        return 0
    fi

    local response
    response=$(curl -s -X POST \
        -H "Authorization: token $FORGEJO_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$pr_data" \
        "$url")

    local pr_number=$(echo "$response" | jq -r '.number // "error"')

    if [ "$pr_number" = "error" ]; then
        log "Error creating PR: $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi

    echo "$pr_number"
}

# Process a single update
process_update() {
    local update="$1"

    local consumer=$(echo "$update" | jq -r '.consumer')
    local dep_name=$(echo "$update" | jq -r '.dep_name')
    local upstream=$(echo "$update" | jq -r '.upstream')
    local old_sha=$(echo "$update" | jq -r '.old_sha')
    local new_sha=$(echo "$update" | jq -r '.new_sha')
    local git_url=$(echo "$update" | jq -r '.git_url')
    local commit_message=$(echo "$update" | jq -r '.commit_info.message // "Update"')
    local commit_author=$(echo "$update" | jq -r '.commit_info.author // "Unknown"')
    local commit_date=$(echo "$update" | jq -r '.commit_info.date // ""')

    log "Processing update: $consumer / $dep_name"

    # Generate branch name
    local branch_name="deps/update-${dep_name}-${new_sha:0:8}"

    # Check for existing PR
    local existing_pr
    existing_pr=$(check_existing_pr "$ORG" "$consumer" "$branch_name")

    if [ -n "$existing_pr" ]; then
        log "PR already exists: #$existing_pr"
        echo "$existing_pr"
        return 0
    fi

    # Create temporary directory for the repository
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Clone the consumer repository
    if ! clone_repo "$ORG" "$consumer" "$temp_dir"; then
        log "Error cloning repository"
        return 1
    fi

    cd "$temp_dir"

    # Configure git
    git config user.name "graft-ci-bot"
    git config user.email "graft-ci-bot@homelab.local"

    # Create new branch
    log "Creating branch: $branch_name"
    git checkout -b "$branch_name"

    # Update graft.yaml
    if [ ! -f "graft.yaml" ]; then
        log "Error: graft.yaml not found in repository"
        return 1
    fi

    update_graft_yaml "graft.yaml" "$dep_name" "$git_url" "$new_sha"

    # Check if there are changes
    if ! git diff --quiet graft.yaml; then
        log "Changes detected, creating commit"

        git add graft.yaml

        local commit_msg="chore(deps): update ${dep_name} to ${new_sha:0:8}"
        git commit -m "$commit_msg"

        # Push branch
        if [ "$DRY_RUN" = "true" ]; then
            log "DRY RUN: Would push branch $branch_name"
        else
            log "Pushing branch: $branch_name"
            git push origin "$branch_name" 2>&1 | sed 's/^/  /' >&2
        fi
    else
        log "No changes detected"
        return 0
    fi

    # Generate PR title and body
    local pr_title="chore(deps): update ${dep_name} to ${new_sha:0:8}"

    local pr_body
    pr_body=$(cat <<EOF
## Summary

Updates \`${dep_name}\` dependency to latest upstream commit.

**Upstream commit:** \`${new_sha:0:8}\` - ${commit_message}
**Author:** ${commit_author}
$([ -n "$commit_date" ] && echo "**Date:** ${commit_date}")

## Changes

- ${dep_name}: ${old_sha:0:8} → ${new_sha:0:8}

---
Automated by graft-ci
EOF
    )

    # Create pull request
    local pr_number
    pr_number=$(create_pull_request "$ORG" "$consumer" "$pr_title" "$pr_body" "$branch_name")

    log "Pull request created: #$pr_number"

    echo "$pr_number"
}

# Main execution
main() {
    local updates_file="${1:-}"

    if [ -z "$updates_file" ] || [ "$updates_file" = "-" ]; then
        log "Reading updates from stdin"
        updates_file="/dev/stdin"
    fi

    log "Starting PR creation"
    log "Organization: $ORG"
    log "Dry run: $DRY_RUN"

    # Read updates
    local updates
    updates=$(cat "$updates_file")

    local update_count=$(echo "$updates" | jq 'length')

    if [ "$update_count" -eq 0 ]; then
        log "No updates to process"
        exit 0
    fi

    log "Processing $update_count update(s)"

    # Process each update
    local results="[]"
    for i in $(seq 0 $((update_count - 1))); do
        local update=$(echo "$updates" | jq ".[$i]")

        local consumer=$(echo "$update" | jq -r '.consumer')
        local dep_name=$(echo "$update" | jq -r '.dep_name')

        log "[$((i + 1))/$update_count] Processing $consumer / $dep_name"

        local pr_number
        if pr_number=$(process_update "$update"); then
            results=$(echo "$results" | jq \
                --arg consumer "$consumer" \
                --arg dep_name "$dep_name" \
                --arg pr "$pr_number" \
                '. += [{consumer: $consumer, dep_name: $dep_name, pr: $pr}]')

            log "  ✓ Success: PR #$pr_number"
        else
            log "  ✗ Failed to create PR"
        fi
    done

    # Output results
    echo "$results" | jq .

    log "PR creation complete"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
