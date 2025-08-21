# Kiali Helm Chart Test Framework

This directory contains modular test files for both the kiali-server and kiali-operator Helm charts. Each test file defines a specific test case that validates chart functionality and security guardrails.

## Directory Structure

- **`kiali-server-tests/`** - Test files for the kiali-server Helm chart
- **`kiali-operator-tests/`** - Test files for the kiali-operator Helm chart
- **`run-helm-chart-tests.sh`** - Test runner script supporting both test suites

## Test File Format

Each test file is a YAML file with the following structure:

```yaml
name: "test_name"                    # Unique test identifier
description: "Test description"      # Human-readable test description
helm_args:                          # Array of arguments to pass to helm template
  - "--set"
  - "key=value"
  - "--set"
  - "another.key=value"
yq_query: ".path.to.yaml.field"     # yq query to extract from helm output
expected_result: |                  # Expected YAML output (multi-line string)
  key: value
  nested:
    field: value
should_fail: false                  # Set to true if helm command should fail
expected_error_pattern: "error text" # Optional: pattern to match in error output
```

## Test Fields

- **name**: Unique identifier for the test (used in reporting)
- **description**: Human-readable description of what the test validates
- **helm_args**: Array of command-line arguments passed to `helm template`
- **yq_query**: Query to extract specific YAML content from helm output
- **expected_result**: Expected YAML content that should match the query result
- **should_fail**: Boolean indicating if the helm command should fail (default: false)
- **expected_error_pattern**: For failure tests, optional pattern to match in error output

## Running Tests

From the helm-charts directory, run:

```bash
# Run all server tests (default)
./tests/run-helm-chart-tests.sh

# Run all operator tests
./tests/run-helm-chart-tests.sh --test-suite operator

# Run specific server tests
./tests/run-helm-chart-tests.sh test1 test2

# Run specific operator tests
./tests/run-helm-chart-tests.sh --test-suite operator test1 test2

# Run with debug mode
./tests/run-helm-chart-tests.sh --debug true test-name
./tests/run-helm-chart-tests.sh --test-suite operator --debug true test-name

# Run with full paths (path stripping works automatically)
./tests/run-helm-chart-tests.sh tests/kiali-server-tests/test-name.yaml
./tests/run-helm-chart-tests.sh --test-suite operator tests/kiali-operator-tests/test-name.yaml
```

## How Tests Work

The test script will:
1. Check prerequisites (helm, yq, make)
2. Build helm charts (`make clean build-helm-charts`)
3. Discover all `*.yaml` files in the appropriate test directory based on test suite:
   - Server tests: `tests/kiali-server-tests/`
   - Operator tests: `tests/kiali-operator-tests/`
4. Run each test following the pattern:
   - Execute: `helm template test-name _output/charts/kiali-server|kiali-operator [helm_args...]`
   - Query: `yq eval "[yq_query]" [helm_output]`
   - Compare: Output vs expected_result
5. Report results and exit with appropriate code

## Adding New Tests

### For Server Tests:
1. Create a new file named `*.yaml` in the `kiali-server-tests/` directory
2. Follow the YAML format above
3. Run: `./tests/run-helm-chart-tests.sh your-test-name` to validate

### For Operator Tests:
1. Create a new file named `*.yaml` in the `kiali-operator-tests/` directory
2. Follow the YAML format above
3. Run: `./tests/run-helm-chart-tests.sh --test-suite operator your-test-name` to validate

## Test Examples

### Server Test Example
Tests specific server chart functionality like deployment configuration:
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
Tests operator chart functionality like CR creation:
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

For more comprehensive documentation, see [TESTING-FRAMEWORK.md](../TESTING-FRAMEWORK.md) in the parent directory.