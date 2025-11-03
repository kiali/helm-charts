# Kiali Helm Charts Testing

This document describes all testing frameworks for the Kiali Helm charts.

## Overview

There are two independent test frameworks:

1. **Template-Based Tests** - Unit tests using `helm template` (no cluster required)
2. **Helm Integration Tests** - Integration tests using `helm test` (requires live cluster)

## Available Make Targets

| Target | Description | Requirements |
|--------|-------------|--------------|
| `make run-helm-tests` | Run all template-based tests (server + operator) | No cluster |
| `make run-helm-tests TEST_SUITE=server` | Run only server template tests | No cluster |
| `make run-helm-tests TEST_SUITE=operator` | Run only operator template tests | No cluster |
| `make run-helm-tests DEBUG=true` | Run template tests with debug output | No cluster |
| `make run-server-itests` | Run integration tests (requires cluster) | Live cluster |
| `make run-server-itest-single TEST_NAME=<name>` | Run single integration test | Live cluster |

---

# Test Framework 1: Template-Based Tests

## Purpose

Unit tests that validate template rendering without requiring a Kubernetes cluster. These tests use `helm template` to render templates and `yq` to validate the output.

## Location

- Test runner: `tests/run-helm-chart-tests.sh`
- Server tests: `tests/kiali-server-tests/*.yaml`
- Operator tests: `tests/kiali-operator-tests/*.yaml`

## Quick Start

### Using Makefile Target (Recommended)

```bash
cd <kiali-helm-charts-repo>

# Run both server and operator tests
make run-helm-tests

# Run only server tests
make run-helm-tests TEST_SUITE=server

# Run only operator tests
make run-helm-tests TEST_SUITE=operator

# Run with debug output
make run-helm-tests DEBUG=true
make run-helm-tests TEST_SUITE=server DEBUG=true
```

### Using Script Directly

```bash
cd <kiali-helm-charts-repo>

# Run all server tests (default)
./tests/run-helm-chart-tests.sh

# Run all operator tests
./tests/run-helm-chart-tests.sh --test-suite operator

# Run specific tests
./tests/run-helm-chart-tests.sh test1 test2

# Run with debug mode
./tests/run-helm-chart-tests.sh --debug true test-name
```

## Test File Format

Each test is a YAML file with this structure:

```yaml
name: "test_identifier"
description: "Human-readable test description"
helm_args:
  - "--set"
  - "key=value"
  - "--set"
  - "another.key=value"
yq_query: ".path.to.yaml.field"
expected_result: |
  key: value
  nested:
    field: value
should_fail: false
expected_error_pattern: "optional error pattern"
```

### Test Fields

- **name**: Unique identifier for the test (used in reporting)
- **description**: Human-readable description of what the test validates
- **helm_args**: Array of command-line arguments passed to `helm template`
- **yq_query**: Query to extract specific YAML content from helm output
- **expected_result**: Expected YAML content that should match the query result
- **should_fail**: Boolean indicating if the helm command should fail (default: false)
- **expected_error_pattern**: For failure tests, optional pattern to match in error output

## Test Execution Flow

1. **Prerequisites Check**: Validates `helm`, `yq`, and `make` are available
2. **Build Phase**: Runs `make clean build-helm-charts` to build chart packages
3. **Discovery Phase**: Finds all `*.yaml` files in the test directory
4. **Execution Phase**: For each test:
   - Executes: `helm template [release-name] _output/charts/kiali-server|kiali-operator --skip-tests [helm_args...]`
   - Applies: `yq eval "[yq_query]" [helm-output]`
   - Compares: Actual output vs expected_result
5. **Reporting Phase**: Shows pass/fail summary and details

## Adding New Tests

### For Server Tests:
1. Create file: `tests/kiali-server-tests/[name].yaml`
2. Follow the YAML format above
3. Run: `./tests/run-helm-chart-tests.sh your-test-name`

### For Operator Tests:
1. Create file: `tests/kiali-operator-tests/[name].yaml`
2. Follow the YAML format above
3. Run: `./tests/run-helm-chart-tests.sh --test-suite operator your-test-name`

## Test Examples

### Server Test Example
```yaml
name: "deployment_replicas"
description: "Verify custom replica count is set correctly"
helm_args:
  - "--set"
  - "deployment.replicas=3"
yq_query: "select(.kind == \"Deployment\") | .spec.replicas"
expected_result: |
  3
should_fail: false
```

