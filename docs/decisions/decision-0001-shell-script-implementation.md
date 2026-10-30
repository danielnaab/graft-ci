---
title: "Shell Script Implementation"
date: 2026-01-06
status: stable
---

# Decision 0001: Shell Script Implementation

## Context

The graft-ci service requires automation scripts to build dependency graphs, check for updates, and create pull requests. We need to choose an implementation language that balances simplicity, maintainability, and alignment with graft's design principles.

Key considerations:
- Minimal dependencies requirement from specification
- Fast execution (target: under 10 seconds end-to-end)
- Easy debugging and modification
- Available in standard CI environments
- Alignment with graft's tooling philosophy

## Decision

**Implement core automation using Bash shell scripts with standard Unix tools (curl, jq, yq, git).**

## Alternatives Considered

### Alternative 1: Python

**Approach**: Use Python with requests and PyYAML libraries

**Pros**:
- More robust error handling
- Better data structure manipulation
- Easier testing with unittest/pytest
- More readable for complex logic
- Type hints for documentation

**Cons**:
- Additional runtime dependency (Python 3.x)
- Package management (pip, venv)
- Slower startup time for small tasks
- Deviates from graft's minimal dependency philosophy
- Requires more boilerplate code

**Why not chosen**: Adds significant dependencies for tasks that are primarily API calls and git operations. The specification emphasizes minimal dependencies, and Python would add runtime + packages.

### Alternative 2: Go

**Approach**: Compiled Go binaries for each component

**Pros**:
- Fast execution
- Static binary (no runtime dependencies)
- Excellent error handling
- Strong typing
- Good for complex logic

**Cons**:
- Compilation step required
- Higher complexity for simple API calls
- Harder to modify in-place
- Larger codebase for basic operations
- Build toolchain required

**Why not chosen**: Over-engineering for API calls and git operations. The compilation requirement makes quick modifications harder, which conflicts with graft's goal of easy customization.

### Alternative 3: Node.js/TypeScript

**Approach**: JavaScript/TypeScript with node-fetch and yaml libraries

**Pros**:
- Good JSON handling (native)
- Async/await for concurrent operations
- npm ecosystem
- Familiar to many developers

**Cons**:
- Requires Node.js runtime
- Package management overhead
- Slower startup than shell
- Additional dependency layer
- Not standard in all CI environments

**Why not chosen**: Runtime dependency and npm packages conflict with minimal dependency requirement.

### Alternative 4: Makefile with shell targets

**Approach**: Use Make to orchestrate shell commands

**Pros**:
- Standard build tool
- Good for task orchestration
- Built-in dependency tracking
- Familiar pattern

**Cons**:
- Make syntax complexity
- Less portable across platforms
- Harder to pass complex data between targets
- Not ideal for long scripts

**Why not chosen**: Make is better for build orchestration than data processing. Shell scripts are more direct for our use case.

## Rationale

Shell scripts with standard tools align with graft's design philosophy:

1. **Minimal Dependencies**: curl, jq, yq, git are standard in CI environments
2. **Fast Execution**: No runtime startup overhead, direct process invocation
3. **Transparency**: Easy to read and understand data flow
4. **Debuggability**: Can run commands interactively, inspect intermediate results
5. **Portability**: POSIX shell runs everywhere
6. **Composability**: Unix philosophy of small tools doing one thing well

The specification explicitly lists "shell, git, curl" as target dependencies, supporting this choice.

## Implementation Guidelines

To mitigate shell script limitations:

1. **Strict Mode**: Use `set -euo pipefail` in all scripts
2. **Function Decomposition**: Small, focused functions
3. **Logging**: Consistent stderr logging with prefixes
4. **Error Handling**: Check return codes and provide context
5. **JSON I/O**: Use jq for all JSON operations
6. **YAML Parsing**: Use yq (static binary) for graft.yaml
7. **ShellCheck**: Validate scripts with linter

## Consequences

### Positive

- **Zero additional runtime dependencies**: Works in any Linux CI environment
- **Fast startup**: No interpreter/runtime loading
- **Easy modification**: Edit and run, no build step
- **Transparent**: Clear data flow through pipes and files
- **Minimal**: Aligns with graft philosophy

### Negative

- **Limited error handling**: Bash error handling less sophisticated than modern languages
- **String manipulation**: More verbose than Python/Node
- **Testing**: Harder to unit test than code with test frameworks
- **Complex logic**: Shell becomes unwieldy for complex algorithms
- **Maintainability**: Requires shell scripting expertise

### Mitigations

- **Strict error handling**: Use `-e`, `-u`, `-o pipefail` consistently
- **JSON for data**: Use jq instead of bash string manipulation
- **Function composition**: Keep functions small and focused
- **Integration tests**: Test complete workflows rather than units
- **ShellCheck**: Automated validation catches common errors
- **Documentation**: Clear comments and function documentation

## Trade-offs Accepted

We accept:
- More verbose error handling in exchange for zero dependencies
- Manual testing over unit tests in exchange for simplicity
- Shell expertise requirement in exchange for transparency
- Limited concurrency primitives in exchange for portability

## Future Considerations

If complexity grows significantly, consider:
- Hybrid approach: Shell for orchestration, Python for complex logic
- Go rewrite if performance becomes critical
- But: Only migrate if evidence shows clear need (3+ concrete pain points)

## Related

- [graft-knowledge: Dependency Update Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md) - Lists "shell, git, curl" as target dependencies
- [meta-knowledge-base: Evolve KB Playbook](https://forgejo.example/daniel/meta-knowledge-base/src/branch/main/playbooks/evolve-kb.md) - Evidence-driven evolution principle

## Sources

- Graft specification requirement: "Minimal dependencies: Implementation should rely on standard tools (shell, git, curl)"
- Unix philosophy: Do one thing well, compose small tools
- Docker Alpine default tools: sh, curl, jq, git are standard
