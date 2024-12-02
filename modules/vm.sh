#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/ssh.sh"

check_vm_connectivity() {
    local host_name="$1"
    local target_ip="" target_user="" target_port=""
    
    # Get host-specific configuration
    target_ip=$(get_vm_config "$host_name" "IP")
    target_user=$(get_vm_config "$host_name" "USER")
    target_port=$(get_vm_config "$host_name" "PORT")

    if [[ -z "$target_ip" || -z "$target_user" || -z "$target_port" ]]; then
        error "Missing VM configuration for ${host_name}"
        return 1
    fi

    log "INFO" "Checking VM connectivity for ${target_ip}"

    if ! check_internet; then
        error "No internet connection available"
        return 1
    fi

    if ssh -q -p "${target_port}" "${target_user}@${target_ip}" exit 2>/dev/null; then
        success "VM connection successful"
        return 0
    else
        error "Cannot connect to VM at ${target_ip}"
        return 1
    fi
}

sync_to_vm() {
    local host_name="$1"
    local source_path="${REPO_PATH}"
    local extra_excludes=("${@:2}")
    local target_ip="" target_user="" target_port="" target_path=""

    # Get host-specific configuration
    target_ip=$(get_vm_config "$host_name" "IP")
    target_user=$(get_vm_config "$host_name" "USER")
    target_port=$(get_vm_config "$host_name" "PORT")
    target_path=$(get_vm_config "$host_name" "PATH")

    if [[ -z "$target_ip" || -z "$target_user" || -z "$target_port" ]]; then
        error "Missing VM configuration for ${host_name}"
        return 1
    fi

    log "INFO" "Syncing files to VM ${target_ip} for host ${host_name}"

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
        "${target_user}@${target_ip}:${target_path:-/home/${target_user}/nixos-config}/"; then
        success "Files synced to VM successfully"
        return 0
    else
        error "Failed to sync files to VM"
        return 1
    fi
}

setup_vm() {
    local host_name="$1"
    local username="" target_ip="" target_port="" current_config=""

    log "INFO" "Setting up VM configuration for ${host_name}"

    # Get existing configuration if any
    current_config=$(show_vm_config "$host_name" 2>/dev/null)

    # Only prompt for values if they're not already set
    if [[ -z "$(get_vm_config "$host_name" "USER")" ]]; then
        read -p "VM Username: " username
        if [[ -n "$username" ]]; then
            set_vm_config "$host_name" "USER" "${username}"
        fi
    fi

    if [[ -z "$(get_vm_config "$host_name" "IP")" ]]; then
        read -p "VM IP Address: " target_ip
        if [[ -n "$target_ip" ]]; then
            set_vm_config "$host_name" "IP" "${target_ip}"
        fi
    fi

    if [[ -z "$(get_vm_config "$host_name" "PORT")" ]]; then
        read -p "VM Port [22]: " target_port
        set_vm_config "$host_name" "PORT" "${target_port:-22}"
    fi

    # Set default path if not specified
    if [[ -z "$(get_vm_config "$host_name" "PATH")" ]]; then
        set_vm_config "$host_name" "PATH" "/home/$(get_vm_config "$host_name" "USER")/nixos-config"
    fi

    success "VM configuration updated successfully"
    show_vm_config "$host_name"
    
    # Test connectivity and offer SSH setup if needed
    if ! check_vm_connectivity "$host_name"; then
        if confirm_action "Would you like to setup SSH for this VM?"; then
            setup_ssh_keys \
                "$host_name" \
                "$(get_vm_config "$host_name" "USER")" \
                "$(get_vm_config "$host_name" "PORT")" \
                "$(get_vm_config "$host_name" "IP")"
        fi
    fi
}

