#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/ssh.sh"

check_vm_connectivity() {
    local host_name="$1"
    
    if [[ "${VM_HOST}" == "localhost" ]]; then
        debug "Using localhost, no VM connectivity check needed"
        return 0
    fi

    # Get host-specific config if available
    local target_host="${VM_HOST}"
    local target_user="${VM_USER}"
    local target_port="${VM_PORT}"
    local target_ip=""
    
    if [[ -n "$host_name" ]]; then
        target_ip=$(get_vm_config "$host_name" "IP")
        target_user=$(get_vm_config "$host_name" "USER")
        target_port=$(get_vm_config "$host_name" "PORT")
        [[ -n "$target_ip" ]] && target_host="$target_ip"
    fi

    log "INFO" "Checking VM connectivity for ${target_host}"

    if ! check_internet; then
        error "No internet connection available"
        return 1
    fi

    if ssh -q -p "${target_port}" "${target_user}@${target_host}" exit 2>/dev/null; then
        success "VM connection successful"
        return 0
    else
        error "Cannot connect to VM at ${target_host}"
        if confirm_action "Would you like to configure SSH for this VM?"; then
            setup_ssh_keys "${host_name}" "${target_user}" "${target_port}" "${target_ip}"
        fi
        return 1
    fi
}

sync_to_vm() {
    local host_name="$1"
    local source_path="${REPO_PATH}"
    local extra_excludes=("${@:2}")

    # Get host-specific config
    local target_host="${VM_HOST}"
    local target_user="${VM_USER}"
    local target_port="${VM_PORT}"
    local target_path="${VM_PATH}"
    local target_ip=""

    if [[ -n "$host_name" ]]; then
        target_ip=$(get_vm_config "$host_name" "IP")
        target_user=$(get_vm_config "$host_name" "USER")
        target_port=$(get_vm_config "$host_name" "PORT")
        target_path=$(get_vm_config "$host_name" "PATH")
        [[ -n "$target_ip" ]] && target_host="$target_ip"
    fi

    log "INFO" "Syncing files to VM ${target_host} for host ${host_name}"

    # Check VM connectivity first
    if ! check_vm_connectivity "$host_name"; then
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
        -e "ssh -p ${target_port}" \
        "${source_path}/" \
        "${target_user}@${target_host}:${target_path}/"; then
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

    # Get host-specific config
    local target_host="${VM_HOST}"
    local target_user="${VM_USER}"
    local target_port="${VM_PORT}"
    local target_path="${VM_PATH}"
    local target_ip=""

    if [[ -n "$host_name" ]]; then
        target_ip=$(get_vm_config "$host_name" "IP")
        target_user=$(get_vm_config "$host_name" "USER")
        target_port=$(get_vm_config "$host_name" "PORT")
        target_path=$(get_vm_config "$host_name" "PATH")
        [[ -n "$target_ip" ]] && target_host="$target_ip"
    fi

    log "INFO" "Deploying ${host_name} configuration to VM ${target_host}"

    # Create backup before deployment
    create_backup

    # Sync files to VM
    if ! sync_to_vm "${host_name}"; then
        return 1
    fi

    # Build configuration on VM
    log "INFO" "Building configuration on VM"
    local build_cmd="cd ${target_path} && "

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

    if ssh -p "${target_port}" "${target_user}@${target_host}" "${build_cmd}"; then
        success "Deployment completed successfully"
    else
        error "Deployment failed"
        if confirm_action "Would you like to rollback?"; then
            rollback_deployment "${host_name}" "${deploy_type}"
        fi
        return 1
    fi
}

