#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Available development environments
declare -A DEV_ENVIRONMENTS=(
    ["rust"]="Rust development environment"
    ["python"]="Python development environment"
    ["node"]="Node.js development environment"
    ["go"]="Go development environment"
    ["zig"]="Zig development environment"
    ["nix"]="Nix development environment"
    ["cpp"]="C/C++ development environment"
)

create_dev_environment() {
    local env_type="$1"
    local env_path="${REPO_PATH}/modules/development/${env_type}"

    if [[ ! "${DEV_ENVIRONMENTS[$env_type]+isset}" ]]; then
        error "Invalid development environment: ${env_type}"
        info "Available environments: ${!DEV_ENVIRONMENTS[*]}"
        return 1
    fi

    log "INFO" "Creating ${env_type} development environment"

    # Create module structure
    mkdir -p "${env_path}"/{config,shell}

    # Create default.nix for the development environment
    cat > "${env_path}/default.nix" <<EOF
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.development.${env_type};
in {
    options.modules.development.${env_type} = {
        enable = mkEnableOption "Enable ${env_type} development environment";

        packages = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional ${env_type} packages to install";
        };

        shellAliases = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Shell aliases for ${env_type} development";
        };

        environmentVariables = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Environment variables for ${env_type} development";
        };
    };

    config = mkIf cfg.enable {
        home.packages = with pkgs; [
            $(get_default_packages "${env_type}")
        ] ++ cfg.packages;

        programs.bash.shellAliases = cfg.shellAliases;
        programs.zsh.shellAliases = cfg.shellAliases;

        home.sessionVariables = cfg.environmentVariables;
    };
}
EOF

    # Create shell.nix for development shell
    cat > "${env_path}/shell/default.nix" <<EOF
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
    buildInputs = with pkgs; [
        $(get_default_packages "${env_type}")
    ];

    shellHook = ''
        echo "${env_type} development environment activated"
        $(get_shell_hook "${env_type}")
    '';
}
EOF

    success "Created ${env_type} development environment"
}

get_default_packages() {
    local env_type="$1"
    case "${env_type}" in
        "rust") echo "rustc rustfmt cargo clippy rust-analyzer" ;;
        "python") echo "python3 poetry black mypy pylint python3Packages.pip" ;;
        "node") echo "nodejs yarn nodePackages.npm nodePackages.typescript" ;;
        "go") echo "go gopls delve golangci-lint" ;;
        "zig") echo "zig zls" ;;
        "nix") echo "nixfmt nil statix" ;;
        "cpp") echo "gcc gdb cmake clang-tools" ;;
        *) error "Unknown environment type: ${env_type}"; return 1 ;;
    esac
}

get_shell_hook() {
    local env_type="$1"
    case "${env_type}" in
        "rust") echo 'export RUST_SRC_PATH="$(rustc --print sysroot)/lib/rustlib/src/rust/library"' ;;
        "python") echo 'export PYTHONPATH="$PWD"; layout_python' ;;
        "node") echo 'export PATH="$PWD/node_modules/.bin:$PATH"' ;;
        "go") echo 'export GOPATH="$PWD/.go"; export PATH="$GOPATH/bin:$PATH"' ;;
        *) echo "# No specific shell hook for ${env_type}" ;;
    esac
}

activate_dev_environment() {
    local env_type="$1"
    local shell_dir="${REPO_PATH}/modules/development/${env_type}/shell"

    if [[ ! -d "$shell_dir" ]]; then
        error "Development environment not found: ${env_type}"
        return 1
    fi

    log "INFO" "Activating ${env_type} development environment"
    if ! nix-shell "${shell_dir}/default.nix"; then
        error "Failed to activate development environment"
        return 1
    fi
}

list_dev_environments() {
    log "INFO" "Available development environments:"
    echo
    for env in "${!DEV_ENVIRONMENTS[@]}"; do
        local status="Not installed"
        if [[ -d "${REPO_PATH}/modules/development/${env}" ]]; then
            status="Installed"
        fi
        printf "%-15s %-40s [%s]\n" "${env}" "${DEV_ENVIRONMENTS[$env]}" "${status}"
    done
}

remove_dev_environment() {
    local env_type="$1"
    local env_path="${REPO_PATH}/modules/development/${env_type}"

    if [[ ! -d "$env_path" ]]; then
        error "Development environment not found: ${env_type}"
        return 1
    fi

    if ! confirm_action "Remove ${env_type} development environment?"; then
        return 0
    fi

    if rm -rf "$env_path"; then
        success "Removed ${env_type} development environment"
    else
        error "Failed to remove environment"
        return 1
    fi
}

update_dev_environment() {
    local env_type="$1"
    local env_path="${REPO_PATH}/modules/development/${env_type}"

    if [[ ! -d "$env_path" ]]; then
        error "Development environment not found: ${env_type}"
        return 1
    fi

    log "INFO" "Updating ${env_type} development environment"

    # Recreate environment while preserving customizations
    if [[ -f "${env_path}/custom.nix" ]]; then
        cp "${env_path}/custom.nix" "${env_path}/custom.nix.bak"
    fi

    create_dev_environment "${env_type}"

    if [[ -f "${env_path}/custom.nix.bak" ]]; then
        mv "${env_path}/custom.nix.bak" "${env_path}/custom.nix"
    fi

    success "Updated ${env_type} development environment"
}

# Export functions
export DEV_ENVIRONMENTS
export -f create_dev_environment activate_dev_environment list_dev_environments
export -f remove_dev_environment update_dev_environment
