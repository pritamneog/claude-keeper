#!/usr/bin/env bash
# claude-keeper: macOS launchd scheduler management
# Creates, loads, unloads, and removes launchd plists for daily scheduling.

set -euo pipefail

readonly PLIST_LABEL="com.claude-keeper.updater"
readonly PLIST_DIR="${HOME}/Library/LaunchAgents"

_plist_path() {
    printf '%s/%s.plist' "${PLIST_DIR}" "${PLIST_LABEL}"
}

# Generate the launchd plist XML content.
# Arguments: hour (0-23), minute (0-59), script_path, log_dir
_generate_plist() {
    local hour="$1"
    local minute="$2"
    local script_path="$3"
    local stdout_log="$4"
    local stderr_log="$5"

    # Capture the current PATH so launchd inherits it.
    # launchd runs with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin) which
    # excludes Homebrew, npm, ~/.local/bin, etc. Without this, detect.sh
    # cannot find brew/claude/npm and reports "not_installed".
    local current_path="${PATH}"

    cat << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${current_path}</string>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
        <string>run</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${stdout_log}</string>
    <key>StandardErrorPath</key>
    <string>${stderr_log}</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST
}

# Install the launchd schedule.
# Arguments: hour (0-23), minute (0-59)
install_schedule() {
    local hour="$1"
    local minute="$2"

    # Remove leading zeros for integer fields
    hour="$((10#${hour}))"
    minute="$((10#${minute}))"

    # Resolve paths -- support both dev layout and installed layout
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
    local stdout_log="${log_d}/launchd-stdout.log"
    local stderr_log="${log_d}/launchd-stderr.log"

    # Unload existing plist if present
    local plist
    plist="$(_plist_path)"
    if [[ -f "${plist}" ]]; then
        launchctl unload "${plist}" 2>/dev/null || true
    fi

    # Create LaunchAgents directory if needed
    mkdir -p "${PLIST_DIR}"

    # Write the plist
    _generate_plist "${hour}" "${minute}" "${script_path}" "${stdout_log}" "${stderr_log}" > "${plist}"

    # Load it
    launchctl load "${plist}"
}

# Uninstall the launchd schedule.
uninstall_schedule() {
    local plist
    plist="$(_plist_path)"

    if [[ -f "${plist}" ]]; then
        launchctl unload "${plist}" 2>/dev/null || true
        rm -f "${plist}"
    fi
}

# Check if the schedule is installed.
is_schedule_installed() {
    local plist
    plist="$(_plist_path)"
    [[ -f "${plist}" ]]
}

# Print schedule status.
schedule_status() {
    if is_schedule_installed; then
        echo "launchd plist: $(_plist_path)"
        echo "Status: installed"
        # Try to show if it's loaded
        if launchctl list "${PLIST_LABEL}" &>/dev/null; then
            echo "Loaded: yes"
        else
            echo "Loaded: no (will load on next login)"
        fi
    else
        echo "Status: not installed"
    fi
}
