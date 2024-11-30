#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Template directory structure
TEMPLATE_BASE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nixhelp/templates"
TEMPLATE_BASE_CONFIGS="${TEMPLATE_BASE_DIR}/base"
TEMPLATE_FULL_CONFIGS="${TEMPLATE_BASE_DIR}/configs"
TEMPLATE_DEV_CONFIGS="${TEMPLATE_BASE_DIR}/development"
TEMPLATE_CUSTOM_DIR="${TEMPLATE_BASE_DIR}/custom"

# Template metadata and configuration
TEMPLATE_META_FILE="template.json"
TEMPLATE_SCHEMA_VERSION="1.0"
TEMPLATE_CACHE_DIR="${CACHE_DIR}/templates"

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
        # Custom templates
        "${TEMPLATE_CUSTOM_DIR}"
        # Cache directory
        "${TEMPLATE_CACHE_DIR}"
    )

    for dir in "${dirs[@]}"; do
        if ! ensure_directory "$dir"; then
            error "Failed to create template directory: ${dir}"
            return 1
        fi
    done

    success "Template directories initialized"
}

# Template metadata validation
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

    # Check schema version
    local schema_version
    schema_version=$(jq -r '.schemaVersion // empty' "$meta_file")
    if [[ -z "$schema_version" ]]; then
        error "Missing schema version in template metadata"
        return 1
    fi

    # Validate required fields
    local required_fields=(
        "name"
        "version"
        "description"
        "category"
        "type"
        "dependencies"
        "variables"
        "compatibility"
    )

    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$meta_file" >/dev/null 2>&1; then
            error "Missing required field in template metadata: ${field}"
            return 1
        fi
    done

    # Validate dependencies
    if ! jq -e '.dependencies | type == "array"' "$meta_file" >/dev/null 2>&1; then
        error "Invalid dependencies format in template metadata"
        return 1
    fi

    # Validate variables
    if ! jq -e '.variables | type == "object"' "$meta_file" >/dev/null 2>&1; then
        error "Invalid variables format in template metadata"
        return 1
    fi

    return 0
}

