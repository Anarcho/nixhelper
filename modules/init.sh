#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"

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

    # Create directory structure
    mkdir -p "${absolute_path}"/{hosts/common,modules/{core,desktop,apps,development,editor,theme,services},home,secrets,overlays,lib}

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
    
    # Show next steps

    cat <<EOF


${BOLD}Next steps:${NC}
1. Edit flake.nix to add your host configurations
2. Create host configuration in hosts/
3. Add modules as needed in modules/
4. Configure home-manager in home/


Use 'nixhelp help' to see available commands.
EOF
}

# Export functions
export -f init_repository
