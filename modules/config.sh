#!/usr/bin/env bash

# Only declare colors if they haven't been declared yet
if [[ -z "$RED" ]]; then
    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# XDG Base Directory Specification
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Function to find the repository root (directory containing flake.nix)
find_repo_root() {
    local current_dir="$1"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/flake.nix" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    echo "$PWD"
    return 1
}

# Function to determine configuration paths
resolve_paths() {
    # Try to find repository root from current directory
    REPO_PATH="${NIXHELP_REPO_PATH:-$(find_repo_root "$PWD")}"

    # Determine configuration directory
    if [[ -n "$NIXHELP_CONFIG_DIR" ]]; then
        CONFIG_DIR="$NIXHELP_CONFIG_DIR"
    else
        # Check for local configuration first
        if [[ -d "$REPO_PATH/.nixhelp" ]]; then
            CONFIG_DIR="$REPO_PATH/.nixhelp"
        else
            CONFIG_DIR="${XDG_CONFIG_HOME}/nixhelp"
        fi
    fi

    # Set derived paths
    CACHE_DIR="${NIXHELP_CACHE_DIR:-${XDG_CACHE_HOME}/nixhelp}"
    DATA_DIR="${NIXHELP_DATA_DIR:-${XDG_DATA_HOME}/nixhelp}"
    
    # Configuration files and directories
    CONFIG_FILE="${CONFIG_DIR}/config"
    BACKUP_DIR="${CONFIG_DIR}/backups"
    TEMPLATE_DIR="${CONFIG_DIR}/templates"
    LOG_DIR="${CONFIG_DIR}/logs"
    LOG_FILE="${LOG_DIR}/nixhelp.log"

    # Export all paths
    export REPO_PATH CONFIG_DIR CACHE_DIR DATA_DIR
    export CONFIG_FILE BACKUP_DIR TEMPLATE_DIR LOG_DIR LOG_FILE
}

# Module categories
if [[ -z "${MODULE_CATEGORIES[*]}" ]]; then
    declare -A MODULE_CATEGORIES=(
        ["core"]="Core system modules"
        ["desktop"]="Desktop environment modules"
        ["apps"]="Application modules"
        ["development"]="Development environment modules"
        ["editor"]="Editor configurations"
        ["theme"]="Theme and appearance modules"
        ["services"]="System services"
    )
fi

# Host types
if [[ -z "${HOST_TYPES[*]}" ]]; then
    declare -a HOST_TYPES=(
        "desktop"
        "server"
        "vm"
        "minimal"
        "wsl"
    )
fi

# Default settings
if [[ -z "${DEFAULT_SETTINGS[*]}" ]]; then
    declare -A DEFAULT_SETTINGS=(
        ["MAX_LOG_SIZE"]="10M"
        ["MAX_LOG_FILES"]="5"
        ["VERBOSE"]="false"
    )
fi

# Function to load configuration
load_config() {
    local config_file="$1"
    local key value

    # Load defaults first
    for key in "${!DEFAULT_SETTINGS[@]}"; do
        declare -g "$key"="${DEFAULT_SETTINGS[$key]}"
    done

    # Override with environment variables if set
    for key in "${!DEFAULT_SETTINGS[@]}"; do
        if [[ -n "${!key}" ]]; then
            continue  # Skip if environment variable is set
        fi
        
        # Try to load from config file
        if [[ -f "$config_file" ]]; then
            value=$(grep "^${key}=" "$config_file" | cut -d'=' -f2-)
            if [[ -n "$value" ]]; then
                declare -g "$key"="$value"
            fi
        fi
    done
}

# Initialize configuration
init_config() {
    # Resolve all paths first
    resolve_paths

    # Create required directories
    mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}" "${TEMPLATE_DIR}" \
             "${LOG_DIR}" "${CACHE_DIR}" "${DATA_DIR}"

    # Create default configuration if it doesn't exist
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<EOF
# NixHelp Configuration
# Generated on $(date)

