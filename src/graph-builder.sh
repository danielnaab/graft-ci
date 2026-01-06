#!/bin/bash
set -euo pipefail

# Dependency Graph Builder
# Scans organization repositories and builds inverted dependency index
# Output: JSON map of upstream → [consumers]

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.example}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"
ORG="${GRAFT_ORG:-daniel}"
CACHE_FILE="${CACHE_FILE:-.graph-cache.json}"

# Check for required tools
for cmd in curl jq yq; do
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
    echo "[graph-builder] $*" >&2
}

# Fetch all repositories in organization
fetch_repos() {
    local org="$1"
    log "Fetching repositories for organization: $org"

    curl -s -H "Authorization: token $FORGEJO_TOKEN" \
        "${FORGEJO_URL}/api/v1/orgs/${org}/repos?limit=100" \
        | jq -r '.[].name'
}

# Fetch graft.yaml from a repository
fetch_graft_yaml() {
    local org="$1"
    local repo="$2"

    log "Fetching graft.yaml from $org/$repo"

    # Try to fetch graft.yaml from the default branch
    local url="${FORGEJO_URL}/api/v1/repos/${org}/${repo}/raw/graft.yaml"
    local response
    response=$(curl -s -w "\n%{http_code}" -H "Authorization: token $FORGEJO_TOKEN" "$url")
    local http_code=$(echo "$response" | tail -n 1)
    local content=$(echo "$response" | head -n -1)

    if [ "$http_code" = "200" ]; then
        echo "$content"
        return 0
    else
        log "No graft.yaml found in $org/$repo (HTTP $http_code)"
        return 1
    fi
}

# Parse dependencies from graft.yaml content
parse_dependencies() {
    local yaml_content="$1"

    # Extract deps section and parse git URLs
    echo "$yaml_content" | yq -r '.deps // {} | to_entries[] | "\(.key)|\(.value)"'
}

# Extract repository name from git URL
extract_repo_name() {
    local git_url="$1"

    # Handle formats:
    # ssh://forgejo@platform-vm:2222/daniel/graft-knowledge.git#main
    # git@platform-vm:daniel/graft-knowledge.git#main

    # Remove #ref suffix
    git_url="${git_url%#*}"

    # Remove .git suffix
    git_url="${git_url%.git}"

    # Extract repo name (last path component)
    basename "$git_url"
}

# Build the dependency graph
build_graph() {
    local org="$1"

    log "Building dependency graph for organization: $org"

    # Initialize empty graph
    local graph="{}"

    # Get all repositories
    local repos
    repos=$(fetch_repos "$org")

    if [ -z "$repos" ]; then
        log "No repositories found in organization: $org"
        echo "{}"
        return 0
    fi

    # Process each repository
    while IFS= read -r repo; do
        [ -z "$repo" ] && continue

        log "Processing repository: $repo"

        # Fetch graft.yaml
        local graft_yaml
        if ! graft_yaml=$(fetch_graft_yaml "$org" "$repo"); then
            continue
        fi

        # Parse dependencies
        local deps
        deps=$(parse_dependencies "$graft_yaml")

        if [ -z "$deps" ]; then
            log "No dependencies found in $repo"
            continue
        fi

        # Add consumer to each upstream's list
        while IFS='|' read -r dep_name dep_url; do
            [ -z "$dep_name" ] && continue

            local upstream_repo
            upstream_repo=$(extract_repo_name "$dep_url")

            log "  $repo depends on $upstream_repo (via $dep_name)"

            # Add to graph using jq
            graph=$(echo "$graph" | jq \
                --arg upstream "$upstream_repo" \
                --arg consumer "$repo" \
                --arg dep_name "$dep_name" \
                '.[$upstream] += [{"repo": $consumer, "dep_name": $dep_name}] | .[$upstream] |= unique_by(.repo)')
        done <<< "$deps"

    done <<< "$repos"

    echo "$graph"
}

# Main execution
main() {
    local org="${1:-$ORG}"

    log "Starting dependency graph builder"
    log "Organization: $org"
    log "Forgejo URL: $FORGEJO_URL"

    # Build the graph
    local graph
    graph=$(build_graph "$org")

    # Save to cache file
    if [ -n "$CACHE_FILE" ]; then
        echo "$graph" > "$CACHE_FILE"
        log "Graph saved to cache: $CACHE_FILE"
    fi

    # Output the graph
    echo "$graph" | jq .

    log "Graph building complete"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
