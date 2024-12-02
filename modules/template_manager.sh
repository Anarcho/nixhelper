#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Template directory structure
TEMPLATE_BASE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nixhelp/templates"
TEMPLATE_CATEGORIES=(
    "base:Core system templates"
    "development:Development environments"
    "editor:Editor configurations"
    "terminal:Terminal emulators"
    "wm:Window managers"
    "shell:Shell configurations"
    "services:System services"
    "theme:Theme configurations"
)

# Template paths
TEMPLATE_PATHS=(
    "${TEMPLATE_BASE_DIR}/base:Base system templates"
    "${TEMPLATE_BASE_DIR}/development:Development environments"
    "${TEMPLATE_BASE_DIR}/applications/editor:Editor configurations"
    "${TEMPLATE_BASE_DIR}/applications/terminal:Terminal emulators"
    "${TEMPLATE_BASE_DIR}/applications/wm:Window managers"
    "${TEMPLATE_BASE_DIR}/applications/shell:Shell configurations"
)

# Template cache and metadata
TEMPLATE_META_FILE="template.json"
TEMPLATE_SCHEMA_VERSION="1.0"
TEMPLATE_CACHE_DIR="${CACHE_DIR}/templates"

# Initialize template system
init_template_system() {
    log "INFO" "Initializing template system..."

    # Create directory structure
    for path_entry in "${TEMPLATE_PATHS[@]}"; do
        local dir="${path_entry%%:*}"
        if ! ensure_directory "$dir"; then
            error "Failed to create template directory: ${dir}"
            return 1
        fi
    done

    # Create cache directory
    ensure_directory "${TEMPLATE_CACHE_DIR}"

    # Initialize template cache
    update_template_cache

    success "Template system initialized"
    return 0
}

# Update template cache
update_template_cache() {
    local cache_file="${TEMPLATE_CACHE_DIR}/template_index.json"
    
    # Create empty cache
    echo "{}" > "$cache_file"

    # Scan for templates
    for path_entry in "${TEMPLATE_PATHS[@]}"; do
        local dir="${path_entry%%:*}"
        local category="${path_entry##*/}"

        find "$dir" -type f -name "${TEMPLATE_META_FILE}" | while read -r meta_file; do
            local template_dir=$(dirname "$meta_file")
            local template_info
            
            if template_info=$(get_template_info "$template_dir"); then
                # Add to cache
                jq --arg cat "$category" --arg dir "$template_dir" \
                   --argjson info "$template_info" \
                   '.[$cat] = (.[$cat] // {}) + {($info.name): $info + {"path": $dir}}' \
                   "$cache_file" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
            fi
        done
    done
}

# Get template information
get_template_info() {
    local template_dir="$1"
    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    # Validate and return metadata
    if validate_template_meta "$meta_file"; then
        cat "$meta_file"
        return 0
    fi

    return 1
}

# Find template
find_template() {
    local category="$1"
    local name="$2"
    local cache_file="${TEMPLATE_CACHE_DIR}/template_index.json"

    if [[ ! -f "$cache_file" ]]; then
        update_template_cache
    fi

    jq -r --arg cat "$category" --arg name "$name" \
        '.[$cat][$name].path // empty' "$cache_file"
}

# List templates by category
list_templates() {
    local category="${1:-all}"
    local cache_file="${TEMPLATE_CACHE_DIR}/template_index.json"

    if [[ ! -f "$cache_file" ]]; then
        update_template_cache
    fi

    case "$category" in
        "all")
            for cat in "${TEMPLATE_CATEGORIES[@]}"; do
                local cat_name="${cat%%:*}"
                local cat_desc="${cat#*:}"
                echo -e "\n${BOLD}${cat_desc}${NC}"
                jq -r --arg cat "$cat_name" \
                    '.[$cat] // {} | to_entries[] | "  \(.key): \(.value.description)"' \
                    "$cache_file"
            done
            ;;
        *)
            if ! is_valid_category "$category"; then
                error "Invalid category: ${category}"
                return 1
            fi
            jq -r --arg cat "$category" \
                '.[$cat] // {} | to_entries[] | "\(.key): \(.value.description)"' \
                "$cache_file"
            ;;
    esac
}

# Check if category is valid
is_valid_category() {
    local category="$1"
    for cat in "${TEMPLATE_CATEGORIES[@]}"; do
        if [[ "${cat%%:*}" == "$category" ]]; then
            return 0
        fi
    done
    return 1
}

# Apply template
apply_template() {
    local category="$1"
    local name="$2"
    local target_dir="$3"
    local variables="${4:-}"

    local template_dir
    template_dir=$(find_template "$category" "$name")

    if [[ -z "$template_dir" ]]; then
        error "Template not found: ${category}/${name}"
        return 1
    fi

    # Ensure target directory exists
    if ! ensure_directory "$target_dir"; then
        error "Failed to create target directory: ${target_dir}"
        return 1
    fi

    # Copy template files
    if ! rsync -a --exclude "${TEMPLATE_META_FILE}" "${template_dir}/" "${target_dir}/"; then
        error "Failed to copy template files"
        return 1
    fi

    # Process template variables if provided
    if [[ -n "$variables" ]]; then
        find "$target_dir" -type f -exec process_template_variables "$template_dir" "$variables" {} \;
    fi

    success "Template applied successfully: ${category}/${name}"
    return 0
}

