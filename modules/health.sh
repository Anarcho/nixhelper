#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

check_health() {
  local issues=0
  log "INFO" "Starting system health check..."

  # Check Nix installation
  check_nix_installation || ((issues++))

  # Check repository structure
  check_repo_structure || ((issues++))

  # Check flake configuration
  check_flake || ((issues++))

  # Check host configurations
  check_host_configs || ((issues++))

  # Check home-manager configs
  check_home_manager_configs || ((issues++))

  # Check Git status
  check_git_status || ((issues++))

  # Summary
  if ((issues > 0)); then
    error "Found ${issues} issue(s)"
    return 1
  else
    success "Health check passed"
    return 0
  fi
}

check_nix_installation() {
  log "INFO" "Checking Nix installation"

  # Check if nix is installed
  if ! command -v nix &>/dev/null; then
    error "Nix is not installed"
    return 1
  fi

  # Check if flakes are enabled
  if ! nix config show | grep -q "experimental-features.*flakes"; then
    warning "Nix flakes not enabled"
    info "Enable with: mkdir -p ~/.config/nix && echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf"
    return 1
  fi

  # Check if running on NixOS
  if is_nixos; then
    local nixos_version
    nixos_version=$(nixos-version)
    success "Running NixOS ${nixos_version}"
  else
    info "Not running NixOS (this is fine if intentional)"
  fi

  # Check nix-channel
  if ! nix-channel --list | grep -q "nixpkgs"; then
    warning "No nixpkgs channel found"
    return 1
  fi

  success "Nix installation check passed"
  return 0
}

check_repo_structure() {
  local status=0
  log "INFO" "Checking repository structure"

  # Check essential directories
  local required_dirs=(
    "hosts"
    "hosts/common"
    "modules"
    "modules/core"
    "home"
    "lib"
  )

  for dir in "${required_dirs[@]}"; do
    if [[ ! -d "${REPO_PATH}/${dir}" ]]; then
      error "Missing required directory: ${dir}"
      status=1
    fi
  done

  # Check essential files
  local required_files=(
    "flake.nix"
    "hosts/common/default.nix"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "${REPO_PATH}/${file}" ]]; then
      error "Missing required file: ${file}"
      status=1
    fi
  done

  # Check file permissions
  find "${REPO_PATH}" -type f -name "*.nix" -exec test ! -r {} \; -exec echo "Warning: {} is not readable" \;

  if ((status == 0)); then
    success "Repository structure check passed"
  fi

  return $status
}

check_flake() {
  log "INFO" "Checking flake configuration"

  # Validate flake.nix
  if ! (cd "${REPO_PATH}" && nix flake check); then
    error "Flake validation failed"
    return 1
  fi

  # Check inputs
  local required_inputs=("nixpkgs" "home-manager")
  for input in "${required_inputs[@]}"; do
    if ! grep -q "inputs.${input}" "${REPO_PATH}/flake.nix"; then
      error "Missing required input: ${input}"
      return 1
    fi
  done

  # Check outputs
  local required_outputs=("nixosConfigurations" "homeConfigurations")
  for output in "${required_outputs[@]}"; do
    if ! grep -q "${output} =" "${REPO_PATH}/flake.nix"; then
      warning "Missing recommended output: ${output}"
    fi
  done

  success "Flake check passed"
  return 0
}

check_host_configs() {
  log "INFO" "Checking host configurations"
  local status=0

  # Find all host configurations
  for host_dir in "${REPO_PATH}/hosts"/*; do
    if [[ -d "$host_dir" && "$(basename "$host_dir")" != "common" ]]; then
      local host_name
      host_name=$(basename "$host_dir")

      # Check essential files
      if [[ ! -f "${host_dir}/default.nix" ]]; then
        error "Host ${host_name} missing default.nix"
        status=1
        continue
      fi

      # Check hardware configuration
      if [[ ! -f "${host_dir}/hardware-configuration.nix" ]]; then
        warning "Host ${host_name} missing hardware-configuration.nix"
      fi

      # Try to build configuration
      if ! nixos-rebuild build --flake "${REPO_PATH}#${host_name}" --dry-run &>/dev/null; then
        error "Host ${host_name} configuration has build errors"
        status=1
      fi
    fi
  done

  if ((status == 0)); then
    success "Host configurations check passed"
  fi

  return $status
}

check_home_manager_configs() {
  log "INFO" "Checking home-manager configurations"
  local status=0

  # Check if home-manager is available
  if ! command -v home-manager &>/dev/null; then
    warning "home-manager not installed (skipping checks)"
    return 0
  fi

  # Check home directory
  if [[ ! -d "${REPO_PATH}/home" ]]; then
    warning "No home directory found"
    return 0
  fi

  # Check each user configuration
  for user_dir in "${REPO_PATH}/home"/*; do
    if [[ -d "$user_dir" ]]; then
      local user_name
      user_name=$(basename "$user_dir")

      # Check essential files
      if [[ ! -f "${user_dir}/default.nix" ]]; then
        error "User ${user_name} missing default.nix"
        status=1
        continue
      fi

      # Try to build configuration
      if ! home-manager build --flake "${REPO_PATH}#${user_name}@$(hostname)" --dry-run &>/dev/null; then
        error "User ${user_name} configuration has build errors"
        status=1
      fi
    fi
  done

  if ((status == 0)); then
    success "Home-manager configurations check passed"
  fi

  return $status
}

check_git_status() {
  log "INFO" "Checking Git status"

  if [[ ! -d "${REPO_PATH}/.git" ]]; then
    warning "Not a Git repository"
    return 1
  fi

  (
    cd "${REPO_PATH}" || exit 1
    # Check for uncommitted changes
    if [[ -n "$(git status --porcelain)" ]]; then
      warning "There are uncommitted changes"
      git status --short
      return 1
    fi

    # Check if branch is behind remote
    local branch
    branch=$(git branch --show-current)
    git fetch origin "${branch}" &>/dev/null
    if [[ -n "$(git log HEAD..origin/${branch} --oneline)" ]]; then
      warning "Local branch is behind remote"
      return 1
    fi
  )

  success "Git status check passed"
  return 0
}

# Export functions
export -f check_health check_nix_installation check_repo_structure check_flake
export -f check_host_configs check_home_manager_configs check_git_status