# Paths
REPO_PATH="${REPO_PATH}"
CONFIG_DIR="${CONFIG_DIR}"
CACHE_DIR="${CACHE_DIR}"
DATA_DIR="${DATA_DIR}"

# Logging
VERBOSE=${VERBOSE}
MAX_LOG_SIZE="${MAX_LOG_SIZE}"
MAX_LOG_FILES=${MAX_LOG_FILES}
EOF
    fi

    # Load configuration
    load_config "${CONFIG_FILE}"

    # Ensure log file exists
    touch "${LOG_FILE}"
}

# Get configuration value with default
get_config() {
    local key="$1"
    local default="$2"
    local value

    # Check environment first
    if [[ -n "${!key}" ]]; then
        echo "${!key}"
        return 0
    fi

    # Then check config file
    if [[ -f "${CONFIG_FILE}" ]]; then
        value=$(grep "^${key}=" "${CONFIG_FILE}" | cut -d'=' -f2-)
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi

    # Finally use default
    echo "$default"
}

# Set configuration value
set_config() {
    local key="$1"
    local value="$2"
    local config_file="${CONFIG_FILE}"

    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$config_file")"

    # Update or add configuration
    if [[ -f "$config_file" ]]; then
        if grep -q "^${key}=" "$config_file"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$config_file"
        else
            echo "${key}=${value}" >> "$config_file"
        fi
    else
        echo "${key}=${value}" > "$config_file"
    fi

    # Update current session
    declare -g "$key"="$value"
}

# Get VM-specific configuration
get_vm_config() {
    local hostname="$1"
    local property="$2"  # IP, USER, PORT
    local key="VM_${hostname}_${property}"
    
    get_config "$key"
}

# Set VM-specific configuration
set_vm_config() {
    local hostname="$1"
    local property="$2"  # IP, USER, PORT
    local value="$3"
    local key="VM_${hostname}_${property}"
    
    set_config "$key" "$value"
}

# Show VM-specific configuration
show_vm_config() {
    local hostname="$1"
    
    echo -e "${BOLD}VM Configuration for ${hostname}:${NC}"
    echo "IP Address: $(get_vm_config "$hostname" "IP")"
    echo "Username:   $(get_vm_config "$hostname" "USER")"
    echo "Port:      $(get_vm_config "$hostname" "PORT")"
}

# Show current configuration
show_config() {
    echo -e "${BOLD}NixHelp Configuration${NC}"
    echo "====================="
    echo
    echo -e "${BOLD}Paths:${NC}"
    echo "Repository: $REPO_PATH"
    echo "Config Dir: $CONFIG_DIR"
    echo "Cache Dir:  $CACHE_DIR"
    echo "Data Dir:   $DATA_DIR"
    echo
    echo -e "${BOLD}VM Configurations:${NC}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        grep "^VM_.*_" "${CONFIG_FILE}" | while read -r line; do
            local hostname
            hostname=$(echo "$line" | cut -d'_' -f2)
            if [[ -n "$hostname" && "$hostname" != *"="* ]]; then
                show_vm_config "$hostname"
                echo
            fi
        done
    fi
    echo
    echo -e "${BOLD}Logging:${NC}"
    echo "Verbose: $VERBOSE"
    echo "Max Log Size: $MAX_LOG_SIZE"
    echo "Max Log Files: $MAX_LOG_FILES"
    echo
    if [[ -f "${CONFIG_FILE}" ]]; then
        echo -e "${BOLD}Custom Settings:${NC}"
        grep -v '^#' "${CONFIG_FILE}" | grep -v '^VM_' | grep -v '^$' || echo "No custom settings"
    fi
}

# Export functions and variables
export RED GREEN YELLOW BLUE PURPLE CYAN BOLD NC
export -A MODULE_CATEGORIES DEFAULT_SETTINGS
export -a HOST_TYPES
export -f find_repo_root resolve_paths load_config init_config get_config set_config
export -f get_vm_config set_vm_config show_vm_config show_config

# Initialize if this script is being sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_config
fi