# Process template variables
process_template_variables() {
    local template_dir="$1"
    local variables="$2"
    local target_file="$3"

    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"
    if [[ ! -f "$meta_file" ]]; then
        return 0
    fi

    # Get template variables
    local template_vars
    template_vars=$(jq -r '.variables // {}' "$meta_file")

    # Process each variable
    echo "$template_vars" | jq -r 'to_entries[] | "\(.key)=\(.value.default // "")"' | \
    while IFS='=' read -r key default; do
        local value="${variables[$key]:-$default}"
        if [[ -n "$value" ]]; then
            sed -i "s|{{${key}}}|${value}|g" "$target_file"
        fi
    done
}

validate_template_meta() {
    local meta_file="$1"
    
    # Basic JSON validation
    if ! jq empty "$meta_file" 2>/dev/null; then
        error "Invalid template metadata JSON: ${meta_file}"
        return 1
    fi

    # Required fields
    local required_fields=(
        "name"
        "version"
        "description"
        "category"
        "type"
        "variables"
        "compatibility"
    )

    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$meta_file" >/dev/null 2>&1; then
            error "Missing required field in template metadata: ${field}"
            return 1
        fi
    done

    return 0
}

# Install template
install_template() {
    local source_path="$1"
    local category="$2"
    local name="$3"
    
    if [[ ! -d "$source_path" ]]; then
        error "Source path not found: ${source_path}"
        return 1
    fi

    local target_dir
    for path_entry in "${TEMPLATE_PATHS[@]}"; do
        if [[ "${path_entry%%:*}" == *"/$category" ]]; then
            target_dir="${path_entry%%:*}/$name"
            break
        fi
    done

    if [[ -z "$target_dir" ]]; then
        error "Invalid category: ${category}"
        return 1
    fi

    # Install template
    if ! rsync -a "$source_path/" "$target_dir/"; then
        error "Failed to install template"
        return 1
    fi

    # Update cache
    update_template_cache

    success "Template installed successfully: ${category}/${name}"
    return 0
}

# Remove template
remove_template() {
    local category="$1"
    local name="$2"
    
    local template_dir
    template_dir=$(find_template "$category" "$name")

    if [[ -z "$template_dir" ]]; then
        error "Template not found: ${category}/${name}"
        return 1
    fi

    if rm -rf "$template_dir"; then
        # Update cache
        update_template_cache
        success "Template removed: ${category}/${name}"
        return 0
    else
        error "Failed to remove template"
        return 1
    fi
}

# Show template info
show_template_info() {
    local category="$1"
    local name="$2"
    
    local template_dir
    template_dir=$(find_template "$category" "$name")

    if [[ -z "$template_dir" ]]; then
        error "Template not found: ${category}/${name}"
        return 1
    fi

    local meta_file="${template_dir}/${TEMPLATE_META_FILE}"
    if [[ ! -f "$meta_file" ]]; then
        error "Template metadata not found"
        return 1
    fi

    echo -e "${BOLD}Template Information:${NC}"
    jq -r '. | to_entries | .[] | "\(.key): \(.value)"' "$meta_file"
}

# Interactive template selection
select_template() {
    local category="$1"
    
    # Show categories if none specified
    if [[ -z "$category" ]]; then
        echo "Select template category:"
        select cat in "${TEMPLATE_CATEGORIES[@]%%:*}" "Cancel"; do
            if [[ "$cat" == "Cancel" ]]; then
                return 1
            elif [[ -n "$cat" ]]; then
                category="$cat"
                break
            fi
        done
    fi

    # List templates in category
    local templates
    templates=$(list_templates "$category")
    if [[ -z "$templates" ]]; then
        error "No templates found in category: ${category}"
        return 1
    fi

    # Show template selection
    echo -e "\nSelect template from ${category}:"
    select template in ${templates%%:*} "Back"; do
        if [[ "$template" == "Back" ]]; then
            return 1
        elif [[ -n "$template" ]]; then
            echo "$template"
            return 0
        fi
    done
}

# Export functions and variables
export TEMPLATE_BASE_DIR TEMPLATE_CATEGORIES TEMPLATE_PATHS
export TEMPLATE_META_FILE TEMPLATE_SCHEMA_VERSION TEMPLATE_CACHE_DIR
export -f init_template_system update_template_cache get_template_info find_template
export -f list_templates is_valid_category apply_template process_template_variables
export -f validate_template_meta install_template remove_template
export -f show_template_info select_template