### Operator Test Example
```yaml
name: "cr_creation_and_operator_deployment"
description: "Verify that when CR creation is enabled, both operator Deployment and Kiali CR are generated correctly"
helm_args:
  - "--set"
  - "cr.create=true"
  - "--set"
  - "cr.namespace=kiali-home-namespace"
yq_query: "(select(.kind == \"Deployment\") | .kind), (select(.kind == \"Kiali\") | {\"kind\": .kind, \"name\": .metadata.name, \"namespace\": .metadata.namespace})"
expected_result: |
  Deployment
  ---
  kind: Kiali
  name: kiali
  namespace: "kiali-home-namespace"
should_fail: false
```

## Debugging

### Debug Mode

```bash
# Enable verbose output and save all files
./tests/run-helm-chart-tests.sh --debug true test-name
./tests/run-helm-chart-tests.sh --test-suite operator --debug true test-name
```

**When debug is `true`:**
- Shows verbose execution output (Helm arguments, yq queries)
- Saves complete Helm template output for analysis
- Preserves all test comparison files
- Provides detailed guidance on viewing saved files

**When debug is `false`:**
- Normal quiet operation
- No verbose logging
- Cleans up temporary files after execution
- Faster execution

**Use debug mode when:**
- You need to see what arguments are being passed to helm
- You want to see what yq query is being executed
- You need to examine the full generated YAML in detail
- You want to test different yq queries against the same output
- You're developing new tests and need to explore the YAML structure
- Complex test failure that needs full analysis

### Debug File Locations

When `--debug true` is used, files are preserved in `/tmp/kiali-helm-tests/`:

```
/tmp/kiali-helm-tests/
├── test_test-name_expected.yaml           # Expected result from test
├── test_test-name_output.yaml             # Actual yq query result
└── test_test-name_helm_output.yaml        # Complete Helm template output
```

### Manual Debugging Techniques

#### Run Helm Commands Directly
```bash
# Copy helm args from test file and run manually
helm template test-name _output/charts/kiali-server \
  --set deployment.replicas=3 \
  | tee /tmp/debug-output.yaml

# Then test yq queries manually
yq eval 'select(.kind == "Deployment") | .spec.replicas' /tmp/debug-output.yaml
```

#### Test yq Queries Interactively
```bash
# Start with basic query and build up
helm template test _output/charts/kiali-server --set key=value > output.yaml

# Test different query approaches
yq eval '.kind' output.yaml                    # See all resource types
yq eval 'select(.kind == "Deployment")' output.yaml  # Filter by type
yq eval 'select(.kind == "Deployment") | .spec.replicas' output.yaml  # Specific field
```

#### Compare Expected vs Actual
```bash
# Run test to generate files
./tests/run-helm-chart-tests.sh --debug true test-name

# Compare files manually
diff -u /tmp/kiali-helm-tests/test_test-name_expected.yaml \
        /tmp/kiali-helm-tests/test_test-name_output.yaml
```

### Common Debugging Scenarios

#### yq Query Issues
```bash
# Problem: Query returns nothing
# Debug: Check resource exists
yq eval '.kind' output.yaml | sort | uniq

# Problem: Wrong field
# Debug: Explore structure
yq eval 'select(.kind == "Deployment") | keys' output.yaml
yq eval 'select(.kind == "Deployment") | .spec | keys' output.yaml
```

#### YAML Formatting Differences
```bash
# Problem: Same content, different formatting
# Solution: Use yq to normalize both sides
yq eval 'sort_keys(.)' expected.yaml > expected_norm.yaml
yq eval 'sort_keys(.)' actual.yaml > actual_norm.yaml
diff expected_norm.yaml actual_norm.yaml
```

#### Helm Template Issues
```bash
# Debug helm template failures
helm template test _output/charts/kiali-server \
  --set invalid.key=value \
  --debug --dry-run

# Check chart syntax
helm lint _output/charts/kiali-server
```

### Pro Tips

#### Iterative Development
1. Start with `--debug true` to see what's happening
2. Inspect full Helm output
3. Test yq queries manually against saved output
4. Refine test until it passes

#### Common yq Patterns
```bash
# Select by resource type
select(.kind == "Deployment")

# Get specific field
.spec.replicas

# Filter arrays
.spec.template.spec.containers | map(select(.name == "kiali"))

# Count items
[select(.kind == "Service")] | length

# Handle missing fields
.spec.optional_field // "default-value"
```

