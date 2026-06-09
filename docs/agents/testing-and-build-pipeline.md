---
title: Testing and Build Pipeline
scribe:
  scan: fcd8fcbc7c7e4b312a9401b873b1db9ffae544d7
  freshness: 100
  human_input: 1
  completeness: 75
  watch_paths:
    - tests/
    - kiali-server/ci/
    - Makefile
    - hack/
  inferred_sections:
    - id: overview
      heading: Overview
    - id: test-file-format
      heading: Test File Format
    - id: running-tests
      heading: Running Tests
    - id: test-categories
      heading: Test Categories
    - id: ci-value-fixtures
      heading: CI Value Fixtures
    - id: build-system
      heading: Build System
    - id: crd-sync
      heading: CRD Synchronization
    - id: integration-test-setup
      heading: Integration Test Setup
  stale_flags: []
  review_notes:
    - finding: "Test counts (~127, ~26) will drift as tests are added; verify with ls | wc -l in tests/ subdirectories"
      severity: minor
      tag: TAG-005
      confidence: 0.9
      date: "2026-05-08"
---

# Testing and Build Pipeline

> Custom helm-template test framework, Makefile build targets, and CRD synchronization workflow for the Kiali Helm charts.

## Overview

The repo uses a bespoke test runner (`tests/run-helm-chart-tests.sh`) rather than the built-in `helm test` mechanism. Each test is a YAML file that specifies Helm arguments, a `yq` query to extract a specific field from the rendered output, and the expected value of that field. This approach tests the exact rendered YAML rather than running pods.

The build system is Makefile-based and produces versioned chart tarballs in `_output/charts/`. CRDs are kept in sync with the upstream `kiali-operator` repository via dedicated Makefile targets.

## Test File Format

Each test file in `tests/kiali-server-tests/` or `tests/kiali-operator-tests/` is a YAML document with these fields:

```yaml
name: "test_name_with_underscores"       # unique identifier; becomes the release name
description: "Human readable description"
helm_args:                                # --set / -f flags passed to helm template
  - "--set"
  - "deployment.replicas=3"
yq_query: ".spec.replicas"               # yq expression applied to the full helm template output
expected_result: |                        # exact string to match against yq output
  3
should_fail: false                        # true = expect helm template to fail
expected_error_pattern: ""               # substring to match in the failure output (when should_fail: true)
```

The runner invokes `helm template <release-name> <chart-path> --skip-tests <helm_args>`, pipes the output through a **two-stage yq pipeline**: `yq eval "<yq_query>" | yq eval 'select(. != null)'`. The second stage strips null nodes before the comparison. The result is compared with `expected_result` using `diff -u`. Leading/trailing whitespace matters (use `|` block scalar for multi-line expectations).

For failure tests (`should_fail: true`), the runner redirects both stdout and stderr to a file and checks that `helm template` exits non-zero. When `expected_error_pattern` is set, it is matched against the **combined stdout+stderr output** (not stderr alone).

## Running Tests

Prerequisites: `helm`, `yq` (mikefarah/yq v4), `make`.

```bash
# Run all server tests (default)
./tests/run-helm-chart-tests.sh

# Run all operator tests
./tests/run-helm-chart-tests.sh --test-suite operator

# Run specific tests by name (extension and path are stripped automatically)
./tests/run-helm-chart-tests.sh deployment-replicas auth-strategy-token

# Run with debug mode — keeps temp files and prints helm commands
./tests/run-helm-chart-tests.sh --debug true deployment-replicas
```

The runner always builds the chart first (`make clean-charts && make build-helm-charts`) before running tests, so it always tests the latest build from source. Chart output goes to `_output/charts/kiali-server` or `_output/charts/kiali-operator` depending on the suite.

In debug mode, intermediate files are preserved in a temp directory (`/tmp/kiali-helm-tests.XXXXXXXXXX/`):
- `test_<name>_helm_output.yaml` — full `helm template` output
- `test_<name>_expected.yaml` — expected value
- `test_<name>_output.yaml` — yq-extracted actual value

