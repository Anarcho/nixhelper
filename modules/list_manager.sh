#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

list_hosts() {
    log "INFO" "NixOS Host Configurations"
    echo

    if [[ ! -d "${REPO_PATH}/hosts" ]]; then
        warning "No hosts directory found"
        return 0
    fi

    printf "%-20s %-15s %-15s %-20s\n" "HOSTNAME" "TYPE" "HW CONFIG" "SSH STATUS"
    echo "--------------------------------------------------------------------------------"

    for host_dir in "${REPO_PATH}/hosts"/*; do
        if [[ -d "$host_dir" && "$(basename "$host_dir")" != "common" ]]; then
            local host_name
            host_name=$(basename "$host_dir")

            # Determine host type
            local host_type="unknown"
            for type in "${HOST_TYPES[@]}"; do
                if [[ -f "${host_dir}/host-type/${type}.nix" ]]; then
                    host_type="$type"
                    break
                fi
            done

            # Check hardware config
            local hw_status="missing"
            if [[ -f "${host_dir}/hardware-configuration.nix" ]]; then
                hw_status="present"
            fi

            # Check SSH status
            local ssh_status="not configured"
            if check_existing_ssh_config "$host_name" >/dev/null 2>&1; then
                ssh_status="configured"
            fi

            printf "%-20s %-15s %-15s %-20s\n" \
                "$host_name" "$host_type" "$hw_status" "$ssh_status"
        fi
    done
}

list_users() {
    log "INFO" "Home Manager User Configurations"
    echo

    if [[ ! -d "${REPO_PATH}/home" ]]; then
        warning "No home directory found"
        return 0
    fi

    printf "%-20s %-30s %-20s\n" "USERNAME" "ENABLED HOSTS" "MODULES"
    echo "--------------------------------------------------------------------------------"

    for user_dir in "${REPO_PATH}/home"/*; do
        if [[ -d "$user_dir" ]]; then
            local user_name
            user_name=$(basename "$user_dir")

            # Find enabled hosts for user
            local enabled_hosts=""
            if grep -q "${user_name}@" "${REPO_PATH}/flake.nix"; then
                enabled_hosts=$(grep -o "${user_name}@[a-zA-Z0-9_-]*" "${REPO_PATH}/flake.nix" | \
                    cut -d'@' -f2 | tr '\n' ',' | sed 's/,$//')
            fi

            # Count enabled modules
            local module_count=0
            if [[ -f "${user_dir}/default.nix" ]]; then
                module_count=$(grep -c "enable = true;" "${user_dir}/default.nix" || echo 0)
            fi

            printf "%-20s %-30s %-20s\n" \
                "$user_name" "${enabled_hosts:-none}" "${module_count} modules"
        fi
    done
}

list_modules() {
    local category="$1"
    log "INFO" "Available Modules"
    echo

    printf "%-15s %-20s %-15s %-20s\n" "CATEGORY" "NAME" "TYPE" "STATUS"
    echo "--------------------------------------------------------------------------------"

    for cat in "${!MODULE_CATEGORIES[@]}"; do
        if [[ -z "$category" || "$category" == "$cat" ]]; then
            if [[ -d "${REPO_PATH}/modules/${cat}" ]]; then
                for module in "${REPO_PATH}/modules/${cat}"/*; do
                    if [[ -d "$module" ]]; then
                        local name
                        name=$(basename "$module")

                        # Determine module type
                        local type="nixos"
                        if grep -q "home = {" "${module}/default.nix" 2>/dev/null; then
                            type="home-manager"
                        fi

                        # Check if module is used
                        local status="unused"
                        if grep -r "modules.${cat}.${name}.enable = true" "${REPO_PATH}" >/dev/null 2>&1; then
                            status="in use"
                        fi

                        printf "%-15s %-20s %-15s %-20s\n" \
                            "$cat" "$name" "$type" "$status"
                    fi
                done
            fi
        fi
    done
}

list_dev_environments() {
    log "INFO" "Development Environments"
    echo

    printf "%-15s %-40s %-15s\n" "NAME" "DESCRIPTION" "STATUS"
    echo "--------------------------------------------------------------------------------"

    for env in "${!DEV_ENVIRONMENTS[@]}"; do
        local status="not installed"
        if [[ -d "${REPO_PATH}/modules/development/${env}" ]]; then
            if grep -r "modules.development.${env}.enable = true" "${REPO_PATH}" >/dev/null 2>&1; then
                status="active"
            else
                status="installed"
            fi
        fi

        printf "%-15s %-40s %-15s\n" \
            "$env" "${DEV_ENVIRONMENTS[$env]}" "$status"
    done
}

list_generations() {
    log "INFO" "System Generations"
    echo

    # NixOS generations
    if is_nixos; then
        echo "NixOS Generations:"
        echo "------------------"
        nix-env --list-generations --profile /nix/var/nix/profiles/system
        echo
    fi

    # Home Manager generations
    if command -v home-manager &>/dev/null; then
        echo "Home Manager Generations:"
        echo "------------------------"
        home-manager generations
    fi
}

list_backups() {
    log "INFO" "Available Backups"
    echo

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        warning "No backup directory found"
        return 0
    fi

    printf "%-30s %-20s %-20s\n" "BACKUP NAME" "DATE" "SIZE"
    echo "--------------------------------------------------------------------------------"

    for backup in "${BACKUP_DIR}"/backup_*; do
        if [[ -d "$backup" ]]; then
            local name
            name=$(basename "$backup")

            local date
            date=$(echo "$name" | sed 's/backup_\([0-9]\{8\}_[0-9]\{6\}\).*/\1/')
            date=$(date -d "${date:0:8} ${date:9:2}:${date:11:2}:${date:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

            local size
            size=$(du -sh "$backup" | cut -f1)

            printf "%-30s %-20s %-20s\n" \
                "$name" "${date:-unknown}" "$size"
        fi
    done
}

# Export functions
export -f list_hosts list_users list_modules list_dev_environments list_generations list_backups
