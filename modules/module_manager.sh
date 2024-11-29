#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

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
    mkdir -p "${module_path}"/{config,lib}

    # Create default.nix based on module type
    case "${module_type}" in
        "nixos")
            cat > "${module_path}/default.nix" <<EOF
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.${category}.${name};
in {
    options.modules.${category}.${name} = {
        enable = mkEnableOption "Enable ${name} module";

        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Module settings for ${name}";
        };
    };

    config = mkIf cfg.enable {
        # Module implementation goes here
    };
}
EOF
            ;;
        "home-manager")
            cat > "${module_path}/default.nix" <<EOF
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.${category}.${name};
in {
    options.modules.${category}.${name} = {
        enable = mkEnableOption "Enable ${name} module";

        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Module settings for ${name}";
        };
    };

    config = mkIf cfg.enable {
        home = {
            # Home-manager specific configuration
        };

        programs = {
            # Program configurations
        };
    };
}
EOF
            ;;
        *)
            error "Invalid module type: ${module_type}"
            return 1
            ;;
    esac

    # Create README.md
    cat > "${module_path}/README.md" <<EOF
# ${name} Module

## Overview

Module Category: ${category}
Type: ${module_type}

## Description
Add module description here.

## Options
- \`enable\`: Enable/disable this module
- \`settings\`: Module-specific settings

## Usage
\`\`\`nix
{
    modules.${category}.${name} = {
        enable = true;
        settings = {
            # Add settings here
        };
    };
}
\`\`\`

## Dependencies

List module dependencies here.

## Example Configuration
\`\`\`nix
{
    modules.${category}.${name} = {
        enable = true;
        settings = {
            # Example settings
        };
    };
}
\`\`\`
EOF

    success "Module created at ${module_path}"
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
                        local name=$(basename "$module")
                        local type="NixOS"

                        # Determine module type
                        if grep -q "home = {" "$module/default.nix" 2>/dev/null; then
                            type="Home Manager"
                        fi

                        echo -e "  - ${name} (${type})"

                        if [[ "$show_details" == "true" && -f "$module/README.md" ]]; then
                            echo "    Description:"
                            sed -n '/^## Description/,/^##/p' "$module/README.md" | \
                                grep -v '^##' | sed 's/^/      /'
                        fi
                    fi
                done
            else
                echo "  No modules found"
            fi
            echo
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

    # Check module structure
    local status=0

    for file in "default.nix" "README.md"; do
        if [[ ! -f "${module_path}/${file}" ]]; then
            error "Missing required file: ${file}"
            status=1
        fi
    done

    # Validate Nix syntax
    if ! nix-instantiate --parse "${module_path}/default.nix" &>/dev/null; then
        error "Invalid Nix syntax in default.nix"
        status=1
    fi

    # Check module usage
    log "INFO" "Checking module usage:"
    grep -r "modules.${category}.${name}.enable" "${REPO_PATH}/hosts" "${REPO_PATH}/home" 2>/dev/null || \
        warning "Module not enabled in any configuration"

    if ((status == 0)); then
        success "Module check passed"
    fi

    return $status
}

# Export functions
export -f create_module enable_module disable_module list_modules check_module
