#!/usr/bin/env bash

# Load helper scripts
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/template_manager.sh"

# Directory constants
readonly TEMPLATE_DIR="${TEMPLATE_BASE_DIR}"
readonly BASE_TEMPLATES="${TEMPLATE_DIR}/base"
readonly DEV_TEMPLATES="${TEMPLATE_DIR}/development"
readonly APP_TEMPLATES="${TEMPLATE_DIR}/applications"


# Install base templates
install_base_templates() {
    local force="${1:-false}"
    log "INFO" "Installing base templates..."

    # Flake template
    create_template_meta "base/flake" "flake" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/flake/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "flake",
    "version": "1.0.0",
    "description": "Base NixOS Flake Configuration",
    "category": "base",
    "type": "nix",
    "dependencies": [],
    "variables": {
        "description": {
            "type": "string",
            "description": "Flake description",
            "default": "NixOS Configuration"
        }
    },
    "compatibility": ["nixos", "darwin"]
}
EOF

    # Create flake.nix template
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
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      nixosConfigurations = {
        # Host configurations will be added here
      };
      homeConfigurations = {
        # User configurations will be added here
      };
    };
}
EOF

    # Base NixOS module template
    create_template_meta "base/module/nixos" "default" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/module/nixos/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "default",
    "version": "1.0.0",
    "description": "Basic NixOS Module Template",
    "category": "base/module",
    "type": "nixos",
    "dependencies": [],
    "variables": {
        "category": {
            "type": "string",
            "description": "Module category",
            "default": ""
        },
        "name": {
            "type": "string",
            "description": "Module name",
            "default": ""
        }
    },
    "compatibility": ["nixos"]
}
EOF

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

    # Base home-manager module template
    create_template_meta "base/module/home-manager" "default" || return 1
    cat > "${TEMPLATE_BASE_CONFIGS}/module/home-manager/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "default",
    "version": "1.0.0",
    "description": "Basic Home-Manager Module Template",
    "category": "base/module",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "category": {
            "type": "string",
            "description": "Module category",
            "default": ""
        },
        "name": {
            "type": "string",
            "description": "Module name",
            "default": ""
        }
    },
    "compatibility": ["nixos", "darwin"]
}
EOF

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

    success "Base templates installed successfully"
    return 0
}

# Install configuration templates
install_config_templates() {
    local force="${1:-false}"
    log "INFO" "Installing configuration templates..."

    # Vim configuration
    create_template_meta "configs/editor/vim" "vim" || return 1
    cat > "${TEMPLATE_FULL_CONFIGS}/editor/vim/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "vim",
    "version": "1.0.0",
    "description": "Vim editor configuration with sensible defaults",
    "category": "editor",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "extraPlugins": {
            "type": "array",
            "description": "Additional vim plugins to install",
            "default": []
        },
        "extraConfig": {
            "type": "string",
            "description": "Additional vim configuration",
            "default": ""
        }
    },
    "compatibility": ["nixos", "linux", "darwin"]
}
EOF

    cat > "${TEMPLATE_FULL_CONFIGS}/editor/vim/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.editor.vim;
in {
    options.modules.editor.vim = {
        enable = mkEnableOption "Enable vim configuration";
        plugins = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional vim plugins";
        };
        extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional vim configuration";
        };
        defaultPlugins = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable default plugins";
        };
    };

    config = mkIf cfg.enable {
        programs.vim = {
            enable = true;
            defaultEditor = true;

            plugins = with pkgs.vimPlugins; (if cfg.defaultPlugins then [
                ctrlp-vim
                nerdtree
                vim-gitgutter
                vim-fugitive
                vim-airline
                vim-surround
                vim-commentary
                gruvbox
                vim-nix
            ] else []) ++ cfg.plugins;

            extraConfig = ''
                " Basic Settings
                set nocompatible
                set number
                set relativenumber
                set expandtab
                set shiftwidth=4
                set tabstop=4
                set autoindent
                set mouse=a
                set clipboard=unnamedplus

                " Color scheme
                set background=dark
                colorscheme gruvbox

                " Key mappings
                let mapleader = " "
                nnoremap <leader>n :NERDTreeToggle<CR>

                ${cfg.extraConfig}
            '';
        };
    };
}
EOF

