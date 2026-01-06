# graft-ci

Central CI/CD service for Graft dependency automation.

This KB follows the [meta knowledge base entrypoint](https://forgejo.example/daniel/meta-knowledge-base/src/branch/main/docs/meta.md).

## Purpose

graft-ci implements automated dependency update propagation for the Graft ecosystem. When upstream repositories are updated, this service detects changes and creates pull requests in consuming repositories.

## Quick Start

- [QUICKSTART](../QUICKSTART.md) - Get running in 10 minutes
- [Workflow Setup](workflow-setup.md) - Forgejo Actions configuration

## Documentation

- [Setup Guide](setup.md) - Installation and configuration
- [Testing Plan](testing-plan.md) - Progressive testing strategy
- [Implementation Plan](specification/dependency-update-automation.md) - Core automation implementation
- [Agent Entrypoint](agents.md) - For automated agents
- [Domain Configuration](../knowledge-base.yaml) - Knowledge base settings
- [Decisions](decisions/decision-0001-shell-script-implementation.md) - Architecture decisions

## Architecture

The service implements the [Dependency Update Notification Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md) from graft-knowledge.

Key components:

- **Dependency Graph Builder**: Scans organization repositories and parses graft.yaml files to build an inverted dependency index
- **Update Detector**: Monitors upstream repositories for changes using git ls-remote
- **PR Creator**: Generates pull requests in consumer repositories with updated dependency references

## Workflow

The system operates in two modes:

1. Event-driven: Organization webhooks trigger on repository push events
2. Scheduled: Periodic polling as fallback for missed events

## Sources

- [graft-knowledge: Dependency Update Notification Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md) - Functional and non-functional requirements
- [graft-knowledge: Decision 0006 - Dependency Update Events](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/decisions/decision-0006-dependency-update-events.md) - Event strategy rationale
- [meta-knowledge-base](https://forgejo.example/daniel/meta-knowledge-base/src/branch/main/docs/meta.md) - Documentation standards and conventions
