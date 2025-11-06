#!/bin/bash

# Kiali Helm Chart Test Runner
# This script builds the helm charts and runs test files for either the kiali-server
# or kiali-operator charts. Test files are found in the kiali-server-tests/ or
# kiali-operator-tests/ directory depending on the test suite selected.
# Each test file defines a helm template test with expected outputs.
#
# Usage:
#   ./tests/run-helm-chart-tests.sh                                 # Run all server tests (default)
#   ./tests/run-helm-chart-tests.sh --test-suite operator           # Run all operator tests
#   ./tests/run-helm-chart-tests.sh test1 test2 ...                 # Run specific server tests by name
#   ./tests/run-helm-chart-tests.sh --test-suite operator test1     # Run specific operator tests
#   ./tests/run-helm-chart-tests.sh --help                          # Show help

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/kiali-helm-tests"

# Change to script directory to ensure consistent working directory
cd "${SCRIPT_DIR}"

# These will be set based on the test suite
TESTS_DIR=""
CHART_PATH=""

# Command line arguments
SPECIFIC_TESTS=()
SHOW_HELP=false
DEBUG_MODE=false
TEST_SUITE="server"  # Default to server tests

# Function to initialize clean temp directory
init_temp_dir() {
    # Clean any existing temp directory to avoid old test results
    if [[ -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning previous test output directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
    # Create fresh temp directory
    mkdir -p "${TEMP_DIR}"
}

# Placeholder - temp directory will be initialized when tests start

# Helper Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
}

show_help() {
    cat << EOF
Kiali Helm Chart Test Runner

USAGE:
    ./tests/run-helm-chart-tests.sh [OPTIONS] [TEST_NAMES...]

DESCRIPTION:
    Builds the helm charts and runs test files for either the kiali-server or kiali-operator
    charts. Test files are found in the tests/kiali-server-tests/ or tests/kiali-operator-tests/ directory
    depending on the test suite selected. Each test file defines a helm template test with
    expected outputs.

OPTIONS:
    --help, -h              Show this help message
    --test-suite SUITE      Test suite to run: 'server' or 'operator' (default: server)
    --debug <true|false>    Enable/disable debug mode (verbose output + save Helm files)

ARGUMENTS:
    TEST_NAMES          Optional list of specific test files to run.
                       Test names should match the filename (with or without .yaml extension).
                       Both parent directory paths and .yaml extensions will be automatically
                       stripped if provided (e.g., tests/kiali-server-tests/test-name.yaml -> test-name
                       or tests/kiali-operator-tests/test-name.yaml -> test-name).
                       If no test names are provided, all tests will be run.

EXAMPLES:
    $0                                                  # Run all server tests (default)
    $0 --test-suite operator                            # Run all operator tests
    $0 deployment-replicas server-port                  # Run specific server tests
    $0 --test-suite operator operator-config            # Run specific operator tests
    $0 auth-strategy-token                              # Run single server test
    $0 auth-strategy-token.yaml                         # Same as above (.yaml automatically stripped)
    $0 tests/kiali-server-tests/auth-strategy-token.yaml      # Same as above (path and .yaml stripped)
    $0 tests/kiali-operator-tests/operator-config.yaml        # Run operator test (path and .yaml stripped)
    $0 --debug true deployment-replicas                 # Run with debug mode (verbose + save files)
    $0 --test-suite operator --debug false test1        # Run operator test with debug mode disabled
    $0 --help                                           # Show this help

EXIT CODES:
    0    All tests passed
    1    One or more tests failed or error occurred
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                SHOW_HELP=true
                shift
                ;;
            --test-suite)
                if [[ $# -lt 2 ]]; then
                    log_error "--test-suite requires a value: server or operator"
                    exit 1
                fi
                case "$2" in
                    server|operator) TEST_SUITE="$2" ;;
                    *) log_error "--test-suite value must be 'server' or 'operator', got: $2"; exit 1 ;;
                esac
                shift 2
                ;;
            --debug)
                if [[ $# -lt 2 ]]; then
                    log_error "--debug requires a value: true or false"
                    exit 1
                fi
                case "$2" in
                    true) DEBUG_MODE=true ;;
                    false) DEBUG_MODE=false ;;
                    *) log_error "--debug value must be 'true' or 'false', got: $2"; exit 1 ;;
                esac
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                # Strip .yaml extension and parent directory path if provided for user convenience
                local test_name="$1"
                # First strip any parent directory path (e.g., tests/kiali-server-tests/test-name.yaml -> test-name.yaml
                # or kiali-server-tests/test-name.yaml -> test-name.yaml or kiali-operator-tests/test-name.yaml -> test-name.yaml)
                test_name="$(basename "${test_name}")"
                # Then strip .yaml extension if present (e.g., test-name.yaml -> test-name)
                if [[ "${test_name}" == *.yaml ]]; then
                    test_name="${test_name%.yaml}"
                fi
                SPECIFIC_TESTS+=("${test_name}")
                shift
                ;;
        esac
    done
}