Debug mode also prints the exact `helm template` command for manual reproduction, and a separate `helm install --dry-run` command. The dry-run command is the only way to view `NOTES.txt` content, since `helm template --skip-tests` does not render it.

## Test Categories

**kiali-server-tests** (~127 tests) cover:

| Category | Example Files |
|---|---|
| Auth strategy | `auth-strategy-token.yaml`, `auth-openid-configuration.yaml` |
| Deployment config | `deployment-replicas.yaml`, `deployment-resources.yaml`, `deployment-image-configuration.yaml` |
| Container security | `deployment-containers-security.yaml`, `deployment-containers-security-overrides.yaml`, `deployment-main-container-security-context.yaml` |
| Credential secrets | `credential-secret-prometheus-password.yaml`, `credential-secret-chatai-*.yaml`, `credential-secret-security-guardrails.yaml` |
| RBAC | `rbac-cluster-wide-access.yaml`, `rbac-no-cluster-wide-access.yaml`, `cluster-wide-access-false-*.yaml` |
| NetworkPolicy | `networkpolicy-default-enabled.yaml`, `networkpolicy-custom-*.yaml` |
| HPA | `hpa-configuration.yaml`, `hpa-removes-replicas.yaml` |
| CA bundle | `cabundle-*.yaml` |
| Ingress | `ingress-configuration.yaml` |
| Custom secrets | `custom-secrets-basic.yaml`, `custom-secrets-csi.yaml` |
| Feature flags | `kiali-feature-flags-*.yaml` |
| Server config | `server-port-configuration.yaml`, `server-web-root*.yaml` |
| Skip resources | `skip-resources-*.yaml` |
| Remote cluster | `deployment-remote-cluster-resources-only.yaml` |

**kiali-operator-tests** (~26 tests) cover:

| Category | Example Files |
|---|---|
| CR creation | `cr-creation-and-operator-deployment.yaml`, `cr-creation-cluster-wide-access.yaml` |
| Deployment | `deployment-affinity.yaml`, `deployment-image-configuration.yaml`, `deployment-security-context.yaml` |
| Watches file | `deployment-watches-file-custom.yaml`, `deployment-watch-namespace.yaml` |
| Permissions flags | `deployment-permission-flags.yaml` |
| Skip resources | `skip-resources-cluster-rbac.yaml`, `skip-resources-serviceaccount.yaml` |

## CI Value Fixtures

`kiali-server/ci/` contains values files used during CI chart testing (e.g., `helm install --values`). Each fixture exercises a different configuration mode:

| Fixture | Purpose |
|---|---|
| `auth-anonymous-values.yaml` | Auth strategy = anonymous |
| `cluster-wide-access-false-values.yaml` | Namespace-scoped RBAC |
| `cluster-wide-access-true-values.yaml` | Cluster-wide RBAC (default) |
| `cluster-wide-access-true-with-ds-values.yaml` | Cluster-wide + discovery selectors |
| `selector-and-logic-values.yaml` | Namespace selector with AND logic |
| `selector-or-logic-values.yaml` | Namespace selector with OR logic |
| `selector-operators-values.yaml` | Selector with NotIn/Exists/DoesNotExist operators |
| `view-only-mode-anonymous-values.yaml` | View-only mode with anonymous auth |
| `view-only-mode-values.yaml` | View-only mode enabled |
| `zero-namespaces-matched-values.yaml` | Selector matches no namespaces |

These fixtures also serve as reference examples for common configurations. The `run-server-itests` Makefile target runs `ct install --charts kiali-server` using these fixture files against a live cluster.

## Build System

The Makefile root (`Makefile`) at repo root drives chart lifecycle:

```makefile
VERSION ?= v2.27.0-SNAPSHOT    # Version token injected into charts
HELM_VERSION ?= v3.10.1        # Helm binary version for chart build
```

Key targets:

