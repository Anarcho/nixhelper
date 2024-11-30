#!/usr/bin/env bash

# Test file for module_manager.sh functionality
TEST_DIR="/tmp/nixhelp-module-tests"
LOG_FILE="${TEST_DIR}/test.log"
FAILED_TESTS=0
TOTAL_TESTS=0

source "$(dirname "${BASH_SOURCE[0]}")/module_manager.sh"

# Test helper functions
setup() {
    echo "Setting up test environment..."
    rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DIR}"
    export REPO_PATH="${TEST_DIR}/repo"
    mkdir -p "${REPO_PATH}"
    echo "Test started at $(date)" > "${LOG_FILE}"

    # Create basic flake.nix for testing
    cat > "${REPO_PATH}/flake.nix" <<EOF
{
  description = "Test NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules = {
      # Modules will be added here
    };
  };
}
EOF
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
    rm -rf "${TEST_DIR}"
}

# Module creation tests
test_module_creation() {
    echo "Testing module creation..."

    # Test basic NixOS module creation
    run_test "Create NixOS module" \
        "create_module core test-module nixos"

    # Verify module structure
    run_test "Verify module structure" \
        "[[ -d ${REPO_PATH}/modules/core/test-module ]] && \
         [[ -f ${REPO_PATH}/modules/core/test-module/default.nix ]] && \
         [[ -d ${REPO_PATH}/modules/core/test-module/config ]]"

    # Test home-manager module creation
    run_test "Create home-manager module" \
        "create_module apps test-home-module home-manager"

    # Test invalid category
    run_test "Create module with invalid category" \
        "create_module invalid test-module" 1

    # Test template-based module creation
    run_test "Create template-based module" \
        "create_module editor vim nixos"

    # Test development environment module
    run_test "Create development module" \
        "create_module development rust nixos"
}

# Module enabling/disabling tests
test_module_management() {
    echo "Testing module enabling/disabling..."

    # Setup test host
    mkdir -p "${REPO_PATH}/hosts/test-host"
    cat > "${REPO_PATH}/hosts/test-host/default.nix" <<EOF
{
  imports = [];
}
EOF

    # Setup test user
    mkdir -p "${REPO_PATH}/home/test-user"
    cat > "${REPO_PATH}/home/test-user/default.nix" <<EOF
{
  imports = [];
}
EOF

    # Test enabling NixOS module
    run_test "Enable NixOS module" \
        "enable_module core test-module test-host"

    # Verify module is enabled
    run_test "Verify module is enabled" \
        "grep -q 'modules.core.test-module.enable = true' ${REPO_PATH}/hosts/test-host/default.nix"

    # Test enabling home-manager module
    run_test "Enable home-manager module" \
        "enable_module apps test-home-module test-user@test-host"

    # Test disabling NixOS module
    run_test "Disable NixOS module" \
        "disable_module core test-module test-host"

    # Verify module is disabled
    run_test "Verify module is disabled" \
        "! grep -q 'modules.core.test-module.enable' ${REPO_PATH}/hosts/test-host/default.nix"
}

# Module listing tests
test_module_listing() {
    echo "Testing module listing..."

    # Test basic listing
    run_test "List all modules" \
        "list_modules"

    # Test category-specific listing
    run_test "List core modules" \
        "list_modules core"

    # Test detailed listing
    run_test "List modules with details" \
        "list_modules core true"
}

# Module checking tests
test_module_checking() {
    echo "Testing module checking..."

    # Test valid module check
    run_test "Check valid module" \
        "check_module core test-module"

    # Create invalid module for testing
    mkdir -p "${REPO_PATH}/modules/core/invalid-module"
    echo "invalid nix" > "${REPO_PATH}/modules/core/invalid-module/default.nix"

    # Test invalid module check
    run_test "Check invalid module" \
        "check_module core invalid-module" 1

    # Test non-existent module check
    run_test "Check non-existent module" \
        "check_module core non-existent" 1
}

# Template integration tests
test_template_integration() {
    echo "Testing template integration..."

    # Test template-based module creation
    run_test "Create module from template" \
        "create_module editor neovim nixos"

    # Verify template metadata
    run_test "Verify template metadata" \
        "[[ -f ${REPO_PATH}/modules/editor/neovim/template.json ]]"

    # Test template activation
    if [[ -f "${REPO_PATH}/modules/editor/neovim/activate.sh" ]]; then
        run_test "Run template activation" \
            "enable_module editor neovim test-host"
    fi
}

# Main test execution
main() {
    setup

    test_module_creation
    test_module_management
    test_module_listing
    test_module_checking
    test_template_integration

    cleanup

    return $FAILED_TESTS
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi