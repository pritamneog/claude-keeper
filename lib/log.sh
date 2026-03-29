#!/usr/bin/env bash
# claude-keeper: Logging utilities
# Timestamped logging with daily rotation and retention management.

set -euo pipefail

# -- Constants --

readonly LOG_DIR_NAME="claude-keeper"
readonly LOG_PREFIX="upgrade"

# -- Directory Resolution --

log_dir() {
    local base
    if [[ "${XDG_DATA_HOME:-}" != "" ]]; then
        base="${XDG_DATA_HOME}"
    else
        base="${HOME}/.local/share"
    fi
    printf '%s/%s/logs' "${base}" "${LOG_DIR_NAME}"
}

# -- Internal Helpers --

_ensure_log_dir() {
    local dir
    dir="$(log_dir)"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
    fi
}

_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

_today() {
    date '+%Y-%m-%d'
}

_log_file() {
    printf '%s/%s-%s.log' "$(log_dir)" "${LOG_PREFIX}" "$(_today)"
}

_append() {
    local level="$1"
    local message="$2"
    _ensure_log_dir
    printf '%s [%s] %s\n' "$(_timestamp)" "${level}" "${message}" >> "$(_log_file)"
}

# -- Public API --

log_info() {
    local message="$1"
    _append "INFO" "${message}"
}

log_error() {
    local message="$1"
    _append "ERROR" "${message}"
}

log_warn() {
    local message="$1"
    _append "WARN" "${message}"
}

log_upgrade_result() {
    local old_ver="$1"
    local new_ver="$2"
    local exit_code="$3"
    local method="$4"

    if [[ "${exit_code}" -eq 0 ]]; then
        if [[ "${old_ver}" == "${new_ver}" ]]; then
            log_info "Upgrade check complete (method=${method}): already up to date at ${old_ver}"
        else
            log_info "Upgrade complete (method=${method}): ${old_ver} -> ${new_ver}"
        fi
    else
        log_error "Upgrade failed (method=${method}): exit_code=${exit_code}, version=${old_ver}"
    fi
}

# Rotate logs: delete log files older than the given number of days.
# A retention of 0 means keep forever.
rotate_logs() {
    local retention_days="$1"

    # Validate input at function boundary
    if ! [[ "${retention_days}" =~ ^[0-9]+$ ]]; then
        _append "ERROR" "rotate_logs: invalid retention_days: ${retention_days}"
        return 1
    fi

    if [[ "${retention_days}" -eq 0 ]]; then
        return 0
    fi

    local dir
    dir="$(log_dir)"

    if [[ ! -d "${dir}" ]]; then
        return 0
    fi

    # Calculate cutoff date using portable date arithmetic
    local cutoff
    if [[ "$(uname -s)" == "Darwin" ]]; then
        cutoff="$(date -v-"${retention_days}"d '+%Y-%m-%d')"
    else
        cutoff="$(date -d "${retention_days} days ago" '+%Y-%m-%d')"
    fi

    local file
    for file in "${dir}"/"${LOG_PREFIX}"-*.log; do
        [[ -f "${file}" ]] || continue

        # Extract date from filename: upgrade-2026-03-28.log -> 2026-03-28
        local file_date
        file_date="$(basename "${file}" .log | sed "s/^${LOG_PREFIX}-//")"

        # String comparison works for ISO dates
        if [[ "${file_date}" < "${cutoff}" ]]; then
            rm -f "${file}"
        fi
    done
}

# Print recent log entries to stdout.
# Usage: show_logs [--full]
show_logs() {
    local full="${1:-}"
    local dir
    dir="$(log_dir)"

    if [[ ! -d "${dir}" ]]; then
        echo "No logs found."
        return 0
    fi

    local files
    files=("${dir}"/"${LOG_PREFIX}"-*.log)

    if [[ ${#files[@]} -eq 0 ]] || [[ ! -f "${files[0]}" ]]; then
        echo "No logs found."
        return 0
    fi

    if [[ "${full}" == "--full" ]]; then
        cat "${files[@]}"
    else
        # Show last 50 lines from most recent log files
        tail -n 50 "${files[@]}" 2>/dev/null
    fi
}