# Cleanup function
cleanup() {
    if [[ "${DEBUG_MODE}" == true ]]; then
        echo ""
        log_info "═══════════════════════════════════════════════════════════════════"
        log_info " Debug Files Saved"
        log_info "═══════════════════════════════════════════════════════════════════"
        log_info "All test files preserved in: ${TEMP_DIR}"
        echo ""
        log_info "To explore saved Helm outputs:"
        log_info "  ls -la ${TEMP_DIR}/test_*_helm_output.yaml"
        echo ""
        log_info "To view a specific Helm output:"
        log_info "  cat ${TEMP_DIR}/test_<test-name>_helm_output.yaml"
        echo ""
        log_info "To view test comparison files:"
        log_info "  cat ${TEMP_DIR}/test_<test-name>_expected.yaml"
        log_info "  cat ${TEMP_DIR}/test_<test-name>_output.yaml"
        echo ""
        log_info "To test yq queries against saved output:"
        log_info "  yq eval 'your-query' ${TEMP_DIR}/test_<test-name>_helm_output.yaml"
        log_info "═══════════════════════════════════════════════════════════════════"
    else
        rm -rf "${TEMP_DIR}"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Set configuration based on test suite
set_test_suite_config() {
    case "${TEST_SUITE}" in
        server)
            TESTS_DIR="${SCRIPT_DIR}/kiali-server-tests"
            CHART_PATH="${SCRIPT_DIR}/../_output/charts/kiali-server"
            ;;
        operator)
            TESTS_DIR="${SCRIPT_DIR}/kiali-operator-tests"
            CHART_PATH="${SCRIPT_DIR}/../_output/charts/kiali-operator"
            ;;
        *)
            log_error "Invalid test suite: ${TEST_SUITE}"
            exit 1
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    if ! command -v helm &> /dev/null; then
        log_error "helm is required but not installed"
        exit 1
    fi

    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed"
        log_info "Install with: go install github.com/mikefarah/yq/v4@latest"
        exit 1
    fi

    if ! command -v make &> /dev/null; then
        log_error "make is required but not installed"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Build helm charts
build_helm_charts() {
    log_section "Building Helm Charts"

    # Change to parent directory where Makefile is located
    local original_dir=$(pwd)
    cd "${SCRIPT_DIR}/.."

    log_info "Cleaning previous builds..."
    make clean-charts

    log_info "Building helm charts..."
    make build-helm-charts

    # Return to original directory
    cd "${original_dir}"

    if [[ ! -d "${CHART_PATH}" ]]; then
        log_error "Chart directory ${CHART_PATH} not found after build"
        exit 1
    fi

    log_success "Helm charts built successfully"
}

# Parse test file using yq
parse_test_file() {
    local test_file="$1"
    local field="$2"

    yq eval ".${field}" "${test_file}"
}