# Kitty terminal configuration
    create_template_meta "configs/terminal/kitty" "kitty" || return 1
    cat > "${TEMPLATE_FULL_CONFIGS}/terminal/kitty/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "kitty",
    "version": "1.0.0",
    "description": "Kitty terminal configuration with sensible defaults",
    "category": "terminal",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "font": {
            "type": "object",
            "description": "Font configuration",
            "default": {
                "name": "JetBrains Mono",
                "size": 12
            }
        },
        "extraConfig": {
            "type": "string",
            "description": "Additional kitty configuration",
            "default": ""
        }
    },
    "compatibility": ["nixos", "linux", "darwin"]
}
EOF

    cat > "${TEMPLATE_FULL_CONFIGS}/terminal/kitty/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.terminal.kitty;
in {
    options.modules.terminal.kitty = {
        enable = mkEnableOption "Enable kitty terminal";
        font = {
            name = mkOption {
                type = types.str;
                default = "JetBrains Mono";
                description = "Font name";
            };
            size = mkOption {
                type = types.int;
                default = 12;
                description = "Font size";
            };
        };
        theme = mkOption {
            type = types.str;
            default = "Gruvbox Dark";
            description = "Color theme";
        };
        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Additional kitty settings";
        };
        extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional kitty configuration";
        };
    };

    config = mkIf cfg.enable {
        programs.kitty = {
            enable = true;
            font = {
                name = cfg.font.name;
                size = cfg.font.size;
            };
            settings = {
                scrollback_lines = 10000;
                enable_audio_bell = false;
                update_check_interval = 0;
                cursor_shape = "block";
                cursor_blink_interval = 0;
                window_padding_width = 4;
            } // cfg.settings;
            extraConfig = ''
                # Keyboard shortcuts
                map ctrl+shift+c copy_to_clipboard
                map ctrl+shift+v paste_from_clipboard
                map ctrl+shift+enter new_window
                map ctrl+shift+t new_tab
                map ctrl+shift+q close_tab
                map ctrl+shift+l next_tab
                map ctrl+shift+h previous_tab

                ${cfg.extraConfig}
            '';
        };
    };
}
EOF

    # Sway configuration
    create_template_meta "configs/wm/sway" "sway" || return 1
    cat > "${TEMPLATE_FULL_CONFIGS}/wm/sway/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "sway",
    "version": "1.0.0",
    "description": "Sway window manager configuration with sensible defaults",
    "category": "wm",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "terminal": {
            "type": "string",
            "description": "Default terminal emulator",
            "default": "kitty"
        },
        "extraConfig": {
            "type": "string",
            "description": "Additional sway configuration",
            "default": ""
        }
    },
    "compatibility": ["nixos", "linux"]
}
EOF

    cat > "${TEMPLATE_FULL_CONFIGS}/wm/sway/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.wm.sway;
