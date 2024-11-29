#!/usr/bin/env bash
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Source required files from the script directory
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"
check_dependencies() {
    local missing=0
    local deps=("git" "nix" "rsync" "ssh" "curl")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            error "Missing required dependency: ${dep}"
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        return 1
    fi

    # Check nix flakes
    if ! nix config show | grep -q "experimental-features.*flakes"; then
        warning "Nix flakes not enabled. Enable with:"
        info "mkdir -p ~/.config/nix"
        info "echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf"
        return 1
    fi

    return 0
}

validate_path() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        error "Path does not exist: ${path}"
        return 1
    fi
    return 0
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -p "${message} ${prompt} " -r response
    response=${response:-$default}

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

create_timestamp() {
    date "+%Y%m%d_%H%M%S"
}

ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            error "Failed to create directory: ${dir}"
            return 1
        }
    fi
    return 0
}

check_internet() {
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        return 0
    else
        error "No internet connection"
        return 1
    fi
}

get_nix_version() {
    nix --version | cut -d ' ' -f 3
}

get_latest_nixpkgs_revision() {
    local branch="${1:-nixos-unstable}"
    local revision

    if ! check_internet; then
        return 1
    fi

    if revision=$(git ls-remote https://github.com/NixOS/nixpkgs.git "$branch" | cut -f1); then
        echo "$revision"
        return 0
    else
        error "Failed to get latest nixpkgs revision"
        return 1
    fi
}

calculate_sha256() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        error "File not found: ${file}"
        return 1
    fi
}

validate_flake() {
    local flake_path="$1"

    if [[ ! -f "${flake_path}/flake.nix" ]]; then
        error "No flake.nix found in ${flake_path}"
        return 1
    fi

    if ! (cd "${flake_path}" && nix flake check); then
        error "Flake validation failed"
        return 1
    fi

    return 0
}

is_nix_shell() {
    [[ -n "$IN_NIX_SHELL" ]]
}

get_system_type() {
    case "$(uname -s)" in
        Linux*)
            if grep -q Microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*)
            echo "darwin"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

find_nixos_config() {
    local paths=(
        "$REPO_PATH"
        "$HOME/.config/nixos"
        "/etc/nixos"
    )

    for path in "${paths[@]}"; do
        if [[ -f "${path}/flake.nix" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

is_nixos() {
    [[ -f "/etc/NIXOS" ]]
}

get_hostname() {
    hostname -s
}

format_size() {
    local size="$1"
    numfmt --to=iec-i --suffix=B "$size"
}

join_by() {
    local d=${1-} f=${2-}
    if shift 2; then
        printf %s "$f" "${@/#/$d}"
    fi
}

# Export functions
export -f check_dependencies validate_path confirm_action create_timestamp
export -f ensure_directory check_internet get_nix_version get_latest_nixpkgs_revision
export -f calculate_sha256 validate_flake is_nix_shell get_system_type
export -f find_nixos_config is_nixos get_hostname format_size join_by
