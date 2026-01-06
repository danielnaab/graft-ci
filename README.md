# graft-ci

Central CI/CD service for Graft dependency automation.

## Quick Start

- **Documentation**: [docs/README.md](docs/README.md)
- **For Agents**: [docs/agents.md](docs/agents.md)
- **Configuration**: [knowledge-base.yaml](knowledge-base.yaml)

## Purpose

This service implements automated dependency update detection and pull request creation for repositories using Graft dependency management.

Based on the [Dependency Update Notification Specification](https://forgejo.example/daniel/graft-knowledge/src/branch/main/docs/specification/dependency-update-notification.md) from graft-knowledge.

## Dependencies

This repository depends on:
- meta-knowledge-base - Documentation standards and conventions
- graft-knowledge - Graft specifications and decisions

See [graft.yaml](graft.yaml) for dependency configuration.
