#!/usr/bin/env bash

# Dynamically determine REPO_PATH based on script location
# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Source required files from the script directory
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/ssh.sh"

create_host() {
    local host_name="$1"
    local host_type="${2:-minimal}"
    local target_path="${REPO_PATH}/hosts/${host_name}"
    local flake_path="${REPO_PATH}/flake.nix"

    # Validate host type
    if [[ ! " ${HOST_TYPES[@]} " =~ " ${host_type} " ]]; then
        error "Invalid host type: ${host_type}"
        info "Available types: ${HOST_TYPES[*]}"
        return 1
    fi

    log "INFO" "Creating new host: ${host_name} (type: ${host_type})"

    # Ensure REPO_PATH exists
    if [[ ! -d "${REPO_PATH}" ]]; then
        error "Repository path does not exist: ${REPO_PATH}"
        return 1
    fi

    # Ensure flake.nix exists
    if [[ ! -f "${flake_path}" ]]; then
        error "flake.nix not found in ${REPO_PATH}"
        error "Please create a valid flake.nix file before adding a host."
        return 1
    fi

    # Create host directory structure
    mkdir -p "${target_path}"

    # Create default.nix
    cat > "${target_path}/default.nix" <<EOF
{
  imports = [ 
    ../common
    ./configuration.nix
    ./hardware-configuration.nix
  ];
}
EOF

    # Create configuration.nix based on host type
    cat > "${target_path}/configuration.nix" <<EOF
{ config, lib, pkgs, ... }:

{
  networking.hostName = "${host_name}";

  # Import host-type specific configuration
  imports = [ ./host-type/${host_type}.nix ];

  # Add your host-specific configuration here
  system.stateVersion = "24.05";
}
EOF

    # Create host-type specific configuration directory
    mkdir -p "${target_path}/host-type"

    # Create host-type configuration
    case "${host_type}" in
        "desktop")
            cat > "${target_path}/host-type/desktop.nix" <<'EOF'
{ config, lib, pkgs, ... }: {
  services.xserver.enable = true;
  environment.systemPackages = with pkgs; [
    # Add desktop-specific packages here
  ];
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}
EOF
            ;;
        "server")
            cat > "${target_path}/host-type/server.nix" <<'EOF'
{ config, lib, pkgs, ... }: {
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  environment.systemPackages = with pkgs; [
    # Add server-specific packages here
  ];
}
EOF
            ;;
        "vm")
            cat > "${target_path}/host-type/vm.nix" <<'EOF'
{ config, lib, pkgs, ... }: {
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    # Add VM-specific packages here
  ];
}
EOF
            ;;
        "wsl")
            cat > "${target_path}/host-type/wsl.nix" <<'EOF'
{ config, lib, pkgs, ... }: {
  wsl = {
    enable = true;
    defaultUser = "nixos";
    nativeSystemd = true;
  };
  environment.systemPackages = with pkgs; [
    # Add WSL-specific packages here
  ];
}
EOF
            ;;
        *)
            error "Unsupported host type: ${host_type}"
            return 1
            ;;
    esac

    # Create placeholder for hardware-configuration.nix
    touch "${target_path}/hardware-configuration.nix"

    # Add host to flake.nix if it doesn't exist
    add_host_to_flake "${host_name}" "${host_type}"

    log "SUCCESS" "Host configuration created at ${target_path}"
}

add_host_to_flake() {
    local host_name="$1"
    local host_type="$2"
    local flake_path="${REPO_PATH}/flake.nix"

    if [[ ! -f "${flake_path}" ]]; then
        error "flake.nix not found in ${REPO_PATH}"
        return 1
    fi

    if ! grep -q "nixosConfigurations.${host_name}" "${flake_path}"; then
        local insert_line
        insert_line=$(grep -n "nixosConfigurations = {" "${flake_path}" | cut -d: -f1)

        if [[ -n "${insert_line}" ]]; then
            sed -i "${insert_line}a\\
        ${host_name} = nixpkgs.lib.nixosSystem {\n          system = \"x86_64-linux\";\n          specialArgs = { inherit inputs outputs; };\n          modules = [\n            ./hosts/${host_name}\n          ];\n        };" "${flake_path}"

            log "SUCCESS" "Added ${host_name} to flake.nix"
        else
            error "Could not find nixosConfigurations section in flake.nix"
            return 1
        fi
    else
        warning "Host ${host_name} already exists in flake.nix"
    fi
}

generate_hardware_config() {
    local host_name="$1"
    local target_path="${REPO_PATH}/hosts/${host_name}"

    if [[ ! -d "${target_path}" ]]; then
        error "Host directory not found: ${target_path}"
        return 1
    fi

    log "INFO" "Generating hardware configuration for ${host_name}"

    if [[ "${VM_HOST}" != "localhost" ]]; then
        if ! check_vm_connectivity; then
            return 1
        fi
        ssh -p "${VM_PORT}" "${VM_USER}@${VM_HOST}" \
            "sudo nixos-generate-config --show-hardware-config" > "${target_path}/hardware-configuration.nix"
    else
        sudo nixos-generate-config --show-hardware-config > "${target_path}/hardware-configuration.nix"
    fi

    if [[ -f "${target_path}/hardware-configuration.nix" ]]; then
        log "SUCCESS" "Hardware configuration generated"
    else
        error "Failed to generate hardware configuration"
        return 1
    fi
}

remove_host() {
    local host_name="$1"
    local target_path="${REPO_PATH}/hosts/${host_name}"

    if [[ ! -d "${target_path}" ]]; then
        error "Host not found: ${host_name}"
        return 1
    fi

    if ! confirm_action "Are you sure you want to remove host ${host_name}?"; then
        return 0
    fi

    create_backup

    rm -rf "${target_path}"
    sed -i "/nixosConfigurations.*${host_name}/,/};/d" "${REPO_PATH}/flake.nix"

    log "SUCCESS" "Host ${host_name} removed"
}

rename_host() {
    local old_name="$1"
    local new_name="$2"
    local old_path="${REPO_PATH}/hosts/${old_name}"
    local new_path="${REPO_PATH}/hosts/${new_name}"

    if [[ ! -d "${old_path}" ]]; then
        error "Host not found: ${old_name}"
        return 1
    fi

    if [[ -d "${new_path}" ]]; then
        error "Host already exists: ${new_name}"
        return 1
    fi

    create_backup

    mv "${old_path}" "${new_path}"
    sed -i "s/hostName = \"${old_name}\"/hostName = \"${new_name}\"/" "${new_path}/configuration.nix"
    sed -i "s/${old_name} = nixpkgs/${new_name} = nixpkgs/" "${REPO_PATH}/flake.nix"
    sed -i "s/hosts\/${old_name}/hosts\/${new_name}/" "${REPO_PATH}/flake.nix"

    log "SUCCESS" "Host renamed from ${old_name} to ${new_name}"
}

# Export functions
export -f create_host add_host_to_flake generate_hardware_config remove_host rename_host