| Target | Description |
|---|---|
| `build-helm-charts` | Packages both charts into `_output/charts/` with `VERSION` substituted |
| `clean` | Removes the entire `_output/` directory |
| `clean-charts` | Removes only `_output/charts/` (preserves downloaded Helm binary) |
| `validate-crd-sync` | Downloads golden CRDs from upstream and diffs against local copies |
| `sync-crds` | Downloads golden CRDs and overwrites local files |
| `update-helm-repos` | Copies versioned chart tarballs to `docs/` and regenerates the Helm repo index at `docs/index.yaml` |
| `verify-kiali-server-permissions` | Downloads and runs the kiali-operator permission verification script against the rendered chart; useful after RBAC changes |
| `run-helm-tests` | Runs helm template tests (server and/or operator); accepts `TEST_SUITE=server\|operator` and `DEBUG=true` |
| `run-server-itests` | Runs integration tests via `chart-testing` against a live cluster; downloads `ct` v3.11.0 to `_output/bin/ct` if not in PATH; passes `--helm-extra-args "--timeout 2m"` (may need adjusting on slow clusters) |
| `run-server-itest-single` | Runs a single CI fixture integration test; requires `TEST_NAME=<fixture-name>` |
| `help` | Lists all targets (parses `## comment:` annotations) |

The build substitutes `${HELM_IMAGE_REPO}` and `${HELM_IMAGE_TAG}` tokens in `values.yaml` files using **`envsubst`** (not sed) before packaging. The source files always contain placeholder tokens; the substituted copy goes into `_output/charts/`.

## CRD Synchronization

The Kiali CRD (`kialis.kiali.io`) and OSSMConsole CRD (`ossmconsoles.kiali.io`) are defined and maintained in the `kiali-operator` upstream repository. The helm-charts repo contains copies:

- `kiali-operator/crds/crds.yaml` — Kiali CRD (installed via Helm `crds/`)
- `kiali-operator/templates/ossmconsole-crd.yaml` — OSSMConsole CRD (templated, OpenShift only)

`make validate-crd-sync` checks both:
1. Downloads the golden Kiali CRD from `https://raw.githubusercontent.com/kiali/kiali-operator/master/crd-docs/crd/kiali.io_kialis.yaml`
2. Compares with `kiali-operator/crds/crds.yaml`
3. Downloads the golden OSSMConsole CRD and compares with the CRD content extracted from `kiali-operator/templates/ossmconsole-crd.yaml` (stripping the surrounding Helm template logic)

`make sync-crds` performs the same download and writes the files in-place. The upstream ref is configurable via `KIALI_OPERATOR_ORG_REPO_REF` (default: `kiali/kiali-operator/master`).

CRD sync is intentionally not automatic — it is a deliberate manual step to track upstream changes.

## Integration Test Setup

`hack/helm-tests-setup.sh` creates Kubernetes namespaces with specific labels required for the integration tests that exercise `deployment.discovery_selectors` behavior:

```bash
# AND logic tests — both matchLabels AND matchExpressions must match
kubectl create namespace test-and-both-match  # istio-injection=enabled, env=prod
kubectl create namespace test-and-labels-only # istio-injection=enabled, env=dev
kubectl create namespace test-and-expr-only   # istio-injection=disabled, env=prod

# OR logic tests — multiple selectors (union)
kubectl create namespace test-or-first-match  # istio-injection=enabled
kubectl create namespace test-or-second-match # monitoring=prometheus
kubectl create namespace test-or-neither      # app=other

# Operator expression tests — NotIn, Exists, DoesNotExist
kubectl create namespace test-op-not-dev      # env=prod, team=platform
kubectl create namespace test-op-is-dev       # env=dev, team=app
kubectl create namespace test-op-no-team      # env=prod (no team label)
```

`hack/helm-tests-cleanup.sh` removes these namespaces. These namespaces are only needed for integration tests that use `helm install/upgrade` against a live cluster (where `lookup` works); unit tests using `helm template` do not need them.