#### Helm Value Testing
```bash
# Test if value is applied correctly
helm template test _output/charts/kiali-server \
  --set deployment.replicas=5 \
  | yq eval 'select(.kind == "Deployment") | .spec.replicas'
# Should output: 5
```

### Test Development Workflow

1. **Identify** what you want to test
2. **Run** helm template manually with your values
3. **Inspect** the output to understand structure
4. **Craft** yq query to extract desired field
5. **Create** test file with query and expected result
6. **Run** test with `--debug true` to verify
7. **Iterate** until test passes

### Key Benefits

- ✅ **Extensibility**: Add tests without modifying code
- ✅ **Modularity**: Tests developed independently
- ✅ **Maintainability**: YAML format is human-readable
- ✅ **Fast**: No cluster required, runs in seconds
- ✅ **Developer Experience**: Simple format, clear error reporting

---

# Test Framework 2: Helm Integration Tests

## Purpose

Integration tests using [Helm's official test framework](https://helm.sh/docs/topics/chart_tests/) that validate functionality against a live Kubernetes cluster.

## Location

- Test templates: `kiali-server/templates/tests/`
- Test value files: `kiali-server/ci/*.yaml`

## Important Notes

- These test templates are **excluded from the published chart** via `kiali-server/.helmignore`
- They are only available when installing from the **source directory**

## How to Run

### Using Makefile Target (Recommended - Fully Automated)

```bash
cd <kiali-helm-charts-repo>
make run-server-itests
```

This automatically downloads [chart-testing](https://github.com/helm/chart-testing) if not installed and runs all server test scenarios.

### Using chart-testing Directly

```bash
cd <kiali-helm-charts-repo>

# Install chart-testing (ct) if not already installed
# See: https://github.com/helm/chart-testing#installation

# Run all test scenarios automatically
ct install --charts kiali-server --helm-extra-args "--timeout 2m"
```

chart-testing will:
- Find all `kiali-server/ci/*.yaml` value files
- Install the chart once for each values file
- Run `helm test` for each installation
- Clean up between scenarios
- Report results

## Prerequisites

- Running Kubernetes cluster
- `kubectl` configured and connected
- `helm` installed (3.10+)
- Must install from source directory (not packaged chart)
- `chart-testing` (ct) installed for automated testing

## Test Scenarios

Test scenarios are defined in `kiali-server/ci/*.yaml`. Each file represents a different configuration to test. chart-testing will automatically discover and run all scenarios.

## Test Setup and Cleanup

Some tests require pre-existing resources. These scripts must be run prior to and after the tests run:
- `hack/helm-tests-setup.sh`
- `hack/helm-tests-cleanup.sh`

The `make run-server-itests` target automatically runs setup before tests and cleanup after.

## Adding New Test Scenarios

To add a new test scenario:

1. Create a new values file: `kiali-server/ci/<scenario-name>-values.yaml`
2. Define the configuration for that scenario
3. If the scenario requires specific namespace labels, update `helm-tests-setup.sh`
4. Run: `make run-server-itests` (will automatically include the new scenario)

Example:
```yaml
# kiali-server/ci/custom-discovery-selectors-values.yaml
deployment:
  cluster_wide_access: false
  image_version: latest
  version_label: test
  discovery_selectors:
    default:
    - matchLabels:
        istio-injection: enabled
  probes:
    startup:
      failure_threshold: 10
      initial_delay_seconds: 1
      period_seconds: 1
```

## How Helm Tests Work

1. Test templates are in `templates/tests/` with `"helm.sh/hook": test` annotation
2. During `helm install`, only the RBAC setup resources are created (ServiceAccount, ClusterRole, ClusterRoleBinding)
3. The actual test Pods are NOT created during install
4. When you run `helm test <release>`, Helm:
   - Retrieves the stored release values from the cluster
   - Renders test templates using those values
   - Creates test Pods that match the configuration
   - Runs the pods and checks if they exit successfully (exit 0)
5. Test resources auto-delete after success via `"helm.sh/hook-delete-policy"`

## Test Images

The test pods use `quay.io/curl/curl:latest` as the base image and download `kubectl` and `yq` from official sources:

```bash
# kubectl from official Kubernetes releases
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# yq from official GitHub releases
curl -LO "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
```