rollback_deployment() {
    local host_name="$1"
    local deploy_type="$2"

    # Get host-specific config
    local target_host="${VM_HOST}"
    local target_user="${VM_USER}"
    local target_port="${VM_PORT}"
    local target_path="${VM_PATH}"
    local target_ip=""

    if [[ -n "$host_name" ]]; then
        target_ip=$(get_vm_config "$host_name" "IP")
        target_user=$(get_vm_config "$host_name" "USER")
        target_port=$(get_vm_config "$host_name" "PORT")
        target_path=$(get_vm_config "$host_name" "PATH")
        [[ -n "$target_ip" ]] && target_host="$target_ip"
    fi

    log "INFO" "Rolling back VM deployment"

    local rollback_cmd="cd ${target_path} && "
    case "${deploy_type}" in
        "nixos"|"all")
            rollback_cmd+="sudo nixos-rebuild switch --rollback"
            ;;
        "home-manager")
            rollback_cmd+="home-manager generations rollback"
            ;;
    esac

    if ssh -p "${target_port}" "${target_user}@${target_host}" "${rollback_cmd}"; then
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
    read -p "VM IP Address: " ip_address
    read -p "VM Port (current: ${VM_PORT}): " new_port
    read -p "VM Path (current: ${VM_PATH}): " new_path

    # Update only if new values provided
    [ -n "$new_user" ] && VM_USER="$new_user"
    [ -n "$new_host" ] && VM_HOST="$new_host"
    [ -n "$new_port" ] && VM_PORT="$new_port"
    [ -n "$new_path" ] && VM_PATH="$new_path"

    # Save host-specific configuration if hostname provided
    if [[ -n "$host_name" ]]; then
        set_vm_config "$host_name" "USER" "${new_user:-${VM_USER}}"
        set_vm_config "$host_name" "HOST" "${new_host:-${VM_HOST}}"
        set_vm_config "$host_name" "IP" "${ip_address}"
        set_vm_config "$host_name" "PORT" "${new_port:-${VM_PORT}}"
        set_vm_config "$host_name" "PATH" "${new_path:-${VM_PATH}}"
    fi

    # Save global configuration
    set_config "VM_USER" "${VM_USER}"
    set_config "VM_HOST" "${VM_HOST}"
    set_config "VM_PORT" "${VM_PORT}"
    set_config "VM_PATH" "${VM_PATH}"

    # Setup SSH keys if needed
    if ! check_vm_connectivity "$host_name" && confirm_action "Would you like to setup SSH keys?"; then
        setup_ssh_keys "${host_name}" "${VM_USER}" "${VM_PORT}" "${ip_address}"
    fi

    success "VM configuration updated successfully"
    
    if [[ -n "$host_name" ]]; then
        show_vm_config "$host_name"
    fi
}

get_vm_status() {
    local host_name="$1"

    # Get host-specific config
    local target_host="${VM_HOST}"
    local target_user="${VM_USER}"
    local target_port="${VM_PORT}"
    local target_ip=""

    if [[ -n "$host_name" ]]; then
        target_ip=$(get_vm_config "$host_name" "IP")
        target_user=$(get_vm_config "$host_name" "USER")
        target_port=$(get_vm_config "$host_name" "PORT")
        [[ -n "$target_ip" ]] && target_host="$target_ip"
    fi

    log "INFO" "Checking VM status for ${host_name} (${target_host})"

    if ! check_vm_connectivity "$host_name"; then
        return 1
    fi

    # Show configuration
    show_vm_config "$host_name"
    echo

    # Check NixOS version
    echo -e "${BOLD}NixOS Version:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_host}" "nixos-version"

    # Check system status
    echo -e "\n${BOLD}System Status:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_host}" "uptime"

    # Check disk usage
    echo -e "\n${BOLD}Disk Usage:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_host}" "df -h /"

    # Check memory usage
    echo -e "\n${BOLD}Memory Usage:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_host}" "free -h"

    # Check current generations
    echo -e "\n${BOLD}NixOS Generations:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_host}" "nix-env --list-generations --profile /nix/var/nix/profiles/system"
}

# Export functions
export -f check_vm_connectivity sync_to_vm deploy_to_vm
export -f rollback_deployment setup_vm get_vm_status