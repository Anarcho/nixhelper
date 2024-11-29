#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

show_help() {
    local command="$1"
    
    if [[ -n "$command" ]]; then
        show_command_help "$command"
        return
    fi

    cat <<EOF
${BOLD}NixOS Configuration Helper${NC}

Usage: nixhelp [command] [options]

${BOLD}Core Commands:${NC}
    init [path]              Initialize new configuration repository
    check                    Run system health checks
    update                   Update flake inputs

${BOLD}Host Commands:${NC}
    host create              Create new host configuration
        <name>               Host name
        [--type TYPE]        Host type (desktop|server|vm|wsl|minimal)
    host list                List all hosts
    host remove              Remove host configuration
    host rename              Rename host

${BOLD}Module Commands:${NC}
    module create            Create new module
        <category>           Module category
        <name>               Module name
        [--type TYPE]        Module type (nixos|home-manager)
    module enable            Enable module for host/user
    module disable           Disable module
    module list              List available modules
    module check             Check module configuration

${BOLD}Development Commands:${NC}
    dev create               Create development environment
        <type>               Environment type (rust|python|node|go|zig|cpp)
    dev activate             Activate development environment
    dev remove               Remove development environment
    dev list                 List available environments
    dev update               Update development environment

${BOLD}Build Commands:${NC}
    build                    Build configuration
        <host>               Host to build for
        <type>               Build type (nixos|home-manager|all)
        [--user NAME]        User for home-manager builds
    build check              Validate configuration before building
    build rollback           Rollback to previous configuration

${BOLD}VM Commands:${NC}
    vm setup                 Configure VM settings
    vm sync                  Sync configuration to VM
    vm deploy                Deploy configuration to VM
    vm status                Check VM status

${BOLD}Backup Commands:${NC}
    backup create            Create new backup
    backup list              List available backups
    backup restore           Restore from backup
    backup verify            Verify backup integrity
    backup delete            Delete backup

${BOLD}Git Commands:${NC}
    git init                 Initialize git repository
    git status               Check git status
    git branch               Branch operations (create|list|switch|delete)
    git sync                 Sync with remote repository
    git commit               Commit changes

${BOLD}List Commands:${NC}
    list hosts               List all hosts
    list users               List all users
    list modules             List all modules
    list dev                 List development environments
    list generations         List system generations
    list backups             List available backups

${BOLD}Options:${NC}
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message
    --version                Show version information

For more detailed information about a command:

    nixhelp help <command>

Examples:
    nixhelp init ~/nixos-config
    nixhelp host create mydesktop --type desktop
    nixhelp module create apps firefox --type home-manager
    nixhelp build myhost all --user myuser
    nixhelp vm deploy myhost
EOF
}

show_command_help() {
    local command="$1"

    case "$command" in
        "init")
            cat <<EOF
${BOLD}Initialize Configuration (init)${NC}

Initialize a new NixOS configuration repository with the recommended structure.

Usage:
    nixhelp init [path]

Options:
    path    Directory to initialize (default: current directory)

The initialization process:
1. Creates directory structure
2. Sets up basic configuration files
3. Initializes git repository
4. Creates documentation

Example:
    nixhelp init ~/nixos-config
EOF
            ;;
        "host")
            cat <<EOF
${BOLD}Host Management (host)${NC}

Manage NixOS host configurations.

Usage:
    nixhelp host create <name> [--type TYPE]
    nixhelp host list
    nixhelp host remove <name>
    nixhelp host rename <old> <new>

Types:
    desktop     Desktop configuration
    server      Server configuration
    vm          Virtual machine configuration
    wsl         Windows Subsystem for Linux
    minimal     Minimal configuration

Example:
    nixhelp host create mydesktop --type desktop
EOF
            ;;
        # Add more command-specific help sections here
        *)
            error "No detailed help available for: ${command}"
            show_help
            return 1
            ;;
    esac
}

show_version() {
    echo "NixOS Configuration Helper v1.0.0"
}

show_examples() {
    cat <<EOF
${BOLD}Configuration Examples${NC}

1. Basic Setup:
    nixhelp init ~/nixos-config
    nixhelp host create desktop --type desktop
    nixhelp module create apps firefox --type home-manager
    nixhelp build desktop all

2. Development Setup:
    nixhelp dev create rust
    nixhelp dev activate rust
    nixhelp module enable development rust user@host

3. VM Deployment:
    nixhelp vm setup
    nixhelp vm sync myhost
    nixhelp vm deploy myhost

4. Backup Management:
    nixhelp backup create
    nixhelp backup list
    nixhelp backup restore backup_20240129_123456

5. Module Management:
    nixhelp module create desktop hyprland
    nixhelp module enable desktop hyprland myhost
    nixhelp module list

For more examples, use: nixhelp help <command>
EOF
}

# Export functions
export -f show_help show_command_help show_version show_examples