in {
    options.modules.wm.sway = {
        enable = mkEnableOption "Enable Sway window manager";
        extraPackages = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional packages for Sway";
        };
        settings = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "Additional Sway settings";
        };
        extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional Sway configuration";
        };
    };

    config = mkIf cfg.enable {
        programs.sway = {
            enable = true;
            wrapperFeatures.gtk = true;
            extraPackages = with pkgs; [
                swaylock
                swayidle
                waybar
                wofi
                mako
                grim
                slurp
                wl-clipboard
            ] ++ cfg.extraPackages;
        };

        home.packages = with pkgs; [
            # Additional tools
            pamixer
            brightnessctl
            playerctl
        ];

        wayland.windowManager.sway = {
            enable = true;
            config = {
                modifier = "Mod4";
                terminal = "kitty";
                menu = "wofi --show drun";
                bars = [{
                    command = "waybar";
                }];
            } // cfg.settings;
            extraConfig = ''
                # Basic key bindings
                bindsym XF86AudioRaiseVolume exec pamixer -i 5
                bindsym XF86AudioLowerVolume exec pamixer -d 5
                bindsym XF86AudioMute exec pamixer -t
                bindsym XF86MonBrightnessDown exec brightnessctl set 5%-
                bindsym XF86MonBrightnessUp exec brightnessctl set +5%

                ${cfg.extraConfig}
            '';
        };
    };
}
EOF

    # Zsh configuration
    create_template_meta "configs/shell/zsh" "zsh" || return 1
    cat > "${TEMPLATE_FULL_CONFIGS}/shell/zsh/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "zsh",
    "version": "1.0.0",
    "description": "Zsh shell configuration with sensible defaults",
    "category": "shell",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "enableDefaultPlugins": {
            "type": "boolean",
            "description": "Enable default plugins",
            "default": true
        },
        "extraConfig": {
            "type": "string",
            "description": "Additional zsh configuration",
            "default": ""
        }
    },
    "compatibility": ["nixos", "linux", "darwin"]
}
EOF

    cat > "${TEMPLATE_FULL_CONFIGS}/shell/zsh/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

with lib;
let
    cfg = config.modules.shell.zsh;
in {
    options.modules.shell.zsh = {
        enable = mkEnableOption "Enable Zsh configuration";
        defaultPlugins = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable default plugins";
        };
        extraPlugins = mkOption {
            type = types.listOf types.package;
            default = [];
            description = "Additional Zsh plugins";
        };
        extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional Zsh configuration";
        };
    };

    config = mkIf cfg.enable {
        programs.zsh = {
            enable = true;
            autocd = true;
            enableAutosuggestions = true;
            enableCompletion = true;
            syntaxHighlighting.enable = true;

            plugins = (if cfg.defaultPlugins then [
                {
                    name = "zsh-nix-shell";
                    file = "nix-shell.plugin.zsh";
                    src = pkgs.fetchFromGitHub {
                        owner = "chisui";
                        repo = "zsh-nix-shell";
                        rev = "v0.5.0";
                        sha256 = "0za4aiwwrlawnia4f29msk822rj9bgcygw6a8a6iikiwzjjz0g91";
                    };
                }
            ] else []) ++ cfg.extraPlugins;

            initExtra = ''
                # Basic settings
                HISTFILE=~/.zsh_history
                HISTSIZE=10000
                SAVEHIST=10000
                setopt appendhistory
                setopt share_history
                setopt hist_ignore_all_dups
                setopt hist_ignore_space
                setopt autocd
                setopt extendedglob
                unsetopt beep

                # Key bindings
                bindkey "^[[1;5C" forward-word
                bindkey "^[[1;5D" backward-word
                bindkey "^[[H" beginning-of-line
                bindkey "^[[F" end-of-line
                bindkey "^[[3~" delete-char

                ${cfg.extraConfig}
            '';
        };
    };
}
EOF

    success "Configuration templates installed successfully"
    return 0
}

# Main installation function
install_default_templates() {
    local force="${1:-false}"
    log "INFO" "Installing default templates..."

    # Initialize template system
    if ! init_template_system; then
        error "Failed to initialize template system"
        return 1
    fi

    # Install templates by category
    install_base_templates "$force" || return 1
    install_development_templates "$force" || return 1
    install_application_templates "$force" || return 1

    success "Default templates installed successfully"
    return 0
}

# Create template metadata
create_template_meta() {
    local path="$1"
    local name="$2"
    local target_dir="${TEMPLATE_BASE_DIR}/${path}"

    if ! ensure_directory "$target_dir"; then
        error "Failed to create template directory: ${target_dir}"
        return 1
    fi

    return 0
}