deploy_to_vm() {
    local host_name="$1"
    local deploy_type="${2:-all}"
    local user_name="${3:-$USER}"
    local target_ip="" target_user="" target_port="" target_path=""

    # Get host-specific configuration
    target_ip=$(get_vm_config "$host_name" "IP")
    target_user=$(get_vm_config "$host_name" "USER")
    target_port=$(get_vm_config "$host_name" "PORT")
    target_path=$(get_vm_config "$host_name" "PATH")

    if [[ -z "$target_ip" || -z "$target_user" || -z "$target_port" ]]; then
        error "Missing VM configuration for ${host_name}"
        return 1
    fi

    log "INFO" "Deploying ${host_name} configuration to VM ${target_ip}"

    # Create backup before deployment
    create_backup

    # Sync files to VM
    if ! sync_to_vm "${host_name}"; then
        return 1
    fi

    # Build configuration on VM
    log "INFO" "Building configuration on VM"
    local build_cmd="cd ${target_path:-/home/${target_user}/nixos-config} && "

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

    if ssh -p "${target_port}" "${target_user}@${target_ip}" "${build_cmd}"; then
        success "Deployment completed successfully"
        return 0
    else
        error "Deployment failed"
        if confirm_action "Would you like to rollback?"; then
            rollback_deployment "${host_name}" "${deploy_type}"
        fi
        return 1
    fi
}

get_vm_status() {
    local host_name="$1"
    local target_ip="" target_user="" target_port=""

    # Get host-specific configuration
    target_ip=$(get_vm_config "$host_name" "IP")
    target_user=$(get_vm_config "$host_name" "USER")
    target_port=$(get_vm_config "$host_name" "PORT")

    if [[ -z "$target_ip" || -z "$target_user" || -z "$target_port" ]]; then
        error "Missing VM configuration for ${host_name}"
        return 1
    fi

    log "INFO" "Checking VM status for ${host_name} (${target_ip})"

    if ! check_vm_connectivity "$host_name"; then
        return 1
    fi

    # Show configuration
    show_vm_config "$host_name"
    echo

    # Check NixOS version
    echo -e "${BOLD}NixOS Version:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_ip}" "nixos-version"

    # Check system status
    echo -e "\n${BOLD}System Status:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_ip}" "uptime"

    # Check disk usage
    echo -e "\n${BOLD}Disk Usage:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_ip}" "df -h /"

    # Check memory usage
    echo -e "\n${BOLD}Memory Usage:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_ip}" "free -h"

    # Check current generations
    echo -e "\n${BOLD}NixOS Generations:${NC}"
    ssh -p "${target_port}" "${target_user}@${target_ip}" "nix-env --list-generations --profile /nix/var/nix/profiles/system"
}

rollback_deployment() {
    local host_name="$1"
    local deploy_type="$2"
    local target_ip="" target_user="" target_port="" target_path=""

    # Get host-specific configuration
    target_ip=$(get_vm_config "$host_name" "IP")
    target_user=$(get_vm_config "$host_name" "USER")
    target_port=$(get_vm_config "$host_name" "PORT")
    target_path=$(get_vm_config "$host_name" "PATH")

    if [[ -z "$target_ip" || -z "$target_user" || -z "$target_port" ]]; then
        error "Missing VM configuration for ${host_name}"
        return 1
    fi

    log "INFO" "Rolling back VM deployment"

    local rollback_cmd="cd ${target_path:-/home/${target_user}/nixos-config} && "
    case "${deploy_type}" in
        "nixos"|"all")
            rollback_cmd+="sudo nixos-rebuild switch --rollback"
            ;;
        "home-manager")
            rollback_cmd+="home-manager generations rollback"
            ;;
        *)
            error "Invalid deploy type: ${deploy_type}"
            return 1
            ;;
    esac

    if ssh -p "${target_port}" "${target_user}@${target_ip}" "${rollback_cmd}"; then
        success "Rollback completed successfully"
        return 0
    else
        error "Rollback failed"
        return 1
    fi
}

# Export functions
export -f check_vm_connectivity sync_to_vm deploy_to_vm setup_vm get_vm_status rollback_deployment