# Run a single test
run_test() {
    local test_file="$1"
    local test_filename="$2"
    local test_name
    local description
    local helm_args
    local yq_query
    local expected_result
    local should_fail
    local expected_error_pattern

    TESTS_RUN=$((TESTS_RUN + 1))

    # Parse test configuration
    test_name=$(parse_test_file "${test_file}" "name")
    description=$(parse_test_file "${test_file}" "description")
    yq_query=$(parse_test_file "${test_file}" "yq_query")
    expected_result=$(parse_test_file "${test_file}" "expected_result")
    should_fail=$(parse_test_file "${test_file}" "should_fail")
    expected_error_pattern=$(parse_test_file "${test_file}" "expected_error_pattern" 2>/dev/null || echo "")

    # Parse helm_args array into bash array
    local helm_args=()
    local i=0
    while true; do
        local arg=$(yq eval ".helm_args[${i}]" "${test_file}" 2>/dev/null)
        if [[ "${arg}" == "null" ]]; then
            break
        fi
        helm_args+=("${arg}")
        i=$((i + 1))
    done

    if [[ "${DEBUG_MODE}" == true ]]; then
        log_info "Running Test ${TESTS_RUN}: ${test_name}"
        log_info "Description: ${description}"
        log_info "Helm Args: ${helm_args[*]}"
        log_info "YQ Query: ${yq_query}"

        # Show the full helm command for manual execution with properly quoted arguments
        local release_name=$(echo "test-${test_name}" | tr '_' '-')
        local quoted_helm_args=""
        for arg in "${helm_args[@]}"; do
            # Quote each argument that contains spaces or special characters
            if [[ "$arg" =~ [[:space:]] ]]; then
                quoted_helm_args+="\"$arg\" "
            else
                quoted_helm_args+="$arg "
            fi
        done
        log_info "Full Helm Command: helm template ${release_name} ${CHART_PATH} ${quoted_helm_args}"

        # Show how to render NOTES.txt separately (NOTES.txt cannot be shown with helm template)
        log_info "To see NOTES.txt output: helm install ${release_name} ${CHART_PATH} ${quoted_helm_args} --dry-run"
    fi

    local output_file="${TEMP_DIR}/test_${test_name}_output.yaml"
    local expected_file="${TEMP_DIR}/test_${test_name}_expected.yaml"
    local helm_output_file="${TEMP_DIR}/test_${test_name}_helm_output.yaml"

    # Build helm template command
    local helm_cmd="helm template test-${test_name} ${CHART_PATH}"

    # Write expected result to file for comparison (if not a failure test)
    if [[ "${should_fail}" != "true" ]]; then
        echo "${expected_result}" > "${expected_file}"
    fi

    # Run helm template command
    if [[ "${should_fail}" == "true" ]]; then
        # Test expects failure
        # Convert test name to valid helm release name (replace underscores with hyphens)
        local release_name=$(echo "test-${test_name}" | tr '_' '-')
        if helm template "${release_name}" "${CHART_PATH}" "${helm_args[@]}" &> "${helm_output_file}"; then
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_error "Test ${test_name}: Expected command to fail but it succeeded"
            else
                log_error "[${TESTS_RUN}] ${test_name} (${test_filename}): Expected command to fail but it succeeded"
            fi
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("${test_name}")
        else
            # Check if failure message contains expected error pattern
            if [[ -n "${expected_error_pattern}" ]]; then
                if grep -q "${expected_error_pattern}" "${helm_output_file}" 2>/dev/null; then
                    if [[ "${DEBUG_MODE}" == true ]]; then
                        log_success "Test ${test_name}: Command failed as expected with correct error message"
                    else
                        log_success "[${TESTS_RUN}] ${test_name} (${test_filename}): Command failed as expected with correct error message"
                    fi
                    TESTS_PASSED=$((TESTS_PASSED + 1))
                else
                    if [[ "${DEBUG_MODE}" == true ]]; then
                        log_error "Test ${test_name}: Command failed but with unexpected error"
                    else
                        log_error "[${TESTS_RUN}] ${test_name} (${test_filename}): Command failed but with unexpected error"
                    fi
                    log_info "Expected error pattern: ${expected_error_pattern}"
                    log_info "Actual output:"
                    cat "${helm_output_file}"
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                    FAILED_TESTS+=("${test_name}")
                fi
            else
                if [[ "${DEBUG_MODE}" == true ]]; then
                    log_success "Test ${test_name}: Command failed as expected"
                else
                    log_success "[${TESTS_RUN}] ${test_name} (${test_filename}): Command failed as expected"
                fi
                TESTS_PASSED=$((TESTS_PASSED + 1))
            fi
        fi
    else
        # Test expects success
        # Convert test name to valid helm release name (replace underscores with hyphens)
        local release_name=$(echo "test-${test_name}" | tr '_' '-')
        if ! helm template "${release_name}" "${CHART_PATH}" "${helm_args[@]}" > "${helm_output_file}" 2>&1; then
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_error "Test ${test_name}: Helm command failed unexpectedly"
            else
                log_error "[${TESTS_RUN}] ${test_name} (${test_filename}): Helm command failed unexpectedly"
            fi
            cat "${helm_output_file}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("${test_name}")
            return
        fi

        # Log helm output location for debugging if requested
        if [[ "${DEBUG_MODE}" == true ]]; then
            log_info "Full Helm output available at: ${helm_output_file}"
            log_info "  View with: cat ${helm_output_file}"
            log_info "  Query with: yq eval 'your-query' ${helm_output_file}"
        fi

        # Apply yq query to helm output
        if ! yq eval "${yq_query}" "${helm_output_file}" | yq eval 'select(. != null)' - > "${output_file}" 2>&1; then
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_error "Test ${test_name}: yq query failed"
            else
                log_error "[${TESTS_RUN}] ${test_name} (${test_filename}): yq query failed"
            fi
            log_info "Query: ${yq_query}"
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_info "Helm output excerpt (first 50 lines):"
                head -50 "${helm_output_file}"
                log_info "--- End excerpt ---"
            fi
            cat "${output_file}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("${test_name}")
            return
        fi

        # Compare output with expected result
        if diff -u "${expected_file}" "${output_file}" > /dev/null; then
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_success "Test ${test_name}: Output matches expected result"
            else
                log_success "[${TESTS_RUN}] ${test_name} (${test_filename}): Output matches expected result"
            fi
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_error "Test ${test_name}: Output does not match expected result"
            else
                log_error "[${TESTS_RUN}] ${test_name} (${test_filename}): Output does not match expected result"
            fi
            log_info "Expected:"
            cat "${expected_file}"
            log_info "Actual:"
            cat "${output_file}"
            log_info "Diff:"
            diff -u "${expected_file}" "${output_file}" || true
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("${test_name}")
        fi
    fi
}