# Get template metadata value
get_template_meta() {
    local template_dir="$1"
    local field="$2"
    local default="${3:-}"
    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"

    if [[ ! -f "$meta_file" ]]; then
        echo "$default"
        return 1
    fi

    local value
    value=$(jq -r ".$field // empty" "$meta_file" 2>/dev/null)
    
    if [[ -z "$value" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Resolve template dependencies
resolve_template_deps() {
    local template_dir="$1"
    local deps_file="${TEMPLATE_CACHE_DIR}/deps_$(basename "$template_dir")"
    
    # Get dependencies from metadata
    local deps
    deps=$(get_template_meta "$template_dir" "dependencies" "[]")
    
    # Create empty deps file
    echo "[]" > "$deps_file"
    
    # Process each dependency
    echo "$deps" | jq -c '.[]' | while read -r dep; do
        local dep_name
        local dep_version
        dep_name=$(echo "$dep" | jq -r '.name')
        dep_version=$(echo "$dep" | jq -r '.version')
        
        # Find dependency template
        local dep_dir
        dep_dir=$(find_template "$dep_name")
        
        if [[ -z "$dep_dir" ]]; then
            error "Dependency not found: ${dep_name}"
            return 1
        fi
        
        # Validate version compatibility
        local dep_current_version
        dep_current_version=$(get_template_meta "$dep_dir" "version")
        if ! check_version_compatibility "$dep_version" "$dep_current_version"; then
            error "Incompatible dependency version: ${dep_name} (required: ${dep_version}, found: ${dep_current_version})"
            return 1
        fi
        
        # Add to deps file
        jq --arg name "$dep_name" --arg dir "$dep_dir" '. += [{"name": $name, "dir": $dir}]' "$deps_file" > "${deps_file}.tmp"
        mv "${deps_file}.tmp" "$deps_file"
    done
    
    echo "$deps_file"
}

# Check version compatibility
check_version_compatibility() {
    local required="$1"
    local current="$2"
    
    # Simple version comparison for now
    # TODO: Implement proper semver comparison
    if [[ "$required" == "$current" ]]; then
        return 0
    fi
    
    return 1
}

# Find template by name
find_template() {
    local name="$1"
    local template_dirs=(
        "$TEMPLATE_BASE_CONFIGS"
        "$TEMPLATE_FULL_CONFIGS"
        "$TEMPLATE_DEV_CONFIGS"
        "$TEMPLATE_CUSTOM_DIR"
    )
    
    for dir in "${template_dirs[@]}"; do
        local found
        found=$(find "$dir" -type f -name "${TEMPLATE_META_FILE}" -exec grep -l "\"name\": \"${name}\"" {} \;)
        if [[ -n "$found" ]]; then
            dirname "$found"
            return 0
        fi
    done
    
    return 1
}

# Process template variables
process_template_variables() {
    local template_dir="$1"
    local variables="$2"
    local target_file="$3"
    
    # Get required variables from metadata
    local required_vars
    required_vars=$(get_template_meta "$template_dir" "variables" "{}")
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    cp "$target_file" "$temp_file"
    
    # Process each variable
    echo "$required_vars" | jq -r 'to_entries[] | .key' | while read -r var; do
        local default_value
        default_value=$(echo "$required_vars" | jq -r --arg var "$var" '.[$var].default // empty')
        local value="${variables[$var]:-$default_value}"
        
        if [[ -z "$value" ]]; then
            error "Missing required variable: ${var}"
            rm "$temp_file"
            return 1
        fi
        
        # Replace variable in file
        sed -i "s|{{${var}}}|${value}|g" "$temp_file"
    done
    
    mv "$temp_file" "$target_file"
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
            local template_dir
            template_dir=$(dirname "$meta_file")
            local name
            local version
            local description
            local type
            name=$(get_template_meta "$template_dir" "name")
            version=$(get_template_meta "$template_dir" "version")
            description=$(get_template_meta "$template_dir" "description")
            type=$(get_template_meta "$template_dir" "type")
            
            printf "%-20s %-10s %-10s %s\n" "${name}" "v${version}" "(${type})" "${description}"
            
            # Show dependencies if verbose mode
            if [[ "${VERBOSE}" == "true" ]]; then
                local deps
                deps=$(get_template_meta "$template_dir" "dependencies" "[]")
                if [[ "$deps" != "[]" ]]; then
                    echo "  Dependencies:"
                    echo "$deps" | jq -r '.[] | "    - \(.name) (\(.version))"'
                fi
            fi
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
        "all"|"custom")
            display_templates "$TEMPLATE_CUSTOM_DIR" "Custom Templates"
            ;;
        *)
            error "Invalid template category: ${category}"
            return 1
            ;;
    esac
}

# Apply a template
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
        "custom")
            source_dir="${TEMPLATE_CUSTOM_DIR}/${name}"
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

    # Validate template metadata
    if ! validate_template_meta "$source_dir"; then
        return 1
    fi

    # Resolve dependencies
    local deps_file
    deps_file=$(resolve_template_deps "$source_dir")
    if [[ ! -f "$deps_file" ]]; then
        error "Failed to resolve template dependencies"
        return 1
    fi

    # Create target directory
    if ! ensure_directory "$target_path"; then
        error "Failed to create target directory: ${target_path}"
        return 1
    fi

    # Apply dependent templates first
    jq -c '.[]' "$deps_file" | while read -r dep; do
        local dep_dir
        dep_dir=$(echo "$dep" | jq -r '.dir')
        if ! apply_template_files "$dep_dir" "$target_path" "$variables"; then
            error "Failed to apply dependent template: $(echo "$dep" | jq -r '.name')"
            return 1
        fi
    done

    # Apply main template
    if ! apply_template_files "$source_dir" "$target_path" "$variables"; then
        error "Failed to apply template: ${category}/${name}"
        return 1
    fi

    success "Template applied successfully: ${category}/${name} to ${target_path}"
}

# Apply template files
apply_template_files() {
    local source_dir="$1"
    local target_path="$2"
    local variables="$3"

    find "$source_dir" -type f -not -name "${TEMPLATE_META_FILE}" | while read -r template_file; do
        local relative_path="${template_file#$source_dir/}"
        local target_file="${target_path}/${relative_path}"
        local target_dir
        target_dir=$(dirname "$target_file")

        # Create target directory
        if ! ensure_directory "$target_dir"; then
            error "Failed to create directory: ${target_dir}"
            return 1
        fi

        # Copy file
        cp "$template_file" "$target_file"

        # Process variables if provided
        if [[ -n "$variables" ]]; then
            if ! process_template_variables "$source_dir" "$variables" "$target_file"; then
                error "Failed to process template variables: ${target_file}"
                return 1
            fi
        fi
    done
}

