#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

git_init() {
    local path="$1"

    if ! command -v git &>/dev/null; then
        error "Git not found. Please install git before continuing."
        return 1
    fi

    log "INFO" "Initializing git repository"

    (cd "${path}" || exit 1
        # Initialize repository if not already initialized
        if [[ ! -d ".git" ]]; then
            git init

            # Create comprehensive .gitignore
            cat > .gitignore <<'EOF'
# Nix
result
result-*
.direnv
.envrc

# Editor files
*.swp
*~
.vscode/
.idea/
*.iml

# OS-specific
.DS_Store
.Spotlight-V100
.Trashes
Thumbs.db
desktop.ini

# Build outputs
/tmp/
/build/

# Secrets
/secrets/
*.key
*.pem
*.key.pub
.env*
!.env.example

# Cache
.cache/
EOF

            # Set up git config if needed
            if [[ -z "$(git config user.name)" ]]; then
                read -p "Enter your name for git config: " git_name
                git config user.name "${git_name}"
            fi

            if [[ -z "$(git config user.email)" ]]; then
                read -p "Enter your email for git config: " git_email
                git config user.email "${git_email}"
            fi

            # Create initial commit
            git add .
            git commit -m "Initial commit: NixOS configuration structure"

            success "Git repository initialized with initial commit"
        else
            info "Git repository already initialized"
        fi
    )
}

git_status() {
    if [[ ! -d "${REPO_PATH}/.git" ]]; then
        error "Not a git repository: ${REPO_PATH}"
        return 1
    fi

    (cd "${REPO_PATH}" || exit 1
        log "INFO" "Git Status:"
        echo

        # Show branch information
        local current_branch
        current_branch=$(git branch --show-current)
        echo "Current branch: ${current_branch}"

        # Show status
        if [[ -n "$(git status --porcelain)" ]]; then
            warning "There are uncommitted changes:"
            git status --short
        else
            success "Working directory is clean"
        fi

        # Show recent commits
        echo -e "\nRecent commits:"
        git log --oneline -n 5
    )
}

git_branch() {
    local action="$1"
    local branch_name="$2"

    if [[ ! -d "${REPO_PATH}/.git" ]]; then
        error "Not a git repository: ${REPO_PATH}"
        return 1
    fi

    (cd "${REPO_PATH}" || exit 1
        case "$action" in
            "create")
                if [[ -z "$branch_name" ]]; then
                    error "Branch name required"
                    return 1
                fi
                if git checkout -b "${branch_name}"; then
                    success "Created and switched to branch: ${branch_name}"
                else
                    error "Failed to create branch: ${branch_name}"
                    return 1
                fi
                ;;
            "list")
                log "INFO" "Available branches:"
                git branch -vv
                ;;
            "switch")
                if [[ -z "$branch_name" ]]; then
                    error "Branch name required"
                    return 1
                fi
                if git checkout "${branch_name}"; then
                    success "Switched to branch: ${branch_name}"
                else
                    error "Failed to switch to branch: ${branch_name}"
                    return 1
                fi
                ;;
            "delete")
                if [[ -z "$branch_name" ]]; then
                    error "Branch name required"
                    return 1
                fi
                if [[ "$branch_name" == "$(git branch --show-current)" ]]; then
                    error "Cannot delete current branch"
                    return 1
                fi
                if git branch -d "${branch_name}"; then
                    success "Deleted branch: ${branch_name}"
                else
                    error "Failed to delete branch: ${branch_name}"
                    return 1
                fi
                ;;
            *)
                error "Invalid branch action: ${action}"
                info "Available actions: create, list, switch, delete"
                return 1
                ;;
        esac
    )
}

git_sync() {
    if [[ ! -d "${REPO_PATH}/.git" ]]; then
        error "Not a git repository: ${REPO_PATH}"
        return 1
    fi

    (cd "${REPO_PATH}" || exit 1
        # Check for uncommitted changes
        if [[ -n "$(git status --porcelain)" ]]; then
            if confirm_action "There are uncommitted changes. Stash them?"; then
                git stash
                local changes_stashed=true
            else
                return 1
            fi
        fi

        # Get current branch
        local current_branch
        current_branch=$(git branch --show-current)

        # Fetch changes
        log "INFO" "Fetching changes..."
        if ! git fetch origin; then
            error "Failed to fetch changes"
            return 1
        fi

        # Pull with rebase
        log "INFO" "Pulling changes..."
        if git pull --rebase origin "${current_branch}"; then
            success "Successfully synced with remote"
        else
            error "Failed to sync with remote"
            if [[ "${changes_stashed}" == "true" ]]; then
                warning "Restoring stashed changes..."
                git stash pop
            fi
            return 1
        fi

        # Apply stashed changes if any
        if [[ "${changes_stashed}" == "true" ]]; then
            if git stash pop; then
                success "Restored stashed changes"
            else
                error "Failed to restore stashed changes"
                warning "Your changes are still in the stash. Resolve conflicts manually."
                return 1
            fi
        fi
    )
}

git_commit() {
    local message="$1"

    if [[ ! -d "${REPO_PATH}/.git" ]]; then
        error "Not a git repository: ${REPO_PATH}"
        return 1
    fi

    if [[ -z "$message" ]]; then
        error "Commit message required"
        return 1
    fi

    (cd "${REPO_PATH}" || exit 1
        if [[ -z "$(git status --porcelain)" ]]; then
            warning "No changes to commit"
            return 0
        fi

        # Show changes to be committed
        git status --short

        if confirm_action "Commit these changes?"; then
            git add .
            if git commit -m "${message}"; then
                success "Changes committed successfully"
            else
                error "Failed to commit changes"
                return 1
            fi
        fi
    )
}

# Export functions
export -f git_init git_status git_branch git_sync git_commit
