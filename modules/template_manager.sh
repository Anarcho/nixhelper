#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Template directory structure
TEMPLATE_BASE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nixhelp/templates"
TEMPLATE_BASE_CONFIGS="${TEMPLATE_BASE_DIR}/base"
TEMPLATE_FULL_CONFIGS="${TEMPLATE_BASE_DIR}/configs"
TEMPLATE_DEV_CONFIGS="${TEMPLATE_BASE_DIR}/development"

# Template metadata filename
TEMPLATE_META_FILE="template.json"

# Initialize template directory structure
init_template_dirs() {
    local dirs=(
        # Base templates
        "${TEMPLATE_BASE_CONFIGS}/flake"
        "${TEMPLATE_BASE_CONFIGS}/module/nixos"
        "${TEMPLATE_BASE_CONFIGS}/module/home-manager"
        "${TEMPLATE_BASE_CONFIGS}/host-configs"
        # Full configurations
        "${TEMPLATE_FULL_CONFIGS}/editor/neovim"
        "${TEMPLATE_FULL_CONFIGS}/editor/vim"
        "${TEMPLATE_FULL_CONFIGS}/terminal/kitty"
        "${TEMPLATE_FULL_CONFIGS}/terminal/alacritty"
        "${TEMPLATE_FULL_CONFIGS}/wm/sway"
        "${TEMPLATE_FULL_CONFIGS}/wm/hyprland"
        # Development environments
        "${TEMPLATE_DEV_CONFIGS}/rust"
        "${TEMPLATE_DEV_CONFIGS}/python"
        "${TEMPLATE_DEV_CONFIGS}/node"
    )

    for dir in "${dirs[@]}"; do
        if ! ensure_directory "$dir"; then
            error "Failed to create template directory: ${dir}"
            return 1
        fi
    done

    success "Template directories initialized"
}

# Validate template metadata
validate_template_meta() {
    local template_dir="$1"
    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"

    if [[ ! -f "$meta_file" ]]; then
        error "Template metadata file not found: ${meta_file}"
        return 1
    fi

    # Basic JSON validation
    if ! jq empty "$meta_file" 2>/dev/null; then
        error "Invalid template metadata JSON: ${meta_file}"
        return 1
    fi

    # Check required fields
    local required_fields=("name" "version" "description" "category" "type")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$meta_file" >/dev/null 2>&1; then
            error "Missing required field in template metadata: ${field}"
            return 1
        fi
    done

    return 0
}

# Get template metadata value
get_template_meta() {
    local template_dir="$1"
    local field="$2"
    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    jq -r ".$field" "$meta_file" 2>/dev/null
}

# List available templates
list_templates() {
    local category="${1:-all}"
    
    log "INFO" "Available templates:"
    echo

    display_templates() {
        local base_dir="$1"
        local category_name="$2"
        
        if [[ ! -d "$base_dir" ]]; then
            return
        fi

        echo -e "${BOLD}${category_name}${NC}"
        echo "----------------------------------------"
        
        find "$base_dir" -name "${TEMPLATE_META_FILE}" -type f | while read -r meta_file; do
            local template_dir="$(dirname "$meta_file")"
            local name="$(get_template_meta "$template_dir" "name")"
            local version="$(get_template_meta "$template_dir" "version")"
            local description="$(get_template_meta "$template_dir" "description")"
            local type="$(get_template_meta "$template_dir" "type")"
            
            printf "%-20s %-10s %-10s %s\n" "${name}" "v${version}" "(${type})" "${description}"
        done
        echo
    }

    case "$category" in
        "all"|"base")
            display_templates "$TEMPLATE_BASE_CONFIGS" "Base Templates"
            ;;
        "all"|"configs")
            display_templates "$TEMPLATE_FULL_CONFIGS" "Full Configurations"
            ;;
        "all"|"development")
            display_templates "$TEMPLATE_DEV_CONFIGS" "Development Environments"
            ;;
        *)
            error "Invalid template category: ${category}"
            return 1
            ;;
    esac
}

# Apply a template
apply_template() {
    local category="$1"
    local name="$2"
    local target_path="$3"
    local variables="${4:-}"
    
    local source_dir
    case "$category" in
        "base")
            source_dir="${TEMPLATE_BASE_CONFIGS}/${name}"
            ;;
        "configs")
            source_dir="${TEMPLATE_FULL_CONFIGS}/${name}"
            ;;
        "development")
            source_dir="${TEMPLATE_DEV_CONFIGS}/${name}"
            ;;
        *)
            error "Invalid template category: ${category}"
            return 1
            ;;
    esac

    if [[ ! -d "$source_dir" ]]; then
        error "Template not found: ${category}/${name}"
        return 1
    fi

    # Create target directory if needed
    if ! ensure_directory "$target_path"; then
        error "Failed to create target directory: ${target_path}"
        return 1
    fi

    # Process each template file
    find "$source_dir" -type f -not -name "${TEMPLATE_META_FILE}" | while read -r template_file; do
        local relative_path="${template_file#$source_dir/}"
        local target_file="${target_path}/${relative_path}"
        local target_dir="$(dirname "$target_file")"

        # Create target directory
        if ! ensure_directory "$target_dir"; then
            error "Failed to create directory: ${target_dir}"
            return 1
        fi

        # Process template variables if provided
        if [[ -n "$variables" ]]; then
            # Create temporary file for variable substitution
            local temp_file="$(mktemp)"
            cp "$template_file" "$temp_file"

            # Apply variables
            while IFS='=' read -r key value; do
                sed -i "s|{{${key}}}|${value}|g" "$temp_file"
            done <<< "$variables"

            # Move processed file to target
            mv "$temp_file" "$target_file"
        else
            # Direct copy if no variables
            cp "$template_file" "$target_file"
        fi
    done

    success "Template applied successfully: ${category}/${name} to ${target_path}"
}

# Export functions and variables
export TEMPLATE_BASE_DIR TEMPLATE_BASE_CONFIGS TEMPLATE_FULL_CONFIGS TEMPLATE_DEV_CONFIGS
export -f init_template_dirs validate_template_meta get_template_meta
export -f list_templates apply_template