# Check if a test should be included based on specific test file names
should_include_test() {
    local test_file="$1"
    local test_filename
    test_filename=$(basename "${test_file}" .yaml)

    # If no specific tests requested, include all
    if [[ ${#SPECIFIC_TESTS[@]} -eq 0 ]]; then
        return 0
    fi

    # Check if test filename is in the list of requested tests
    for requested_test in "${SPECIFIC_TESTS[@]}"; do
        if [[ "${test_filename}" == "${requested_test}" ]]; then
            return 0
        fi
    done

    return 1
}

# Discover and run tests
run_all_tests() {
    if [[ ${#SPECIFIC_TESTS[@]} -eq 0 ]]; then
        log_section "Discovering and Running All Tests"
    else
        log_section "Running Specific Tests: ${SPECIFIC_TESTS[*]}"
    fi

    if [[ ! -d "${TESTS_DIR}" ]]; then
        log_error "Tests directory ${TESTS_DIR} not found"
        exit 1
    fi

    # Find all test files
    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "${TESTS_DIR}" -name "*.yaml" -not -name "README*" -print0 | sort -z)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_error "No test files found in ${TESTS_DIR}"
        exit 1
    fi

    log_info "Found ${#test_files[@]} test files"

    # Track which specific tests were found
    local found_tests=()
    local not_found_tests=()

    # If specific tests were requested, validate they exist
    if [[ ${#SPECIFIC_TESTS[@]} -gt 0 ]]; then
        for requested_test in "${SPECIFIC_TESTS[@]}"; do
            local found=false
            for test_file in "${test_files[@]}"; do
                # Extract filename without extension
                local test_filename
                test_filename=$(basename "${test_file}" .yaml)
                if [[ "${test_filename}" == "${requested_test}" ]]; then
                    found_tests+=("${requested_test}")
                    found=true
                    break
                fi
            done
            if [[ "${found}" == false ]]; then
                not_found_tests+=("${requested_test}")
            fi
        done

        # Report any tests that weren't found
        if [[ ${#not_found_tests[@]} -gt 0 ]]; then
            log_warning "The following requested tests were not found:"
            for test in "${not_found_tests[@]}"; do
                echo "  - ${test}"
            done
        fi

        if [[ ${#found_tests[@]} -eq 0 ]]; then
            log_error "None of the requested tests were found"
            exit 1
        fi
    fi

    # Run each test
    local tests_to_run=0
    for test_file in "${test_files[@]}"; do
        # Check if this test should be included
        if should_include_test "${test_file}"; then
            if [[ "${DEBUG_MODE}" == true ]]; then
                log_info "Processing test file: $(basename "${test_file}")"
            fi
            run_test "${test_file}" "$(basename "${test_file}")"
            tests_to_run=$((tests_to_run + 1))
        fi
    done

    if [[ ${tests_to_run} -eq 0 ]]; then
        log_error "No matching tests found to run"
        exit 1
    fi
}

# Print test summary
print_summary() {
    log_section "Test Summary"

    echo "Tests Run: ${TESTS_RUN}"
    echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo
        log_error "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - ${test}"
        done
        echo
        return 1
    else
        echo
        log_success "All tests passed! ✅"
        echo
        log_info "The kiali-${TEST_SUITE} Helm chart is working correctly."
        echo
        return 0
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Show help if requested
    if [[ "${SHOW_HELP}" == true ]]; then
        show_help
        exit 0
    fi

    log_section "Kiali Helm Chart Test Runner (${TEST_SUITE} tests)"

    set_test_suite_config
    check_prerequisites
    build_helm_charts
    init_temp_dir
    run_all_tests
    print_summary
}

# Run main function
main "$@"
