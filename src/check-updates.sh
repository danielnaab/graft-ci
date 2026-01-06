#!/bin/bash
set -euo pipefail

# Update Detector
# Identifies consumers with outdated dependency refs
# Uses git ls-remote for efficient ref checking

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.example}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
ORG="${GRAFT_ORG:-daniel}"

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
    echo "[check-updates] $*" >&2
}

# Fetch graft.yaml from a repository
fetch_graft_yaml() {
    local org="$1"
    local repo="$2"

    local url="${FORGEJO_URL}/api/v1/repos/${org}/${repo}/raw/graft.yaml"
    local response
    response=$(curl -s -w "\n%{http_code}" -H "Authorization: token $FORGEJO_TOKEN" "$url")
    local http_code=$(echo "$response" | tail -n 1)
    local content=$(echo "$response" | head -n -1)

    if [ "$http_code" = "200" ]; then
        echo "$content"
        return 0
    else
        return 1
    fi
}

# Get current HEAD of a git repository
get_remote_head() {
    local git_url="$1"
    local ref="${2:-HEAD}"

    log "Checking remote ref: $git_url $ref"

    # Remove #ref suffix if present
    git_url="${git_url%#*}"

    # Use git ls-remote to get the ref
    local output
    local error
    local sha

    output=$(git ls-remote "$git_url" "$ref" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        error=$(echo "$output" | head -n 1)
        log "Error: git ls-remote failed for $git_url (ref: $ref): $error"
        return 1
    fi

    sha=$(echo "$output" | awk '{print $1}' | head -n 1)

    if [ -z "$sha" ]; then
        log "Warning: Could not resolve ref '$ref' for $git_url (no matching ref found)"
        return 1
    fi

    echo "$sha"
}

# Extract ref from dependency URL (part after #)
extract_ref_from_url() {
    local url="$1"

    if [[ "$url" == *"#"* ]]; then
        echo "${url#*#}"
    else
        echo "HEAD"
    fi
}

# Extract git URL without ref
extract_git_url() {
    local url="$1"
    echo "${url%#*}"
}

# Get commit information from Forgejo API
get_commit_info() {
    local org="$1"
    local repo="$2"
    local sha="$3"

    local url="${FORGEJO_URL}/api/v1/repos/${org}/${repo}/git/commits/${sha}"
    local response
    response=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" "$url")

    local message=$(echo "$response" | jq -r '.message // ""' | head -n 1)
    local author=$(echo "$response" | jq -r '.author.name // "Unknown"')
    local date=$(echo "$response" | jq -r '.author.date // ""')

    jq -n \
        --arg message "$message" \
        --arg author "$author" \
        --arg date "$date" \
        '{message: $message, author: $author, date: $date}'
}

# Check for updates in a consumer repository
check_consumer_updates() {
    local org="$1"
    local consumer_repo="$2"
    local upstream_repo="$3"
    local dep_name="$4"

    log "Checking updates for $consumer_repo (dep: $dep_name → $upstream_repo)"

    # Fetch consumer's graft.yaml
    local graft_yaml
    if ! graft_yaml=$(fetch_graft_yaml "$org" "$consumer_repo"); then
        log "Could not fetch graft.yaml from $consumer_repo"
        return 1
    fi

    # Extract the dependency URL
    local dep_url
    dep_url=$(echo "$graft_yaml" | yq -r ".deps[\"$dep_name\"] // \"\"")

    if [ -z "$dep_url" ]; then
        log "Dependency $dep_name not found in $consumer_repo"
        return 1
    fi

    # Parse the URL and ref
    local git_url=$(extract_git_url "$dep_url")
    local pinned_ref=$(extract_ref_from_url "$dep_url")

    log "  Current: $pinned_ref"

    # Get current remote HEAD
    local upstream_head
    if ! upstream_head=$(get_remote_head "$git_url" "$pinned_ref"); then
        log "Could not get remote HEAD for $git_url"
        return 1
    fi

    log "  Remote HEAD: ${upstream_head:0:8}"

    # Check if pinned_ref is already a full SHA matching upstream_head
    if [ "$pinned_ref" = "$upstream_head" ]; then
        log "  Status: Up to date"
        return 0
    fi

    # If pinned_ref is a branch name, resolve it to SHA
    local pinned_sha
    if ! pinned_sha=$(get_remote_head "$git_url" "$pinned_ref"); then
        log "Could not resolve pinned ref $pinned_ref"
        return 1
    fi

    log "  Pinned SHA: ${pinned_sha:0:8}"

    # Compare SHAs
    if [ "$pinned_sha" = "$upstream_head" ]; then
        log "  Status: Up to date"
        return 0
    fi

    log "  Status: Update available (${pinned_sha:0:8} → ${upstream_head:0:8})"

    # Get commit info for the new HEAD
    local commit_info
    commit_info=$(get_commit_info "$org" "$upstream_repo" "$upstream_head" || echo '{}')

    # Output update information
    jq -n \
        --arg consumer "$consumer_repo" \
        --arg dep_name "$dep_name" \
        --arg upstream "$upstream_repo" \
        --arg old_ref "$pinned_ref" \
        --arg old_sha "$pinned_sha" \
        --arg new_sha "$upstream_head" \
        --arg git_url "$git_url" \
        --argjson commit_info "$commit_info" \
        '{
            consumer: $consumer,
            dep_name: $dep_name,
            upstream: $upstream,
            old_ref: $old_ref,
            old_sha: $old_sha,
            new_sha: $new_sha,
            git_url: $git_url,
            commit_info: $commit_info
        }'
}

# Main execution
main() {
    local org="${ORG}"
    local upstream_repo="${1:-}"
    local graph_file="${2:-.graph-cache.json}"

    if [ -z "$upstream_repo" ]; then
        echo "Usage: $0 <upstream_repo> [graph_file]" >&2
        echo "  upstream_repo: Repository that was updated" >&2
        echo "  graph_file: Path to dependency graph JSON (default: .graph-cache.json)" >&2
        exit 1
    fi

    log "Starting update check"
    log "Upstream repository: $upstream_repo"
    log "Organization: $org"

    # Load dependency graph
    if [ ! -f "$graph_file" ]; then
        log "Error: Graph file not found: $graph_file"
        log "Run graph-builder.sh first to generate the dependency graph"
        exit 1
    fi

    local graph
    graph=$(cat "$graph_file")

    # Find consumers of the upstream repository
    local consumers
    consumers=$(echo "$graph" | jq -r --arg upstream "$upstream_repo" '.[$upstream] // []')

    if [ "$consumers" = "[]" ]; then
        log "No consumers found for $upstream_repo"
        echo "[]"
        exit 0
    fi

    log "Found consumers: $(echo "$consumers" | jq -r '.[].repo' | tr '\n' ' ')"

    # Check each consumer for updates
    local updates="[]"
    local consumer_count=$(echo "$consumers" | jq -r 'length')

    for i in $(seq 0 $((consumer_count - 1))); do
        local consumer_repo=$(echo "$consumers" | jq -r ".[$i].repo")
        local dep_name=$(echo "$consumers" | jq -r ".[$i].dep_name")

        local update
        if update=$(check_consumer_updates "$org" "$consumer_repo" "$upstream_repo" "$dep_name"); then
            if [ -n "$update" ] && [ "$update" != "null" ]; then
                updates=$(echo "$updates" | jq --argjson update "$update" '. += [$update]')
            fi
        fi
    done

    # Output results
    echo "$updates" | jq .

    local update_count=$(echo "$updates" | jq 'length')
    log "Check complete: $update_count update(s) available"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
