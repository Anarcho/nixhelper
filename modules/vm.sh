#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"

check_vm_connectivity() {
    if [[ "${VM_HOST}" == "localhost" ]]; then
        debug "Using localhost, no VM connectivity check needed"
        return 0
    fi

    log "INFO" "Checking VM connectivity for ${VM_HOST}"

    if ! check_internet; then
        error "No internet connection available"
        return 1
    fi

    if ssh -q -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" exit 2>/dev/null; then
        success "VM connection successful"
        return 0
    else
        error "Cannot connect to VM at ${VM_HOST}"
        if confirm_action "Would you like to configure SSH for this VM?"; then
            setup_ssh_keys "${VM_HOST}" "${VM_USER}" "${VM_PORT}"
        fi
        return 1
    fi
}

sync_to_vm() {
    local host_name="$1"
    local source_path="${REPO_PATH}"
    local extra_excludes=("${@:2}")

    log "INFO" "Syncing files to VM ${VM_HOST} for host ${host_name}"

    # Check VM connectivity first
    if ! check_vm_connectivity; then
        return 1
    fi

    # Create default excludes
    local exclude_opts=(
        --exclude '.git/'
        --exclude 'result'
        --exclude '.direnv'
        --exclude '*.swp'
        --exclude '.DS_Store'
        --exclude 'tmp/'
    )

    # Add any extra excludes
    for exclude in "${extra_excludes[@]}"; do
        exclude_opts+=("--exclude=${exclude}")
    done

    # Sync files
    if rsync -avz --delete "${exclude_opts[@]}" \
        -e "ssh -p ${VM_PORT}" \
        "${source_path}/" \
        "${VM_USER}@${VM_HOST}:${VM_PATH}/"; then
        success "Files synced to VM successfully"
    else
        error "Failed to sync files to VM"
        return 1
    fi
}

deploy_to_vm() {
    local host_name="$1"
    local deploy_type="${2:-all}"
    local user_name="${3:-$USER}"

    log "INFO" "Deploying ${host_name} configuration to VM ${VM_HOST}"

    # Create backup before deployment
    create_backup

    # Sync files to VM
    if ! sync_to_vm "${host_name}"; then
        return 1
    fi

    # Build configuration on VM
    log "INFO" "Building configuration on VM"
    local build_cmd="cd ${VM_PATH} && "

    case "${deploy_type}" in
        "nixos")
            build_cmd+="sudo nixos-rebuild switch --flake .#${host_name}"
            ;;
        "home-manager")
            build_cmd+="home-manager switch --flake .#${user_name}@${host_name}"
            ;;
        "all")
            build_cmd+="sudo nixos-rebuild switch --flake .#${host_name} && "
            build_cmd+="home-manager switch --flake .#${user_name}@${host_name}"
            ;;
        *)
            error "Invalid deploy type: ${deploy_type}"
            return 1
            ;;
    esac

    if ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "${build_cmd}"; then
        success "Deployment completed successfully"
    else
        error "Deployment failed"
        if confirm_action "Would you like to rollback?"; then
            rollback_deployment "${deploy_type}"
        fi
        return 1
    fi
}

rollback_deployment() {
    local deploy_type="$1"

    log "INFO" "Rolling back VM deployment"

    local rollback_cmd="cd ${VM_PATH} && "
    case "${deploy_type}" in
        "nixos"|"all")
            rollback_cmd+="sudo nixos-rebuild switch --rollback"
            ;;
        "home-manager")
            rollback_cmd+="home-manager generations rollback"
            ;;
    esac

    if ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "${rollback_cmd}"; then
        success "Rollback completed successfully"
    else
        error "Rollback failed"
        return 1
    fi
}

setup_vm() {
    local host_name="$1"

    log "INFO" "Setting up VM configuration for ${host_name}"

    # Configure VM settings
    echo "Enter VM configuration details:"
    read -p "VM Username (current: ${VM_USER}): " new_user
    read -p "VM Hostname (current: ${VM_HOST}): " new_host
    read -p "VM Port (current: ${VM_PORT}): " new_port
    read -p "VM Path (current: ${VM_PATH}): " new_path

    # Update only if new values provided
    [ -n "$new_user" ] && VM_USER="$new_user"
    [ -n "$new_host" ] && VM_HOST="$new_host"
    [ -n "$new_port" ] && VM_PORT="$new_port"
    [ -n "$new_path" ] && VM_PATH="$new_path"

    # Save configuration
    set_config "VM_USER" "${VM_USER}"
    set_config "VM_HOST" "${VM_HOST}"
    set_config "VM_PORT" "${VM_PORT}"
    set_config "VM_PATH" "${VM_PATH}"

    # Setup SSH keys if needed
    if ! check_vm_connectivity && confirm_action "Would you like to setup SSH keys?"; then
        setup_ssh_keys "${VM_HOST}" "${VM_USER}" "${VM_PORT}"
    fi

    success "VM configuration updated successfully"
}

get_vm_status() {
    local host_name="$1"

    log "INFO" "Checking VM status for ${host_name}"

    if ! check_vm_connectivity; then
        return 1
    fi

    # Check NixOS version
    echo "NixOS Version:"
    ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "nixos-version"

    # Check system status
    echo -e "\nSystem Status:"
    ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "uptime"

    # Check disk usage
    echo -e "\nDisk Usage:"
    ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "df -h /"

    # Check memory usage
    echo -e "\nMemory Usage:"
    ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "free -h"

    # Check current generations
    echo -e "\nNixOS Generations:"
    ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" "nix-env --list-generations --profile /nix/var/nix/profiles/system"
}

# Export functions
export -f check_vm_connectivity sync_to_vm deploy_to_vm
export -f rollback_deployment setup_vm get_vm_status