create_dev_template() {
    local name="$1"
    local description="$2"
    local template_dir="${DEV_TEMPLATES}/${name}"

    ensure_directory "$template_dir" || return 1
    cat > "${template_dir}/template.json" <<EOF
{
    "schemaVersion": "1.0",
    "name": "${name}",
    "version": "1.0.0",
    "description": "${description}",
    "category": "development",
    "type": "home-manager",
    "variables": {},
    "compatibility": ["nixos", "darwin"]
}
EOF

    return 0
}


i
install_application_templates() {
    local force="${1:-false}"
    log "INFO" "Installing application templates..."

    # Create application categories
    ensure_directory "${APP_TEMPLATES}/editor"
    ensure_directory "${APP_TEMPLATES}/terminal"
    ensure_directory "${APP_TEMPLATES}/wm"
    ensure_directory "${APP_TEMPLATES}/shell"

    # Install editor templates
    create_app_template "editor/neovim" "Neovim Editor Configuration" || return 1
    create_app_template "editor/vim" "Vim Editor Configuration" || return 1

    # Install terminal templates
    create_app_template "terminal/kitty" "Kitty Terminal Configuration" || return 1
    create_app_template "terminal/alacritty" "Alacritty Terminal Configuration" || return 1

    # Install window manager templates
    create_app_template "wm/sway" "Sway Window Manager Configuration" || return 1
    create_app_template "wm/hyprland" "Hyprland Window Manager Configuration" || return 1

    # Install shell templates
    create_app_template "shell/zsh" "Zsh Shell Configuration" || return 1
    create_app_template "shell/fish" "Fish Shell Configuration" || return 1

    success "Application templates installed successfully"
    return 0
}




install_base_templates() {
    local force="${1:-false}"
    log "INFO" "Installing base templates..."

    # Install flake template
    install_flake_template || return 1

    # Install module templates
    install_module_templates || return 1

    # Install host templates
    install_host_templates || return 1

    success "Base templates installed successfully"
    return 0
}

install_flake_template() {
    # Create flake template directory and metadata
    create_base_template "flake" "Base NixOS Flake Configuration" || return 1

    # Create template files
    cat > "${BASE_TEMPLATES}/flake/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "flake",
    "version": "1.0.0",
    "description": "Base NixOS Flake Configuration",
    "category": "base",
    "type": "nix",
    "dependencies": [],
    "variables": {
        "description": {
            "type": "string",
            "description": "Flake description",
            "default": "NixOS Configuration"
        }
    },
    "compatibility": ["nixos", "darwin"]
}
EOF

    cat > "${BASE_TEMPLATES}/flake/flake.nix" <<'EOF'
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
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      nixosConfigurations = {
        # Host configurations will be added here
      };
      homeConfigurations = {
        # User configurations will be added here
      };
    };
}
EOF

    return 0
}

install_module_templates() {
    # Install NixOS module template
    create_base_template "modules/nixos" "NixOS Module Template" || return 1
    cat > "${BASE_TEMPLATES}/modules/nixos/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "nixos-module",
    "version": "1.0.0",
    "description": "Basic NixOS Module Template",
    "category": "base",
    "type": "nixos",
    "dependencies": [],
    "variables": {
        "category": {
            "type": "string",
            "description": "Module category",
            "default": ""
        },
        "name": {
            "type": "string",
            "description": "Module name",
            "default": ""
        }
    },
    "compatibility": ["nixos"]
}
EOF

    cat > "${BASE_TEMPLATES}/modules/nixos/default.nix" <<'EOF'
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

    # Install home-manager module template
    create_base_template "modules/home-manager" "Home Manager Module Template" || return 1
    cat > "${BASE_TEMPLATES}/modules/home-manager/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "home-manager-module",
    "version": "1.0.0",
    "description": "Basic Home-Manager Module Template",
    "category": "base",
    "type": "home-manager",
    "dependencies": [],
    "variables": {
        "category": {
            "type": "string",
            "description": "Module category",
            "default": ""
        },
        "name": {
            "type": "string",
            "description": "Module name",
            "default": ""
        }
    },
    "compatibility": ["nixos", "darwin"]
}
EOF

    cat > "${BASE_TEMPLATES}/modules/home-manager/default.nix" <<'EOF'
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

    return 0
}

