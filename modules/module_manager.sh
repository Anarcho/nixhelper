#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/template_manager.sh"

create_module() {
    local category="$1"
    local name="$2"
    local module_type="${3:-nixos}"  # nixos or home-manager
    local module_path="${REPO_PATH}/modules/${category}/${name}"

    # Validate category
    if [[ ! "${MODULE_CATEGORIES[$category]+isset}" ]]; then
        error "Invalid module category: ${category}"
        info "Available categories: ${!MODULE_CATEGORIES[*]}"
        return 1
    fi

    log "INFO" "Creating ${module_type} module: ${category}/${name}"

    # Create module directory structure
    mkdir -p "${module_path}"/{config,lib} || {
        error "Failed to create module directory structure"
        return 1
    }

    # Prepare template variables
    local template_vars
    template_vars=$(cat <<EOF
{
    "category": "${category}",
    "name": "${name}",
    "description": "${MODULE_CATEGORIES[$category]} module for ${name}"
}
EOF
)

    # Select and apply appropriate template
    local template_category="base/module"
    local template_name="${module_type}"
    if ! apply_template "$template_category" "$template_name" "$module_path" "$template_vars"; then
        error "Failed to apply module template"
        rm -rf "${module_path}"
        return 1
    fi

    # Additional module-specific setup
    case "${category}" in
        "development")
            if [[ -f "${module_path}/default.nix" ]]; then
                local dev_template_category="development"
                local dev_template_name="${name}"
                if apply_template "$dev_template_category" "$dev_template_name" "${module_path}/config" "$template_vars" 2>/dev/null; then
                    log "INFO" "Applied development-specific template for ${name}"
                fi
            fi
            ;;
        "editor")
            if [[ -f "${module_path}/default.nix" ]]; then
                local editor_template_category="configs/editor"
                local editor_template_name="${name}"
                if apply_template "$editor_template_category" "$editor_template_name" "${module_path}/config" "$template_vars" 2>/dev/null; then
                    log "INFO" "Applied editor-specific template for ${name}"
                fi
            fi
            ;;
        *)
            local custom_template_category="configs/${category}"
            local custom_template_name="${name}"
            if apply_template "$custom_template_category" "$custom_template_name" "${module_path}/config" "$template_vars" 2>/dev/null; then
                log "INFO" "Applied category-specific template for ${name}"
            fi
            ;;
    esac

    # Add module to flake.nix if it's a NixOS module
    if [[ "${module_type}" == "nixos" ]]; then
        add_module_to_flake "${category}" "${name}"
    fi

    success "Module created at ${module_path}"
}

add_module_to_flake() {
    local category="$1"
    local name="$2"
    local flake_path="${REPO_PATH}/flake.nix"

    if [[ ! -f "${flake_path}" ]]; then
        error "flake.nix not found in ${REPO_PATH}"
        return 1
    fi

    # Check if module is already in flake.nix
    if grep -q "modules.${category}.${name}" "${flake_path}"; then
        log "INFO" "Module already exists in flake.nix"
        return 0
    fi

    # Add module to nixosModules section
    local insert_line
    insert_line=$(grep -n "nixosModules = {" "${flake_path}" | cut -d: -f1)

    if [[ -n "${insert_line}" ]]; then
        sed -i "${insert_line}a\\        ${category}-${name} = ./modules/${category}/${name};" "${flake_path}"
        log "SUCCESS" "Added module to flake.nix"
    else
        warning "Could not find nixosModules section in flake.nix"
    fi
}

enable_module() {
    local category="$1"
    local name="$2"
    local target="$3"  # host name or user@host for home-manager
    local module_path="${REPO_PATH}/modules/${category}/${name}"

    if [[ ! -d "$module_path" ]]; then
        error "Module not found: ${category}/${name}"
        return 1
    fi

    if [[ "$target" =~ "@" ]]; then
        # Home-manager configuration
        local user="${target%@*}"
        local host="${target#*@}"
        local config_path="${REPO_PATH}/home/${user}/default.nix"
    else
        # NixOS configuration
        local host="$target"
        local config_path="${REPO_PATH}/hosts/${host}/default.nix"
    fi

    if [[ ! -f "$config_path" ]]; then
        error "Configuration not found: ${config_path}"
        return 1
    fi

    # Add module to imports if not already present
    if ! grep -q "modules/${category}/${name}" "$config_path"; then
        sed -i "/imports = \[/a \    ../../modules/${category}/${name}" "$config_path"
    fi

    # Enable module
    if ! grep -q "modules.${category}.${name}.enable" "$config_path"; then
        sed -i "/^{/a \  modules.${category}.${name}.enable = true;" "$config_path"
        success "Enabled module ${category}/${name} for ${target}"
    else
        warning "Module already enabled for ${target}"
    fi

    # Apply any template-specific activation steps
    local template_meta="${module_path}/template.json"
    if [[ -f "$template_meta" ]]; then
        local activation_script="${module_path}/activate.sh"
        if [[ -f "$activation_script" ]]; then
            log "INFO" "Running template activation script"
            bash "$activation_script" "$target"
        fi
    fi
}

disable_module() {
    local category="$1"
    local name="$2"
    local target="$3"

    if [[ "$target" =~ "@" ]]; then
        local user="${target%@*}"
        local host="${target#*@}"
        local config_path="${REPO_PATH}/home/${user}/default.nix"
    else
        local host="$target"
        local config_path="${REPO_PATH}/hosts/${host}/default.nix"
    fi

    if [[ ! -f "$config_path" ]]; then
        error "Configuration not found: ${config_path}"
        return 1
    fi

    # Remove module import
    sed -i "\#modules/${category}/${name}#d" "$config_path"

    # Disable module
    sed -i "/modules.${category}.${name}.enable/d" "$config_path"

    success "Disabled module ${category}/${name} for ${target}"
}

list_modules() {
    local category="$1"
    local show_details="${2:-false}"

    log "INFO" "Available modules:"
    echo

    for cat in "${!MODULE_CATEGORIES[@]}"; do
        if [[ -z "$category" || "$category" == "$cat" ]]; then
            echo -e "${BOLD}${cat}${NC} - ${MODULE_CATEGORIES[$cat]}"

            if [[ -d "${REPO_PATH}/modules/${cat}" ]]; then
                for module in "${REPO_PATH}/modules/${cat}"/*; do
                    if [[ -d "$module" ]]; then
                        local name
                        name=$(basename "$module")
                        local type="NixOS"
                        local template_info=""

                        # Determine module type and get template info
                        if grep -q "home = {" "$module/default.nix" 2>/dev/null; then
                            type="Home Manager"
                        fi

                        if [[ -f "${module}/template.json" ]]; then
                            template_info=" (Template-based)"
                        fi

                        echo -e "  - ${name} (${type})${template_info}"
                    fi
                done
            else
                echo "  No modules found"
            fi
        fi
    done
}

check_module() {
    local category="$1"
    local name="$2"
    local module_path="${REPO_PATH}/modules/${category}/${name}"

    if [[ ! -d "$module_path" ]]; then
        error "Module not found: ${category}/${name}"
        return 1
    fi

    log "INFO" "Checking module: ${category}/${name}"

    # Validate module structure
    for file in "default.nix" "README.md"; do
        if [[ ! -f "${module_path}/${file}" ]]; then
            error "Missing required file: ${file}"
        fi
    done

    success "Module check passed"
}

# Export functions
export -f create_module enable_module disable_module list_modules check_module add_module_to_flake