# Add custom template
add_custom_template() {
    local source_path="$1"
    local name="$2"
    local target_dir="${TEMPLATE_CUSTOM_DIR}/${name}"

    if [[ ! -d "$source_path" ]]; then
        error "Source path not found: ${source_path}"
        return 1
    fi

    if [[ ! -f "${source_path}/${TEMPLATE_META_FILE}" ]]; then
        error "Template metadata file not found in source"
        return 1
    fi

    # Validate metadata before copying
    if ! validate_template_meta "$source_path"; then
        return 1
    fi

    # Create target directory
    if ! ensure_directory "$target_dir"; then
        error "Failed to create custom template directory: ${target_dir}"
        return 1
    fi

    # Copy template files
    if rsync -av --delete "$source_path/" "$target_dir/"; then
        success "Custom template added: ${name}"
    else
        error "Failed to copy template files"
        return 1
    fi
}

# Remove custom template
remove_custom_template() {
    local name="$1"
    local target_dir="${TEMPLATE_CUSTOM_DIR}/${name}"

    if [[ ! -d "$target_dir" ]]; then
        error "Custom template not found: ${name}"
        return 1
    fi

    if rm -rf "$target_dir"; then
        success "Custom template removed: ${name}"
    else
        error "Failed to remove custom template"
        return 1
    fi
}

# Update template
update_template() {
    local category="$1"
    local name="$2"
    local source_path="$3"
    
    local target_dir
    case "$category" in
        "base")
            target_dir="${TEMPLATE_BASE_CONFIGS}/${name}"
            ;;
        "configs")
            target_dir="${TEMPLATE_FULL_CONFIGS}/${name}"
            ;;
        "development")
            target_dir="${TEMPLATE_DEV_CONFIGS}/${name}"
            ;;
        "custom")
            target_dir="${TEMPLATE_CUSTOM_DIR}/${name}"
            ;;
        *)
            error "Invalid template category: ${category}"
            return 1
            ;;
    esac

    if [[ ! -d "$target_dir" ]]; then
        error "Template not found: ${category}/${name}"
        return 1
    fi

    # Create backup of current template
    local backup_dir="${BACKUP_DIR}/templates/${category}_${name}_$(create_timestamp)"
    if ! ensure_directory "$backup_dir"; then
        error "Failed to create backup directory"
        return 1
    fi

    if ! rsync -a "$target_dir/" "$backup_dir/"; then
        error "Failed to backup template"
        return 1
    fi

    # Update template
    if [[ -n "$source_path" ]]; then
        # Update from source path
        if ! rsync -av --delete "$source_path/" "$target_dir/"; then
            error "Failed to update template from source"
            return 1
        fi
    else
        # Update from default templates
        if [[ "$category" != "custom" ]]; then
            install_default_templates "true"
        else
            error "Source path required for custom template update"
            return 1
        fi
    fi

    success "Template updated successfully: ${category}/${name}"
}

# Validate template compatibility
validate_template_compatibility() {
    local template_dir="$1"
    local target_system="$2"
    
    local compatibility
    compatibility=$(get_template_meta "$template_dir" "compatibility" "[]")
    
    if [[ "$compatibility" == "[]" ]]; then
        # No compatibility restrictions
        return 0
    fi
    
    if echo "$compatibility" | jq -e --arg sys "$target_system" '. | index($sys)' >/dev/null; then
        return 0
    else
        error "Template not compatible with ${target_system}"
        return 1
    fi
}

# Get template variables
get_template_variables() {
    local template_dir="$1"
    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"
    
    if [[ ! -f "$meta_file" ]]; then
        echo "{}"
        return 1
    fi
    
    jq -r '.variables // {}' "$meta_file"
}

# Export functions and variables
export TEMPLATE_BASE_DIR TEMPLATE_BASE_CONFIGS TEMPLATE_FULL_CONFIGS TEMPLATE_DEV_CONFIGS
export TEMPLATE_CUSTOM_DIR TEMPLATE_META_FILE TEMPLATE_SCHEMA_VERSION TEMPLATE_CACHE_DIR
export -f init_template_dirs validate_template_meta get_template_meta resolve_template_deps
export -f check_version_compatibility find_template process_template_variables list_templates
export -f apply_template apply_template_files add_custom_template remove_custom_template
export -f update_template validate_template_compatibility get_template_variables