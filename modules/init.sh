#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"
source "$(dirname "${BASH_SOURCE[0]}")/host_manager.sh"
source "$(dirname "${BASH_SOURCE[0]}")/template_manager.sh"

# Repository Initialization
init_repository() {
    local target_path="$1"
    local absolute_path

    # Get absolute path
    if [ -z "$target_path" ]; then
        absolute_path="$(pwd)"
    else
        absolute_path="$(realpath "$target_path")"
    fi

    log "INFO" "Initializing NixOS configuration repository at ${absolute_path}"

    # Check if directory exists and is not empty
    if [[ -d "${absolute_path}" && -n "$(ls -A "${absolute_path}" 2>/dev/null)" ]]; then
        if ! confirm_action "Directory exists and is not empty. Continue?"; then
            log "INFO" "Initialization cancelled"
            return 0
        fi
    fi

    # Create the directory structure
    mkdir -p "${absolute_path}"/{hosts/common,modules/{core,desktop,apps,development,editor,theme,services},home,secrets,overlays,lib}

    # Change to the target directory
    cd "${absolute_path}" || {
        error "Failed to change to directory: ${absolute_path}"
        return 1
    }

    # Set REPO_PATH dynamically
    export REPO_PATH="${absolute_path}"
    log "INFO" "Set REPO_PATH to ${REPO_PATH}"

    # Create initial flake.nix
    cat > "${absolute_path}/flake.nix" <<'EOF'
{
  description = "NixOS Configuration";

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
        # Add your host configurations here
      };

      # Home-manager configurations
      homeConfigurations = {
        # Add your home-manager configurations here
      };

      # Custom modules
      nixosModules = {
        # Add your custom modules here
      };
    };
}
EOF

    # Create common NixOS configuration
    cat > "${absolute_path}/hosts/common/default.nix" <<'EOF'
{ lib, inputs, ... }: {
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;
}
EOF

    # Create home-manager base configuration
    cat > "${absolute_path}/home/default.nix" <<'EOF'
{ config, lib, pkgs, ... }: {
  programs.home-manager.enable = true;
  
  # Default home configuration
  home = {
    stateVersion = "24.05";
    
    # Basic packages for all users
    packages = with pkgs; [
      git
      vim
      curl
      wget
    ];
  };
}
EOF


    # Create README
    cat > "${absolute_path}/README.md" <<'EOF'
# NixOS Configuration

This repository contains NixOS system configurations managed through Nix Flakes.

## Structure


- `flake.nix`: Main flake configuration
- `hosts/`: Host-specific configurations
  - `common/`: Shared configurations
  - `desktop/`: Desktop configurations
  - `vm/`: Virtual machine configurations
  - `wsl/`: Windows Subsystem for Linux configurations
- `modules/`: Reusable NixOS modules
  - `core/`: Core system modules
  - `desktop/`: Desktop environment modules
  - `apps/`: Application configurations

  - `development/`: Development environments
  - `editor/`: Editor configurations
  - `theme/`: Theme configurations
  - `services/`: Service configurations
- `home/`: Home-manager configurations

- `secrets/`: Secret management (gitignored)
- `overlays/`: Nixpkgs overlays
- `lib/`: Custom Nix functions

## Usage

To build and apply configuration:


```bash
# For NixOS systems
nixos-rebuild switch --flake .#hostname

# For home-manager
home-manager switch --flake .#username@hostname
```

## Adding a New Host

1. Create a new host directory in `hosts/`
2. Add host configuration
3. Add host to `flake.nix`
4. Generate hardware configuration if needed
5. Build and deploy

## Managing Home Configurations


1. Create user configuration in `home/`
2. Add user to `flake.nix` under `homeConfigurations`
3. Build and deploy using home-manager
EOF

    # Create .gitignore
    cat > "${absolute_path}/.gitignore" <<'EOF'
result
result-*
.direnv
.envrc

*.swp
.DS_Store
/secrets/
EOF

    # Initialize git repository if available
    git_init "${absolute_path}"

    log "SUCCESS" "Repository initialized at ${absolute_path}"

    # Apply base configuration
    if ! apply_template "base" "flake" "$REPO_PATH"; then
        error "Failed to apply base configuration"
        return 1
    fi
    
    if ! apply_template "base" "host" "$REPO_PATH/hosts/common"; then
        error "Failed to apply host configuration"
        return 1
    fi

    # Interactive steps for additional configuration
    create_multiple_hosts
    configure_optional_modules
}

