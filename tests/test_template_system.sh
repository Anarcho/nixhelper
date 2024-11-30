#!/usr/bin/env bash

# Template system test script
TEST_DIR="/tmp/nixhelp-template-tests"
LOG_FILE="${TEST_DIR}/test.log"
FAILED_TESTS=0
TOTAL_TESTS=0

# Test helper functions
setup() {
    echo "Setting up test environment..."
    rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DIR}"
    echo "Test started at $(date)" > "${LOG_FILE}"
}

log_test() {
    local name="$1"
    local result="$2"
    local details="$3"
    echo "[$result] $name" | tee -a "${LOG_FILE}"
    [[ -n "$details" ]] && echo "$details" >> "${LOG_FILE}"
    echo "------------------------------------------" >> "${LOG_FILE}"
}

run_test() {
    local name="$1"
    local cmd="$2"
    local expected_status="${3:-0}"
    
    ((TOTAL_TESTS++))
    echo "Running test: $name"
    
    local output
    output=$(eval "$cmd" 2>&1)
    local status=$?
    
    if [[ $status -eq $expected_status ]]; then
        log_test "$name" "PASS" "$output"
        return 0
    else
        log_test "$name" "FAIL" "Expected status: $expected_status, got: $status\nOutput: $output"
        ((FAILED_TESTS++))
        return 1
    fi
}

cleanup() {
    echo "Cleaning up..."
    echo "Test completed at $(date)" >> "${LOG_FILE}"
    echo "Total tests: ${TOTAL_TESTS}"
    echo "Failed tests: ${FAILED_TESTS}"
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "All tests passed!"
    else
        echo "Some tests failed. Check ${LOG_FILE} for details."
    fi
}

# Main test groups
test_installation() {
    echo "Testing template installation..."
    
    run_test "Template Installation" \
        "nixhelp template install"

    run_test "Template Listing" \
        "nixhelp template list"
}

test_template_application() {
    echo "Testing template application..."
    
    local test_targets=(
        "configs editor/vim ${TEST_DIR}/vim"
        "configs terminal/kitty ${TEST_DIR}/kitty"
        "configs wm/sway ${TEST_DIR}/sway"
        "configs shell/zsh ${TEST_DIR}/zsh"
    )
    
    for target in "${test_targets[@]}"; do
        read -r category name path <<< "$target"
        run_test "Apply ${name} template" \
            "nixhelp template apply ${category} ${name} ${path}"
        
        run_test "Verify ${name} files" \
            "[[ -f ${path}/default.nix ]]"
    done
}

test_module_creation() {
    echo "Testing module creation with templates..."
    
    local test_dir="${TEST_DIR}/modules"
    mkdir -p "$test_dir"
    
    run_test "Create NixOS module" \
        "nixhelp template apply base/module/nixos ${test_dir}/test-nixos"
    
    run_test "Create Home Manager module" \
        "nixhelp template apply base/module/home-manager ${test_dir}/test-home-manager"
}

test_custom_templates() {
    echo "Testing custom template functionality..."
    
    # Create a test custom template
    local custom_dir="${TEST_DIR}/custom-template"
    mkdir -p "${custom_dir}"
    
    cat > "${custom_dir}/template.json" <<EOF
{
    "schemaVersion": "1.0",
    "name": "test-template",
    "version": "1.0.0",
    "description": "Test custom template",
    "category": "custom",
    "type": "config",
    "dependencies": [],
    "variables": {},
    "compatibility": ["nixos"]
}
EOF
    
    cat > "${custom_dir}/default.nix" <<EOF
{ config, lib, pkgs, ... }: {}
EOF
    
    run_test "Add custom template" \
        "nixhelp template add custom test-template ${custom_dir}"
    
    run_test "List custom templates" \
        "nixhelp template list custom"
    
    run_test "Apply custom template" \
        "nixhelp template apply custom test-template ${TEST_DIR}/custom-test"
}

test_error_handling() {
    echo "Testing error handling..."
    
    run_test "Invalid category" \
        "nixhelp template apply invalid-category test ${TEST_DIR}/error" 1
    
    run_test "Non-existent template" \
        "nixhelp template apply configs non-existent ${TEST_DIR}/error" 1
    
    run_test "Invalid target directory" \
        "nixhelp template apply configs editor/vim /invalid/path" 1
}

# Main test execution
main() {
    setup
    
    test_installation
    test_template_application
    test_module_creation
    test_custom_templates
    test_error_handling
    
    cleanup
    
    return $FAILED_TESTS
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi