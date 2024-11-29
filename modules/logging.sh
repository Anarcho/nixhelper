#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Log Levels
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["SUCCESS"]=2
    ["WARNING"]=3
    ["ERROR"]=4
    ["CRITICAL"]=5
)

rotate_logs() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        return 0
    fi

    local size
    size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}")
    
    if ((size > $(numfmt --from=iec "${MAX_LOG_SIZE}"))); then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local rotated_log="${LOG_DIR}/nixhelp.${timestamp}.log"

        mv "${LOG_FILE}" "${rotated_log}"
        gzip "${rotated_log}"

        # Cleanup old logs, keeping last MAX_LOG_FILES
        find "${LOG_DIR}" -name "nixhelp.*.log.gz" -type f | \
            sort -r | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null || true

        touch "${LOG_FILE}"
    fi
}

format_log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}"
}

write_to_log() {
    local formatted_message="$1"
    
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}"
    
    # Rotate logs if needed
    rotate_logs
    
    # Write to log file
    echo -e "${formatted_message}" >> "${LOG_FILE}"
}

log() {
    local level="$1"
    shift
    local message="$*"
    
    # Validate log level
    if [[ -z ${LOG_LEVELS[$level]} ]]; then
        level="INFO"
    fi

    # Format message
    local formatted_message
    formatted_message=$(format_log_message "$level" "$message")
    
    # Write to log file
    write_to_log "${formatted_message}"

    # Display to console with appropriate color and formatting
    case "${level}" in
        DEBUG)
            ${VERBOSE} && echo -e "${BLUE}DEBUG: ${message}${NC}"
            ;;
        INFO)
            echo -e "${CYAN}${message}${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}${message}${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}Warning: ${message}${NC}" >&2
            ;;
        ERROR)
            echo -e "${RED}Error: ${message}${NC}" >&2
            ;;
        CRITICAL)
            echo -e "${RED}${BOLD}Critical: ${message}${NC}" >&2
            ;;
    esac
}

debug() {
    log "DEBUG" "$@"
}

info() {
    log "INFO" "$@"
}

success() {
    log "SUCCESS" "$@"
}

warning() {
    log "WARNING" "$@"
}

error() {
    log "ERROR" "$@"
}

critical() {
    log "CRITICAL" "$@"
}

get_log_file() {
    echo "${LOG_FILE}"
}

show_logs() {
    local lines="${1:-50}"
    local level="${2:-}"
    
    if [[ ! -f "${LOG_FILE}" ]]; then
        error "No log file found"
        return 1
    fi

    if [[ -n "${level}" ]]; then
        tail -n "${lines}" "${LOG_FILE}" | grep "\[${level}\]"
    else
        tail -n "${lines}" "${LOG_FILE}"
    fi
}

clear_logs() {
    if [[ -f "${LOG_FILE}" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        
        # Backup current log before clearing
        mv "${LOG_FILE}" "${LOG_FILE}.${timestamp}.bak"
        gzip "${LOG_FILE}.${timestamp}.bak"
        
        touch "${LOG_FILE}"
        success "Logs cleared and backed up"
    fi
}

# Export functions
export -A LOG_LEVELS
export -f rotate_logs format_log_message write_to_log log
export -f debug info success warning error critical
export -f get_log_file show_logs clear_logs