# Interactive Host Creation
create_multiple_hosts() {
    echo "Starting multiple host creation process..."

    while true; do
        echo "Let's configure a new host!"

        # Prompt for host name
        read -p "Enter the host name (or type 'done' to finish): " host_name
        if [[ "$host_name" == "done" ]]; then
            echo "Finished host creation process."
            break
        fi

        if [[ -z "$host_name" ]]; then
            echo "Host name cannot be empty!"
            continue
        fi

        # Prompt for host type
        echo "Select the host type:"
        select host_type in "desktop" "minimal" "server" "vm" "wsl"; do
            if [[ -n "$host_type" ]]; then
                break
            else
                echo "Invalid selection. Please choose a valid host type."
            fi
        done

        # Get VM details if it's a VM host
        local ip_address username port
        if [[ "$host_type" == "vm" ]]; then
            read -p "Enter the VM username: " username
            read -p "Enter the VM IP address: " ip_address
            read -p "Enter the SSH port (default: 22): " port
            port=${port:-22}

            # Store VM configuration
            set_vm_config "$host_name" "USER" "$username"
            set_vm_config "$host_name" "IP" "$ip_address"
            set_vm_config "$host_name" "PORT" "$port"
        fi

        # Create the host
        log "INFO" "Creating host: $host_name (type: $host_type)"
        if ! create_host "$host_name" "$host_type"; then
            error "Failed to create host: $host_name"
            continue
        fi

        # Configure SSH if it's a VM
        if [[ "$host_type" == "vm" ]]; then
            log "INFO" "Setting up SSH for host: $host_name"
            setup_ssh_keys "$host_name" "$username" "$port" "$ip_address"
        fi

        echo "Host '$host_name' created successfully!"
    done
}


# Dynamic Template/Module Configuration
configure_optional_modules() {
    log "INFO" "Configuring optional modules..."

    # Install templates if not available
    if ! list_templates &>/dev/null; then
        log "INFO" "Installing default templates..."
        if ! install_default_templates; then
            error "Failed to install default templates"
            return 1
        fi
    fi

    while true; do
        echo -e "\nSelect configuration type:"
        select category in "Development Environment" "Applications" "Done"; do
            case "$category" in
                "Development Environment")
                    configure_dev_environment
                    break
                    ;;
                "Applications")
                    configure_applications
                    break
                    ;;
                "Done")
                    return 0
                    ;;
                *)
                    echo "Invalid selection. Please choose a valid option."
                    ;;
            esac
        done
    done
}

configure_base_templates() {
    # Apply base flake template automatically
    log "INFO" "Applying base flake configuration..."
    # Changed from "base/flake" to "flake"
    apply_template "base" "flake" "$REPO_PATH" || return 1

    # Offer host template configuration
    if confirm_action "Would you like to configure host templates?"; then
        # Changed from "base/host" to "host"
        apply_template "base" "host" "$REPO_PATH/hosts/common" || return 1
    fi
}

configure_dev_environment() {
    echo -e "\nSelect development environment:"
    select env in "Rust" "Python" "Node.js" "Back"; do
        case "$env" in
            "Rust"|"Python"|"Node.js")
                local template_name="${env,,}"
                template_name=${template_name//.}  # Remove dots for Node.js
                # Make sure we're using the correct development path
                if apply_template "development" "$template_name" "$REPO_PATH/modules/development/${template_name}"; then
                    success "Development environment ${env} configured"
                fi
                break
                ;;
            "Back")
                return 0
                ;;
            *)
                echo "Invalid selection. Please choose a valid option."
                ;;
        esac
    done
}

configure_app_category() {
    local category="$1"
    echo -e "\nSelect ${category} configuration:"

    # Changed path construction
    local templates
    templates=$(list_templates "$category")
    
    if [[ -z "$templates" ]]; then
        warning "No ${category} templates available."
        return 1
    fi

    select template in ${templates} "Back"; do
        case "$template" in
            "Back")
                return 0
                ;;
            *)
                if [[ -n "$template" ]]; then
                    # Updated path construction
                    if apply_template "$category" "$template" "$REPO_PATH/modules/${category}/${template}"; then
                        success "${category^} ${template} configured"
                    fi
                fi
                break
                ;;
        esac
    done
}

# Export Functions
export -f init_repository create_multiple_hosts configure_optional_modules