#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/template_manager.sh"

# Install base templates
install_base_templates() {
    local force="${1:-false}"
    log "INFO" "Installing base templates..."

    # Flake template
    create_template_meta "base/flake" "flake" "Base NixOS Flake Configuration" "1.0.0" "base" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/flake/flake.nix" <<'EOF'
{
  description = "{{description}}";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, ... } @ inputs:
    let
      inherit (self) outputs;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Your custom packages
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      
      # NixOS configurations
      nixosConfigurations = {
        # Host configurations will be added here
      };

      # Home-manager configurations
      homeConfigurations = {
        # User configurations will be added here
      };

      # Custom modules
      nixosModules = {
        # Add your custom modules here
      };
    };
}
EOF

    # NixOS module template
    create_template_meta "base/module/nixos" "default" "Basic NixOS Module Template" "1.0.0" "base" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/module/nixos/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.{{category}}.{{name}};
in {
    options.modules.{{category}}.{{name}} = {
        enable = mkEnableOption "Enable {{name}} module";

        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Module settings for {{name}}";
        };
    };

    config = mkIf cfg.enable {
        # Module implementation goes here
    };
}
EOF

    # Home-manager module template
    create_template_meta "base/module/home-manager" "default" "Basic Home-Manager Module Template" "1.0.0" "base" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/module/home-manager/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.{{category}}.{{name}};
in {
    options.modules.{{category}}.{{name}} = {
        enable = mkEnableOption "Enable {{name}} module";

        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Module settings for {{name}}";
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

    # Module README template
    cat > "${TEMPLATE_BASE_CONFIGS}/module/nixos/README.md" <<'EOF'
# {{name}} Module

## Overview

Module Category: {{category}}
Type: {{type}}

## Description
Add module description here.

## Options
- `enable`: Enable/disable this module
- `settings`: Module-specific settings

## Usage
```nix
{
    modules.{{category}}.{{name}} = {
        enable = true;
        settings = {
            # Add settings here
        };
    };
}
```

## Dependencies

List module dependencies here.

## Example Configuration
```nix
{
    modules.{{category}}.{{name}} = {
        enable = true;
        settings = {
            # Example settings
        };
    };
}
```
EOF

    success "Base templates installed successfully"
}

# Install configuration templates
install_config_templates() {
    local force="${1:-false}"
    log "INFO" "Installing configuration templates..."

    # Neovim configuration template
    create_template_meta "configs/editor/neovim" "default" "Neovim Configuration" "1.0.0" "config" || return 1
    cat > "${TEMPLATE_FULL_CONFIGS}/editor/neovim/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.editor.neovim;
in {
    options.modules.editor.neovim = {
        enable = mkEnableOption "Enable Neovim configuration";

        plugins = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional Neovim plugins";
        };

        extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional Neovim configuration";
        };
    };

    config = mkIf cfg.enable {
        programs.neovim = {
            enable = true;
            viAlias = true;
            vimAlias = true;
            plugins = with pkgs.vimPlugins; [
                # Basic functionality
                vim-surround
                vim-commentary
                vim-fugitive
                vim-gitgutter
                
                # File navigation
                telescope-nvim
                nvim-tree-lua
                
                # LSP support
                nvim-lspconfig
                nvim-cmp
                cmp-nvim-lsp
                
                # Appearance
                gruvbox
                lualine-nvim
                nvim-web-devicons
            ] ++ cfg.plugins;

            extraConfig = ''
                " Basic Settings
                set number
                set relativenumber
                set expandtab
                set tabstop=4
                set shiftwidth=4
                set smartindent
                set termguicolors
                
                " Color scheme
                colorscheme gruvbox
                
                " Key mappings
                let mapleader = " "
                
                " Additional configuration
                ${cfg.extraConfig}
            '';
        };
    };
}
EOF

    success "Configuration templates installed successfully"
}

# Install development environment templates
install_dev_templates() {
    local force="${1:-false}"
    log "INFO" "Installing development templates..."

    # Rust development environment template
    create_template_meta "development/rust" "default" "Rust Development Environment" "1.0.0" "dev" || return 1
    cat > "${TEMPLATE_DEV_CONFIGS}/rust/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.development.rust;
in {
    options.modules.development.rust = {
        enable = mkEnableOption "Enable Rust development environment";

        extraPackages = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional Rust development packages";
        };
    };

    config = mkIf cfg.enable {
        home.packages = with pkgs; [
            # Core Rust tools
            rustc
            cargo
            rust-analyzer
            rustfmt
            clippy

            # Build tools
            gcc
            gnumake
            pkg-config

            # Additional tools
            cargo-edit
            cargo-watch
            cargo-audit
        ] ++ cfg.extraPackages;
    };
}
EOF

    success "Development templates installed successfully"
}

# Create template metadata
create_template_meta() {
    local path="$1"
    local name="$2"
    local description="$3"
    local version="$4"
    local type="$5"
    
    local target_dir="${TEMPLATE_BASE_DIR}/${path}"

    if ! ensure_directory "$target_dir"; then
        error "Failed to create template directory: ${target_dir}"
        return 1
    fi

    cat > "${target_dir}/${TEMPLATE_META_FILE}" <<EOF
{
    "name": "${name}",
    "version": "${version}",
    "description": "${description}",
    "category": "${path}",
    "type": "${type}",
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Main installation function
install_default_templates() {
    local force="${1:-false}"
    
    log "INFO" "Installing default templates..."

    # Initialize template directories
    if ! init_template_dirs; then
        error "Failed to initialize template directories"
        return 1
    fi

    install_base_templates "$force" || return 1
    install_config_templates "$force" || return 1
    install_dev_templates "$force" || return 1

    success "Default templates installed successfully"
}

# Export functions
export -f create_template_meta
export -f install_default_templates install_base_templates
export -f install_config_templates install_dev_templates