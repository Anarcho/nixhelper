#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

create_backup() {
    local backup_name="backup_$(create_timestamp)"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    log "INFO" "Creating backup at ${backup_path}"

    # Ensure backup directory exists
    ensure_directory "$backup_path"

    # Sync configuration files
    if rsync -az --info=progress2 \
        --exclude '.git' \
        --exclude 'result' \
        --exclude '.direnv' \
        --exclude 'tmp' \
        --exclude '*.swp' \
        "${REPO_PATH}/" "${backup_path}/"; then

        # Create backup manifest
        cat > "${backup_path}/MANIFEST.txt" <<EOF
Backup Information
-----------------
Created: $(date)
Source: ${REPO_PATH}
Host: $(hostname)
User: ${USER}

Git Status:
$(cd "${REPO_PATH}" && git status 2>/dev/null || echo "Not a git repository")

Git Commit: 
$(cd "${REPO_PATH}" && git rev-parse HEAD 2>/dev/null || echo "N/A")

Directory Structure:
$(tree -a -I '.git|result|.direnv' "${backup_path}" || ls -R "${backup_path}")

System Information:
------------------
NixOS Version: $(nixos-version 2>/dev/null || echo "Not NixOS")
Home Manager Version: $(home-manager --version 2>/dev/null || echo "Not installed")
EOF

        cleanup_old_backups
        success "Backup created successfully at ${backup_path}"
    else
        error "Backup creation failed"
        rm -rf "${backup_path}"
        return 1
    fi
}

cleanup_old_backups() {
    local max_backups="${MAX_BACKUPS:-5}"
    local backup_count

    log "INFO" "Cleaning up old backups (keeping ${max_backups} most recent)"

    backup_count=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "backup_*" | wc -l)

    if ((backup_count > max_backups)); then
        find "${BACKUP_DIR}" -maxdepth 1 -type d -name "backup_*" | \
            sort -r | \
            tail -n +$((max_backups + 1)) | \
            while read -r backup; do
                log "INFO" "Removing old backup: $(basename "${backup}")"
                rm -rf "${backup}"
            done
    fi
}

restore_backup() {
    local backup_name="$1"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    local target_path="${2:-${REPO_PATH}}"

    if [[ ! -d "${backup_path}" ]]; then
        error "Backup not found: ${backup_name}"
        return 1
    fi

    # Show backup information
    if [[ -f "${backup_path}/MANIFEST.txt" ]]; then
        echo "Backup Information:"
        cat "${backup_path}/MANIFEST.txt"
    fi

    if ! confirm_action "Restore this backup to ${target_path}?"; then
        return 0
    fi

    log "INFO" "Restoring backup ${backup_name} to ${target_path}"

    # Create backup of current state before restoring
    create_backup

    # Restore files
    if rsync -az --delete --info=progress2 \
        "${backup_path}/" \
        "${target_path}/"; then
        success "Backup restored successfully"
    else
        error "Backup restoration failed"
        return 1
    fi
}

list_backups() {
    log "INFO" "Available backups:"
    echo

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        warning "No backups directory found"
        return 0
    fi

    local count=0
    for backup in "${BACKUP_DIR}"/backup_*; do
        if [[ -d "${backup}" ]]; then
            ((count++))
            echo -e "${BOLD}${count}. $(basename "${backup}")${NC}"
            if [[ -f "${backup}/MANIFEST.txt" ]]; then
                # Extract and display key information from manifest
                echo "Created: $(grep "Created:" "${backup}/MANIFEST.txt" | cut -d: -f2-)"
                echo "Source: $(grep "Source:" "${backup}/MANIFEST.txt" | cut -d: -f2-)"
                echo "Git Commit: $(grep "Git Commit:" "${backup}/MANIFEST.txt" | cut -d: -f2-)"
                echo
            fi
        fi
    done

    if ((count == 0)); then
        warning "No backups found"
    fi
}

verify_backup() {
    local backup_name="$1"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    if [[ ! -d "${backup_path}" ]]; then
        error "Backup not found: ${backup_name}"
        return 1
    fi

    log "INFO" "Verifying backup: ${backup_name}"

    # Check manifest
    if [[ ! -f "${backup_path}/MANIFEST.txt" ]]; then
        warning "Manifest file missing"
    fi

    # Check file integrity
    local error_count=0

    while IFS= read -r -d '' file; do
        if [[ ! -f "${REPO_PATH}/${file#${backup_path}/}" ]]; then
            warning "File missing in source: ${file#${backup_path}/}"
            ((error_count++))
        fi
    done < <(find "${backup_path}" -type f -print0)

    if ((error_count > 0)); then
        warning "Found ${error_count} discrepancies"
        return 1
    else
        success "Backup verification completed successfully"
        return 0
    fi
}

delete_backup() {
    local backup_name="$1"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    if [[ ! -d "${backup_path}" ]]; then
        error "Backup not found: ${backup_name}"
        return 1
    fi

    if ! confirm_action "Are you sure you want to delete backup ${backup_name}?"; then
        return 0
    fi

    if rm -rf "${backup_path}"; then
        success "Backup deleted successfully"
    else
        error "Failed to delete backup"
        return 1
    fi
}

# Export functions
export -f create_backup cleanup_old_backups restore_backup list_backups verify_backup delete_backup
