#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

check_existing_ssh_config() {
    local search_hostname="$1"
    local ssh_config="$HOME/.ssh/config"

    if [[ ! -f "$ssh_config" ]]; then
        debug "SSH config file not found"
        return 1
    fi

    if grep -qw "^Host ${search_hostname}$" "$ssh_config"; then
        success "Found existing SSH configuration for ${search_hostname}"
        return 0
    fi

    debug "No existing SSH configuration found for ${search_hostname}"
    return 1
}


setup_ssh_keys() {
    local hostname="$1"          # Hostname or IP for the remote host
    local username="${2:-$USER}" # Default to current user if not provided
    local port="${3:-22}"        # Default to port 22
    local ip_address="${4}"
    local ssh_dir="$HOME/.ssh"
    local ssh_config="$ssh_dir/config"

    log "INFO" "Setting up SSH configuration for ${hostname}"

    # Backup existing SSH configuration
    backup_ssh_config

    # Ensure SSH directory exists with correct permissions
    ensure_directory "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Set SSH key paths dynamically based on hostname
    local ssh_key="${ssh_dir}/${hostname}"
    local pub_key="${ssh_key}.pub"

    # Generate a new key, overwriting any existing key for the host
    log "INFO" "Generating a new SSH key for ${hostname}..."
    ssh-keygen -t ed25519 -C "${username}@${hostname}" -f "$ssh_key" -N "" || {
        error "Failed to generate SSH key for ${hostname}"
        return 1
    }
    success "Generated new SSH key: ${ssh_key}"

    # Ensure SSH config file exists
    touch "$ssh_config"
    chmod 600 "$ssh_config"

    # Remove any existing configuration for the host
    log "INFO" "Removing any existing SSH configuration for ${hostname}..."
    awk -v host="$hostname" '
        BEGIN { removed = 0 }
        /^Host / {
            if ($2 == host) {
                removed = 1
                next
            }
        }
        !removed || /^$/ { removed = 0; print }
    ' "$ssh_config" > "${ssh_config}.tmp" && mv "${ssh_config}.tmp" "$ssh_config"

    # Add the new SSH config entry
    cat >> "$ssh_config" <<EOF

Host ${hostname}
    HostName ${ip_address}
    User ${username}
    Port ${port}
    IdentityFile ${ssh_key}
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 2
EOF
    success "Added SSH configuration for ${hostname}"

    # Attempt to copy the public key to the remote host
    log "INFO" "Copying SSH key to the remote host (${hostname})..."
    if ! ssh-copy-id -i "$pub_key" -p "$port" "${username}@${ip_address}"; then
        warning "Could not automatically copy SSH key. Manual copy may be required."
        echo "Run this command on the remote host:"
        echo "mkdir -p ~/.ssh && echo '$(cat "$pub_key")' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    else
        success "SSH key successfully copied to ${hostname}"
    fi

    # Test the SSH connection
    if ssh -q -p "$port" -o BatchMode=yes "${username}@${hostname}" exit; then
        success "SSH connection to ${hostname} verified successfully"
    else
        error "SSH connection test failed for ${hostname}"
        return 1
    fi
}


backup_ssh_config() {
    local ssh_dir="$HOME/.ssh"
    local backup_dir="${BACKUP_DIR}/ssh_$(create_timestamp)"

    log "INFO" "Backing up SSH configuration"

    # Create backup directory
    ensure_directory "$backup_dir"

    # Backup SSH directory if it exists
    if [[ -d "$ssh_dir" ]]; then
        if rsync -a --exclude '*.pub' "$ssh_dir/" "$backup_dir/"; then
            success "SSH configuration backed up to ${backup_dir}"
        else
            error "Failed to backup SSH configuration"
            return 1
        fi
    else
        warning "No SSH configuration to backup"
    fi
}

restore_ssh_config() {
    local backup_name="$1"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    local ssh_dir="$HOME/.ssh"

    if [[ ! -d "$backup_path" ]]; then
        error "Backup not found: ${backup_path}"
        return 1
    fi

    log "INFO" "Restoring SSH configuration from ${backup_name}"

    # Backup current configuration before restore
    backup_ssh_config

    # Restore from backup
    if rsync -a "$backup_path/" "$ssh_dir/"; then
        # Fix permissions
        chmod 700 "$ssh_dir"
        chmod 600 "$ssh_dir"/*
        chmod 644 "$ssh_dir"/*.pub 2>/dev/null || true
        success "SSH configuration restored from ${backup_name}"
    else
        error "Failed to restore SSH configuration"
        return 1
    fi
}

list_ssh_configs() {
    local ssh_config="$HOME/.ssh/config"

    if [[ ! -f "$ssh_config" ]]; then
        warning "No SSH config file found"
        return 1
    fi

    log "INFO" "Configured SSH hosts:"
    echo

    # Parse and display SSH configurations
    awk '/^Host [^*]/ {
        host=$2
        printf "Host: %s\n", host
        in_host=1
        next
    }
    in_host && /^[[:space:]]/ {
        gsub(/^[[:space:]]+/, "  ")
        print
    }
    /^$/ { in_host=0; print "" }' "$ssh_config"
}

remove_ssh_config() {
    local hostname="$1"
    local ssh_config="$HOME/.ssh/config"

    if [[ ! -f "$ssh_config" ]]; then
        error "No SSH config file found"
        return 1
    fi

    if ! check_existing_ssh_config "$hostname"; then
        error "No configuration found for host: ${hostname}"
        return 1
    fi

    log "INFO" "Removing SSH configuration for ${hostname}"

    # Create backup before modification
    backup_ssh_config

    # Remove the host configuration
    local tmp_config="${ssh_config}.tmp"
    awk -v host="$hostname" '
        /^Host '"$hostname"'$/,/^(Host|$)/ { next }
        { print }
    ' "$ssh_config" > "$tmp_config" && mv "$tmp_config" "$ssh_config"

    success "Removed SSH configuration for ${hostname}"
}

# Export functions
export -f check_existing_ssh_config setup_ssh_keys backup_ssh_config
export -f restore_ssh_config list_ssh_configs remove_ssh_config
