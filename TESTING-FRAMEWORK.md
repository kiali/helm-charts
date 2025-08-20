# Kiali Helm Chart Testing Framework

## Overview

The Kiali Helm Chart testing framework is a modular and extensible testing system for validating Helm chart functionality for both kiali-server and kiali-operator charts. This framework allows developers to add new tests by simply creating YAML test files without modifying the main test runner script.

## Architecture

### Main Components

1. **`tests/run-helm-chart-tests.sh`** - Main test runner script (supports both server and operator tests)
2. **`tests/kiali-server-tests/`** - Directory containing server chart test files
3. **`tests/kiali-operator-tests/`** - Directory containing operator chart test files
4. **`tests/README.md`** - Documentation for test file format and usage

### Test Execution Flow

1. **Prerequisites Check**: Validates `helm`, `yq`, and `make` are available
2. **Build Phase**: Runs `make clean build-helm-charts` to build chart packages
3. **Discovery Phase**: Finds all `*.yaml` files in the `tests/kiali-server-tests/` or `tests/kiali-operator-tests/` directory based on test suite
4. **Execution Phase**: For each test file:
   - Parses test configuration from YAML
   - Executes: `helm template [release-name] _output/charts/kiali-server|kiali-operator [args...]`
   - Applies: `yq eval "[query]" [helm-output]`
   - Compares: Actual output vs expected result
5. **Reporting Phase**: Shows pass/fail summary and details

## Test File Format

Each test is defined in a YAML file with this structure:

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

## Adding New Tests

To add a new server test:

1. Create a new file: `tests/kiali-server-tests/[name].yaml`
2. Follow the YAML format documented in `tests/README.md`
3. Run `./tests/run-helm-chart-tests.sh [test-name]` to validate

To add a new operator test:

1. Create a new file: `tests/kiali-operator-tests/[name].yaml`
2. Follow the YAML format documented in `tests/README.md`
3. Run `./tests/run-helm-chart-tests.sh --test-suite operator [test-name]` to validate

## Key Benefits

### ✅ **Extensibility**
- Add tests without modifying code
- Each test is self-contained
- Easy to maintain and review

### ✅ **Modularity**
- Tests can be developed independently
- Clear separation of concerns
- Easy to debug individual tests

### ✅ **Maintainability**
- YAML format is human-readable
- Test logic separated from execution logic
- Consistent test patterns

### ✅ **Developer Experience**
- Simple test file format
- Clear error reporting
- Comprehensive documentation

## Usage

```bash
# Run all server tests (default)
./tests/run-helm-chart-tests.sh

# Run all operator tests
./tests/run-helm-chart-tests.sh --test-suite operator

# Run specific server tests by filename (with or without .yaml extension)
./tests/run-helm-chart-tests.sh clustering-autodetect-secrets deployment-replicas

# Run specific operator tests
./tests/run-helm-chart-tests.sh --test-suite operator cr-creation-and-operator-deployment

# Run tests with full paths (path stripping works)
./tests/run-helm-chart-tests.sh tests/kiali-server-tests/auth-strategy-token.yaml
./tests/run-helm-chart-tests.sh --test-suite operator tests/kiali-operator-tests/cr-creation-and-operator-deployment.yaml

# Show help
./tests/run-helm-chart-tests.sh --help

# Test output shows:
# - Prerequisites check
# - Build phase status
# - Individual test results
# - Summary with pass/fail counts
```

## Debugging Test Framework

### Debug Mode

#### Debug Mode (`--debug`)
```bash
# Run with debug mode enabled (verbose output + save all files)
./tests/run-helm-chart-tests.sh --debug true test-name
./tests/run-helm-chart-tests.sh --test-suite operator --debug true test-name

# Run with debug mode disabled (normal operation)
./tests/run-helm-chart-tests.sh --debug false test-name
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
- Faster execution for production use

**Use debug mode when:**
- You need to see **what arguments** are being passed to helm
- You want to see **what yq query** is being executed
- You need to **examine the full generated YAML** in detail
- You want to **test different yq queries** against the same output
- You're **developing new tests** and need to explore the YAML structure
- You want to **share the output** with others for analysis
- Complex test failure that needs full analysis

**Benefits:**
- Single option controls all debugging features
- Complete YAML preserved for analysis (full ~10KB files)
- Can test queries offline against saved output
- Perfect for test development workflow
- Enables offline analysis and collaboration

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

### Debug File Locations

When `--debug true` is used, files are preserved in `/tmp/kiali-helm-tests/`:

```
/tmp/kiali-helm-tests/
├── test_test-name_expected.yaml           # Expected result from test
├── test_test-name_output.yaml             # Actual yq query result
└── test_test-name_helm_output.yaml        # Complete Helm template output
```

### Pro Tips

#### Iterative Development
1. Start with `--debug true` to see what's happening
2. Use `--save-helm-output true` to inspect full Helm output
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

### Debugging Failing Tests

```bash
# For failing test analysis:
./tests/run-helm-chart-tests.sh --debug true failing-test-name
./tests/run-helm-chart-tests.sh --test-suite operator --debug true failing-test-name

# Check debug output for:
# - Helm arguments (are they correct?)
# - yq query (does it target the right path?)
# - Expected vs actual diff (formatting issue?)
# - Helm output (does the field exist?)
```

This debugging approach will help you quickly identify and fix test issues!
