#!/usr/bin/env bash

# Define paths
TEST_DIR="$HOME/repos/testing"
NIXHELP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nixhelp"

# Cleanup Function
cleanup() {
    echo "Cleaning up test environment..."
    # Remove test directory
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        echo "Removed test directory: $TEST_DIR"
    else
        echo "Test directory does not exist, skipping cleanup."
    fi

    # Remove nixhelp configuration directory
    if [[ -d "$NIXHELP_CONFIG_DIR" ]]; then
        rm -rf "$NIXHELP_CONFIG_DIR"
        echo "Removed nixhelp configuration directory: $NIXHELP_CONFIG_DIR"
    else
        echo "Nixhelp configuration directory does not exist, skipping cleanup."
    fi
}

# Run Initialization Function
run_initialization() {
    echo "Starting initialization test..."
    # Call nixhelp init and wait for user input at prompts
    nixhelp init "$TEST_DIR"
}

# Validate Output
validate_output() {
    echo "Validating output..."
    # Check critical files
    if [[ -f "$TEST_DIR/flake.nix" ]]; then
        echo "flake.nix created successfully."
    else
        echo "ERROR: flake.nix was not created."
    fi

    if [[ -f "$TEST_DIR/hosts/common/default.nix" ]]; then
        echo "hosts/common/default.nix created successfully."
    else
        echo "ERROR: hosts/common/default.nix was not created."
    fi
}

# Display Results
display_results() {
    echo "Test completed. Directory structure:"
    if command -v tree &> /dev/null; then
        tree "$TEST_DIR"
    else
        echo "'tree' command not found. Using 'ls -R' instead."
        ls -R "$TEST_DIR"
    fi
}

# Main Function
main() {
    cleanup
    run_initialization
}

# Run Main
main
