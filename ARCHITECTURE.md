# Architecture

> This file is a navigation index. For detailed documentation, follow the links below.

## Documentation Index

- [Kiali Operator Chart](docs/agents/kiali-operator-chart.md) — Helm chart for installing the Kiali Operator — an Ansible-based Kubernetes operator that watches for `Kiali` CRs and reconciles them into running Kiali Server instances.
- [Kiali Server Chart](docs/agents/kiali-server-chart.md) — Helm chart for deploying the Kiali Server directly, without an operator. Produces all Kubernetes resources needed to run Kiali and expose it to users.
- [Testing and Build Pipeline](docs/agents/testing-and-build-pipeline.md) — Custom helm-template test framework, Makefile build targets, and CRD synchronization workflow for the Kiali Helm charts.

## Quick Reference

See [AGENTS.md](AGENTS.md) for commands, build instructions, and a directory overview.
