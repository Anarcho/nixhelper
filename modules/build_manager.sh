#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vm.sh"

# Build types
declare -A BUILD_TYPES=(
    ["nixos"]="NixOS system configuration"
    ["home-manager"]="Home Manager user configuration"
    ["all"]="Both NixOS and Home Manager configurations"
)

build_config() {
    local host_name="$1"
    local build_type="${2:-all}"
    local user_name="${3:-$USER}"
    local dry_run="${4:-false}"

    # Validate build type
    if [[ ! "${BUILD_TYPES[$build_type]+isset}" ]]; then
        error "Invalid build type: ${build_type}"
        info "Available types: ${!BUILD_TYPES[*]}"
        return 1
    fi

    # Validate configuration before building
    if ! validate_config "$host_name" "$build_type" "$user_name"; then
        error "Configuration validation failed"
        return 1
    fi

    # Determine if building remotely or locally
    local is_remote=false
    if [[ "${VM_HOST}" != "localhost" ]]; then
        is_remote=true
        if ! check_vm_connectivity; then
            return 1
        fi
    fi

    # Build NixOS configuration
    build_nixos() {
        local build_cmd="sudo nixos-rebuild"
        [[ "$dry_run" == "true" ]] && build_cmd+=" dry-run" || build_cmd+=" switch"
        build_cmd+=" --flake .#${host_name}"

        log "INFO" "Building NixOS configuration for ${host_name}"
        if $is_remote; then
            ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "cd ${VM_PATH} && ${build_cmd}"
        else
            (cd "${REPO_PATH}" && ${build_cmd})
        fi
    }

    # Build home-manager configuration
    build_home_manager() {
        local build_cmd="home-manager"
        [[ "$dry_run" == "true" ]] && build_cmd+=" build" || build_cmd+=" switch"
        build_cmd+=" --flake .#${user_name}@${host_name}"

        log "INFO" "Building home-manager configuration for user ${user_name}"
        if $is_remote; then
            # Check if home-manager is installed on remote system
            if ! ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "command -v home-manager" &>/dev/null; then
                if confirm_action "home-manager not found. Install it?"; then
                    install_home_manager
                else
                    return 1
                fi
            fi
            ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "cd ${VM_PATH} && ${build_cmd}"
        else
            if ! command -v home-manager &>/dev/null; then
                if confirm_action "home-manager not found. Install it?"; then
                    install_home_manager
                else
                    return 1
                fi
            fi
            (cd "${REPO_PATH}" && ${build_cmd})
        fi
    }

    # Install home-manager if needed
    install_home_manager() {
        local install_cmd="nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager && \
                          nix-channel --update && \
                          nix-shell '<home-manager>' -A install"
        if $is_remote; then
            ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "${install_cmd}"
        else
            eval "${install_cmd}"
        fi
    }

    # Perform the build based on type
    case "${build_type}" in
        "nixos")
            build_nixos
            ;;
        "home-manager")
            build_home_manager
            ;;
        "all")
            build_nixos && build_home_manager
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Build completed successfully"
        return 0
    else
        error "Build failed"
        if confirm_action "Would you like to see the build logs?"; then
            show_logs 100
        fi
        return 1
    fi
}

validate_config() {
    local host_name="$1"
    local build_type="$2"
    local user_name="$3"
    local target_path="${REPO_PATH}/hosts/${host_name}"

    log "INFO" "Validating configuration for ${host_name}"

    # Check if host configuration exists
    if [[ ! -d "${target_path}" ]]; then
        error "Host configuration not found: ${target_path}"
        return 1
    fi

    # Check hardware configuration
    if [[ ! -f "${target_path}/hardware-configuration.nix" ]]; then
        warning "No hardware configuration found."
        if confirm_action "Would you like to generate hardware configuration?"; then
            generate_hardware_config "${host_name}" || return 1
        fi
    fi

    # Validate flake.nix
    if ! (cd "${REPO_PATH}" && nix flake check); then
        error "Flake validation failed"
        return 1
    fi

    # Check specific configurations based on build type
    case "${build_type}" in
        "nixos"|"all")
            local nixos_cmd="nixos-rebuild dry-run --flake .#${host_name}"
            if ! (cd "${REPO_PATH}" && ${nixos_cmd}); then
                error "NixOS configuration validation failed"
                return 1
            fi
            ;;
        "home-manager"|"all")
            if ! grep -q "${user_name}@${host_name}" "${REPO_PATH}/flake.nix"; then
                error "No home-manager configuration found for ${user_name}@${host_name}"
                return 1
            fi
            ;;
    esac

    log "SUCCESS" "Configuration validation completed"
    return 0
}

rollback_build() {
    local host_name="$1"
    local build_type="${2:-all}"
    local user_name="${3:-$USER}"

    case "${build_type}" in
        "nixos"|"all")
            log "INFO" "Rolling back NixOS configuration"
            sudo nixos-rebuild switch --rollback
            ;;
        "home-manager"|"all")
            log "INFO" "Rolling back home-manager configuration"
            home-manager generations rollback
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Rollback completed"
    else
        error "Rollback failed"
        return 1
    fi
}

# Export functions
export BUILD_TYPES
export -f build_config validate_config rollback_build
