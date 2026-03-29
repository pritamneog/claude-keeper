#!/usr/bin/env bash
# claude-keeper: Linux scheduler management
# Uses systemd user timers (preferred) with cron as fallback.

set -euo pipefail

readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
readonly SERVICE_NAME="claude-keeper"
readonly CRON_MARKER="# claude-keeper auto-update"

# -- Detection --

_has_systemd_user() {
    systemctl --user status &>/dev/null 2>&1
}

# -- systemd --

_service_path() {
    printf '%s/%s.service' "${SYSTEMD_USER_DIR}" "${SERVICE_NAME}"
}

_timer_path() {
    printf '%s/%s.timer' "${SYSTEMD_USER_DIR}" "${SERVICE_NAME}"
}

_generate_service() {
    local script_path="$1"

    cat << SERVICE
[Unit]
Description=Claude Code auto-updater

[Service]
Type=oneshot
ExecStart=/bin/bash "${script_path}" run
SERVICE
}

_generate_timer() {
    local hour="$1"
    local minute="$2"

    # Pad with leading zeros
    local hh
    hh="$(printf '%02d' "$((10#${hour}))")"
    local mm
    mm="$(printf '%02d' "$((10#${minute}))")"

    cat << TIMER
[Unit]
Description=Daily Claude Code update check

[Timer]
OnCalendar=*-*-* ${hh}:${mm}:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER
}

_install_systemd() {
    local hour="$1"
    local minute="$2"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local script_path
    if [[ -f "${script_dir}/bin/claude-keeper.sh" ]]; then
        script_path="${script_dir}/bin/claude-keeper.sh"
    elif [[ -f "${script_dir}/claude-keeper.sh" ]]; then
        script_path="${script_dir}/claude-keeper.sh"
    else
        echo "ERROR: Cannot find claude-keeper.sh" >&2
        return 1
    fi

    # Create directory
    mkdir -p "${SYSTEMD_USER_DIR}"

    # Write unit files
    _generate_service "${script_path}" > "$(_service_path)"
    _generate_timer "${hour}" "${minute}" > "$(_timer_path)"

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}.timer"
    systemctl --user start "${SERVICE_NAME}.timer"
}

_uninstall_systemd() {
    if systemctl --user is-enabled "${SERVICE_NAME}.timer" &>/dev/null 2>&1; then
        systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null || true
        systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    fi

    rm -f "$(_service_path)" "$(_timer_path)"
    systemctl --user daemon-reload 2>/dev/null || true
}

_is_systemd_installed() {
    [[ -f "$(_timer_path)" ]]
}

# -- cron --

_install_cron() {
    local hour="$1"
    local minute="$2"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local script_path
    if [[ -f "${script_dir}/bin/claude-keeper.sh" ]]; then
        script_path="${script_dir}/bin/claude-keeper.sh"
    elif [[ -f "${script_dir}/claude-keeper.sh" ]]; then
        script_path="${script_dir}/claude-keeper.sh"
    else
        echo "ERROR: Cannot find claude-keeper.sh" >&2
        return 1
    fi

    local log_d
    log_d="$(log_dir)"
    mkdir -p "${log_d}"

    # Remove existing claude-keeper entries, then add new one
    local existing
    existing="$(crontab -l 2>/dev/null | grep -v "claude-keeper" || true)"

    local new_entry
    new_entry="$((10#${minute})) $((10#${hour})) * * * /bin/bash ${script_path} run >> ${log_d}/cron.log 2>&1 ${CRON_MARKER}"

    if [[ -n "${existing}" ]]; then
        printf '%s\n%s\n' "${existing}" "${new_entry}" | crontab -
    else
        printf '%s\n' "${new_entry}" | crontab -
    fi
}

_uninstall_cron() {
    local existing
    existing="$(crontab -l 2>/dev/null | grep -v "claude-keeper" || true)"

    if [[ -n "${existing}" ]]; then
        printf '%s\n' "${existing}" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
}

_is_cron_installed() {
    crontab -l 2>/dev/null | grep -q "claude-keeper"
}

# -- Public API --

# Install the schedule using the best available method.
# Arguments: hour (0-23), minute (0-59)
install_schedule() {
    local hour="$1"
    local minute="$2"

    if _has_systemd_user; then
        _install_systemd "${hour}" "${minute}"
    else
        _install_cron "${hour}" "${minute}"
    fi
}

# Uninstall the schedule.
uninstall_schedule() {
    if _has_systemd_user; then
        _uninstall_systemd
    fi
    # Always try cron too in case both were set up
    _uninstall_cron 2>/dev/null || true
}

# Check if any schedule is installed.
is_schedule_installed() {
    _is_systemd_installed || _is_cron_installed
}

# Print schedule status.
schedule_status() {
    if _has_systemd_user && _is_systemd_installed; then
        echo "Method: systemd user timer"
        echo "Service: $(_service_path)"
        echo "Timer: $(_timer_path)"
        systemctl --user status "${SERVICE_NAME}.timer" --no-pager 2>/dev/null || true
    elif _is_cron_installed; then
        echo "Method: cron"
        echo "Entry:"
        crontab -l 2>/dev/null | grep "claude-keeper" | sed 's/^/  /'
    else
        echo "Status: not installed"
    fi
}
