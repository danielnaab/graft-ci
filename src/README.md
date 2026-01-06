# Source Scripts

Implementation scripts for graft-ci dependency update automation.

## Scripts

### graph-builder.sh

Builds inverted dependency graph from organization repositories.

**Usage:**
```bash
export FORGEJO_TOKEN="your-token"
export FORGEJO_URL="https://forgejo.example"
export GRAFT_ORG="daniel"

./graph-builder.sh
```

**Output:** JSON map of `upstream → [consumers]`

**Cache:** Saves result to `.graph-cache.json`

### check-updates.sh

Checks for outdated dependencies in consumer repositories.

**Usage:**
```bash
export FORGEJO_TOKEN="your-token"
export FORGEJO_URL="https://forgejo.example"
export GRAFT_ORG="daniel"

# Check specific upstream
./check-updates.sh graft-knowledge .graph-cache.json

# Output: JSON array of updates
```

**Requirements:**
- Dependency graph file (from graph-builder.sh)
- git, curl, jq, yq

### create-pr.sh

Creates pull requests for dependency updates.

**Usage:**
```bash
export FORGEJO_TOKEN="your-token"
export FORGEJO_URL="https://forgejo.example"
export GRAFT_ORG="daniel"

# From file
./create-pr.sh updates.json

# From stdin
./check-updates.sh graft-knowledge | ./create-pr.sh -

# Dry run
DRY_RUN=true ./create-pr.sh updates.json
```

**Requirements:**
- git, curl, jq, yq
- SSH access to repositories
- Write permissions in target repositories

## Environment Variables

Required:
- `FORGEJO_TOKEN` - Personal access token with repo scope

Optional:
- `FORGEJO_URL` - Forgejo instance URL (default: https://forgejo.example)
- `GRAFT_ORG` - Organization name (default: daniel)
- `DRY_RUN` - Set to "true" for dry run mode (default: false)
- `CACHE_FILE` - Graph cache file path (default: .graph-cache.json)

## Example Workflow

```bash
# 1. Build dependency graph
./graph-builder.sh > graph.json

# 2. Check for updates
./check-updates.sh graft-knowledge graph.json > updates.json

# 3. Create PRs (dry run first)
DRY_RUN=true ./create-pr.sh updates.json

# 4. Create PRs for real
./create-pr.sh updates.json
```

## Error Handling

All scripts:
- Exit with non-zero status on error
- Log to stderr
- Output JSON results to stdout
- Use `set -euo pipefail` for strict error handling

## Testing

Run scripts individually with sample data:

```bash
# Test graph builder
FORGEJO_TOKEN="test" ./graph-builder.sh

# Test update checker with mock graph
echo '{"graft-knowledge": [{"repo": "graft", "dep_name": "graft-knowledge"}]}' > test-graph.json
./check-updates.sh graft-knowledge test-graph.json

# Test PR creator in dry run
DRY_RUN=true ./create-pr.sh test-updates.json
```
