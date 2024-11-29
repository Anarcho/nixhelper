#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

clean_generations() {
  log "INFO" "Cleaning up old generations"

  # Ask for confirmation
  read -p "This will remove old system generations. Continue? [y/N] " -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "INFO" "Cleanup cancelled"
    return 0
  fi

  # Clean NixOS generations
  if sudo nix-collect-garbage -d; then
    log "SUCCESS" "System generations cleaned"
  else
    log "ERROR" "Failed to clean system generations"
    return 1
  fi

  # Clean Home Manager generations if available
  if command -v home-manager &>/dev/null; then
    if home-manager expire-generations "-30 days"; then
      log "SUCCESS" "Home Manager generations cleaned"
    else
      log "WARNING" "Failed to clean Home Manager generations"
    fi
  fi

  # Remove temporary files
  find "${REPO_PATH}" -name "result" -type l -delete
  find "${REPO_PATH}" -name ".direnv" -type d -exec rm -rf {} +

  log "SUCCESS" "Cleanup completed"
}

list_generations() {
  log "INFO" "System generations:"
  nix-env --list-generations --profile /nix/var/nix/profiles/system

  if command -v home-manager &>/dev/null; then
    log "INFO" "Home Manager generations:"
    home-manager generations
  fi
}

rollback_generation() {
  local type="${1:-system}"

  case "$type" in
  system)
    if sudo nixos-rebuild switch --rollback; then
      log "SUCCESS" "System rolled back to previous generation"
    else
      log "ERROR" "System rollback failed"
      return 1
    fi
    ;;
  home)
    if command -v home-manager &>/dev/null; then
      if home-manager generations rollback; then
        log "SUCCESS" "Home Manager configuration rolled back"
      else
        log "ERROR" "Home Manager rollback failed"
        return 1
      fi
    else
      log "ERROR" "Home Manager not installed"
      return 1
    fi
    ;;
  *)
    log "ERROR" "Unknown generation type: ${type}"
    return 1
    ;;
  esac
}

switch_generation() {
  local generation="$1"
  local type="${2:-system}"

  case "$type" in
  system)
    if sudo nixos-rebuild switch --to-generation "$generation"; then
      log "SUCCESS" "Switched to system generation ${generation}"
    else
      log "ERROR" "Failed to switch to system generation ${generation}"
      return 1
    fi
    ;;
  home)
    if command -v home-manager &>/dev/null; then
      if home-manager switch --generation "$generation"; then
        log "SUCCESS" "Switched to home-manager generation ${generation}"
      else
        log "ERROR" "Failed to switch to home-manager generation ${generation}"
        return 1
      fi
    else
      log "ERROR" "Home Manager not installed"
      return 1
    fi
    ;;
  *)
    log "ERROR" "Unknown generation type: ${type}"
    return 1
    ;;
  esac
}

# Export functions
export -f clean_generations list_generations rollback_generation switch_generation