install_host_templates() {
    # Create host configuration template
    create_base_template "host" "NixOS Host Configuration" || return 1
    cat > "${BASE_TEMPLATES}/host/template.json" <<'EOF'
{
    "schemaVersion": "1.0",
    "name": "host",
    "version": "1.0.0",
    "description": "NixOS Host Configuration",
    "category": "base",
    "type": "nixos",
    "variables": {
        "hostname": {
            "type": "string",
            "description": "Host name",
            "default": "nixos"
        },
        "username": {
            "type": "string",
            "description": "Primary user name",
            "default": "nixos"
        },
        "timezone": {
            "type": "string",
            "description": "System timezone",
            "default": "UTC"
        }
    },
    "compatibility": ["nixos"]
}
EOF

    cat > "${BASE_TEMPLATES}/host/configuration.nix" <<'EOF'
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "{{hostname}}";
  time.timeZone = "{{timezone}}";

  users.users.{{username}} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    vim
  ];

  system.stateVersion = "24.05";
}
EOF

    return 0
}

install_development_templates() {
    local force="${1:-false}"
    log "INFO" "Installing development templates..."

    # Install Rust template
    create_dev_template "rust" "Rust Development Environment" || return 1
    create_rust_template || return 1

    # Install Python template
    create_dev_template "python" "Python Development Environment" || return 1
    create_python_template || return 1

    # Install Node.js template
    create_dev_template "node" "Node.js Development Environment" || return 1
    create_node_template || return 1

    success "Development templates installed successfully"
    return 0
}

create_rust_template() {
    cat > "${DEV_TEMPLATES}/rust/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
  ];

  home.file.".cargo/config.toml".text = ''
    [target.{{target_triple}}]
    linker = "{{linker}}"
  '';
}
EOF
    return 0
}

create_python_template() {
    cat > "${DEV_TEMPLATES}/python/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    python3
    python3Packages.pip
    python3Packages.black
    python3Packages.pylint
    python3Packages.pytest
  ];

  home.file.".config/pip/pip.conf".text = ''
    [global]
    index-url = {{pip_index}}
  '';
}
EOF
    return 0
}

create_node_template() {
    cat > "${DEV_TEMPLATES}/node/default.nix" <<'EOF'
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    nodejs
    nodePackages.npm
    nodePackages.yarn
  ];

  home.file.".npmrc".text = ''
    prefix = {{npm_prefix}}
    registry = {{npm_registry}}
  '';
}
EOF
    return 0
}

create_base_template() {
    local name="$1"
    local description="$2"
    local template_dir="${BASE_TEMPLATES}/${name}"

    ensure_directory "$template_dir" || return 1
    return 0
}

create_dev_template() {
    local name="$1"
    local description="$2"
    local template_dir="${DEV_TEMPLATES}/${name}"

    ensure_directory "$template_dir" || return 1
    cat > "${template_dir}/template.json" <<EOF
{
    "schemaVersion": "1.0",
    "name": "${name}",
    "version": "1.0.0",
    "description": "${description}",
    "category": "development",
    "type": "home-manager",
    "variables": {},
    "compatibility": ["nixos", "darwin"]
}
EOF

    return 0
}

create_app_template() {
    local path="$1"
    local description="$2"
    local name=$(basename "$path")
    local category=$(dirname "$path")
    local template_dir="${APP_TEMPLATES}/${path}"

    ensure_directory "$template_dir" || return 1
    cat > "${template_dir}/template.json" <<EOF
{
    "schemaVersion": "1.0",
    "name": "${name}",
    "version": "1.0.0",
    "description": "${description}",
    "category": "${category}",
    "type": "home-manager",
    "variables": {},
    "compatibility": ["nixos", "darwin"]
}
EOF

    return 0
}

# Export functions
export -f install_default_templates install_base_templates
export -f install_development_templates install_application_templates
export -f create_base_template create_dev_template create_app_template