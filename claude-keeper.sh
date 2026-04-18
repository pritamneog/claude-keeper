#!/usr/bin/env bash
# claude-keeper: Auto-updater for Claude Code CLI
# Main CLI entry point.

set -euo pipefail

readonly CLAUDE_KEEPER_VERSION="0.1.0"

# Resolve the directory where this script lives (follows symlinks)
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "${source}" ]]; do
        local dir
        dir="$(cd -P "$(dirname "${source}")" && pwd)"
        source="$(readlink "${source}")"
        [[ "${source}" != /* ]] && source="${dir}/${source}"
    done
    cd -P "$(dirname "${source}")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"

# Resolve lib directory: supports both dev layout (./lib) and installed layout (../lib)
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
    LIB_DIR="${SCRIPT_DIR}/lib"
elif [[ -d "${SCRIPT_DIR}/../lib" ]]; then
    LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
else
    echo "ERROR: Cannot find lib/ directory relative to ${SCRIPT_DIR}" >&2
    exit 1
fi

# -- Source library modules --

source "${LIB_DIR}/log.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/detect.sh"
source "${LIB_DIR}/upgrade.sh"

# -- Subcommands --

cmd_run() {
    # Acquire lock to prevent concurrent runs
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/claude-keeper.lock"
    exec 9>"${lock_file}"
    if command -v flock &>/dev/null; then
        if ! flock -n 9; then
            echo "Another claude-keeper instance is already running. Exiting."
            exit 0
        fi
    fi

    # Validate config
    if ! validate_config 2>/dev/null; then
        validate_config
        echo ""
        echo "Fix config errors before running. Config: $(config_path)"
        exit 1
    fi

    # Check if enabled
    local enabled
    enabled="$(read_config_or_default "enabled" "${DEFAULT_ENABLED}")"
    if [[ "${enabled}" != "true" ]]; then
        log_info "Auto-update disabled in config. Skipping."
        echo "Auto-update is disabled. Enable with: claude-keeper config set enabled true"
        exit 0
    fi

    # Determine install method
    local method
    method="$(read_config_or_default "install_method" "${DEFAULT_INSTALL_METHOD}")"
    if [[ "${method}" == "auto" ]]; then
        method="$(detect_install_method)"
    fi

    if [[ "${method}" == "not_installed" ]]; then
        log_error "Claude Code is not installed."
        echo "Error: Claude Code is not installed on this system."
        exit 1
    fi

    # Get hooks
    local pre_hook
    pre_hook="$(read_config "pre_update_hook")"
    local post_hook
    post_hook="$(read_config "post_update_hook")"

    # Run the full upgrade pipeline
    echo "Upgrading Claude Code (method: ${method})..."
    if run_full_upgrade "${method}" "${pre_hook}" "${post_hook}"; then
        echo "Done."
    else
        echo "Upgrade encountered an issue. Check logs: claude-keeper logs"
        exit 1
    fi

    # Rotate logs
    local retention
    retention="$(read_config_or_default "log_retention_days" "${DEFAULT_LOG_RETENTION_DAYS}")"
    rotate_logs "${retention}"
}

cmd_status() {
    echo "claude-keeper v${CLAUDE_KEEPER_VERSION}"
    echo ""

    # Config
    local cfg
    cfg="$(config_path)"
    if [[ -f "${cfg}" ]]; then
        echo "Config: ${cfg}"
    else
        echo "Config: not found (run 'claude-keeper reconfigure' to create)"
    fi

    # Enabled
    local enabled
    enabled="$(read_config_or_default "enabled" "${DEFAULT_ENABLED}")"
    echo "Enabled: ${enabled}"

    # Update time
    local update_time
    update_time="$(read_config_or_default "update_time" "${DEFAULT_UPDATE_TIME}")"
    echo "Update time: ${update_time}"

    # Install method
    local config_method
    config_method="$(read_config_or_default "install_method" "${DEFAULT_INSTALL_METHOD}")"
    local detected_method
    detected_method="$(detect_install_method)"
    if [[ "${config_method}" == "auto" ]]; then
        echo "Install method: auto -> $(describe_method "${detected_method}")"
    else
        echo "Install method: ${config_method} (override) [detected: ${detected_method}]"
    fi

    # Claude version
    local version
    version="$(get_claude_version)"
    echo "Claude version: ${version:-not available}"

    # Last log entry
    echo ""
    local log_d
    log_d="$(log_dir)"
    if [[ -d "${log_d}" ]]; then
        local latest
        latest="$(ls -t "${log_d}"/upgrade-*.log 2>/dev/null | head -1 || true)"
        if [[ -n "${latest}" ]]; then
            echo "Last log entry:"
            tail -n 3 "${latest}" 2>/dev/null | sed 's/^/  /'
        else
            echo "No upgrade logs yet."
        fi
    else
        echo "No upgrade logs yet."
    fi

    # Scheduler status
    echo ""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local plist="${HOME}/Library/LaunchAgents/com.claude-keeper.updater.plist"
        if [[ -f "${plist}" ]]; then
            echo "Scheduler: launchd (installed)"
        else
            echo "Scheduler: not installed"
        fi
    else
        if systemctl --user is-active claude-keeper.timer &>/dev/null; then
            echo "Scheduler: systemd timer (active)"
        elif crontab -l 2>/dev/null | grep -q "claude-keeper"; then
            echo "Scheduler: cron (installed)"
        else
            echo "Scheduler: not installed"
        fi
    fi
}

cmd_test() {
    echo "claude-keeper dry run"
    echo "====================="
    echo ""

    # Detect method
    local method
    method="$(detect_install_method)"
    echo "Detected install method: $(describe_method "${method}")"
    echo ""

    # Show what would happen
    echo "What would happen on 'claude-keeper run':"
    local brew_cask=""
    if [[ "${method}" == "homebrew" ]]; then
        local brew_bin
        brew_bin="$(_find_cmd "brew" "${_BREW_PATHS[@]}")" && \
            brew_cask="$(detect_brew_claude_cask "${brew_bin}" 2>/dev/null || true)"
    fi
    case "${method}" in
        homebrew)        echo "  -> brew upgrade --cask ${brew_cask:-claude-code}" ;;
        npm)             echo "  -> npm install -g @anthropic-ai/claude-code" ;;
        winget)          echo "  -> winget upgrade Anthropic.ClaudeCode" ;;
        native)          echo "  -> claude update (safety net; native auto-updates)" ;;
        unknown_in_path) echo "  -> ERROR: Cannot determine upgrade command" ;;
        not_installed)   echo "  -> ERROR: Claude Code not found" ;;
    esac
    echo ""

    # Version
    local version
    version="$(get_claude_version)"
    echo "Current version: ${version:-not available}"

    # Config
    echo ""
    local cfg
    cfg="$(config_path)"
    if [[ -f "${cfg}" ]]; then
        echo "Config file: ${cfg}"
        validate_config 2>&1 | sed 's/^/  /' || true
    else
        echo "Config file: not created yet"
    fi
}

cmd_config() {
    local action="${1:-show}"
    shift || true

    case "${action}" in
        show)
            show_config
            ;;
        set)
            if [[ $# -lt 2 ]]; then
                echo "Usage: claude-keeper config set KEY VALUE"
                echo "Valid keys: enabled, update_time, install_method, log_retention_days, pre_update_hook, post_update_hook"
                exit 1
            fi
            local key="$1"
            local value="$2"

            # Validate known keys
            case "${key}" in
                enabled|update_time|install_method|log_retention_days|pre_update_hook|post_update_hook)
                    write_config "${key}" "${value}"
                    echo "Set ${key}=${value}"
                    # Validate after write
                    if ! validate_config 2>/dev/null; then
                        echo ""
                        echo "Warning: config validation issues:"
                        validate_config 2>&1 | sed 's/^/  /' || true
                    fi
                    ;;
                *)
                    echo "Unknown config key: ${key}"
                    echo "Valid keys: enabled, update_time, install_method, log_retention_days, pre_update_hook, post_update_hook"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Usage: claude-keeper config [show|set KEY VALUE]"
            exit 1
            ;;
    esac
}

cmd_logs() {
    show_logs "${1:-}"
}

cmd_version() {
    echo "claude-keeper v${CLAUDE_KEEPER_VERSION}"
}

cmd_help() {
    cat << 'HELP'
claude-keeper - Auto-updater for Claude Code CLI

USAGE:
    claude-keeper <command> [options]

COMMANDS:
    run              Execute upgrade now (called by scheduler)
    status           Show install method, schedule status, last run
    test             Dry run: detect method, show what would happen
    config           Show current config
    config set K V   Update a config value
    logs             Show recent log entries
    logs --full      Show all log entries
    reconfigure      Re-detect method, update scheduler
    uninstall        Remove claude-keeper completely
    version          Print version
    help             Show this help

EXAMPLES:
    claude-keeper test                          # See what would happen
    claude-keeper run                           # Upgrade now
    claude-keeper config set update_time 14:00  # Change schedule to 2pm
    claude-keeper status                        # Check everything

CONFIG FILE:
    ~/.config/claude-keeper/config

LOGS:
    ~/.local/share/claude-keeper/logs/
HELP
}

cmd_reconfigure() {
    echo "Reconfiguring claude-keeper..."

    # Ensure config exists
    create_default_config

    # Re-detect method
    local method
    method="$(detect_install_method)"
    echo "Detected install method: $(describe_method "${method}")"

    # Get update time from config
    local update_time
    update_time="$(read_config_or_default "update_time" "${DEFAULT_UPDATE_TIME}")"
    echo "Update time: ${update_time}"

    # Set up scheduler
    local hour="${update_time%%:*}"
    local minute="${update_time##*:}"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if [[ -f "${LIB_DIR}/scheduler-macos.sh" ]]; then
            source "${LIB_DIR}/scheduler-macos.sh"
            install_schedule "${hour}" "${minute}"
            echo "Scheduler: launchd configured"
        else
            echo "Scheduler module not found. Skipping."
        fi
    else
        if [[ -f "${LIB_DIR}/scheduler-linux.sh" ]]; then
            source "${LIB_DIR}/scheduler-linux.sh"
            install_schedule "${hour}" "${minute}"
            echo "Scheduler: configured"
        else
            echo "Scheduler module not found. Skipping."
        fi
    fi

    echo ""
    echo "Done. Run 'claude-keeper status' to verify."
}

cmd_uninstall() {
    local uninstall_script="${SCRIPT_DIR}/uninstall.sh"
    if [[ -f "${uninstall_script}" ]]; then
        bash "${uninstall_script}"
    else
        echo "Uninstall script not found at: ${uninstall_script}"
        echo "Manual removal:"
        echo "  1. Remove scheduler (see 'claude-keeper status')"
        echo "  2. rm -rf ~/.local/share/claude-keeper"
        echo "  3. rm -rf ~/.config/claude-keeper"
        echo "  4. rm -f ~/.local/bin/claude-keeper"
        exit 1
    fi
}

# -- Main --

main() {
    local command="${1:-help}"
    shift || true

    case "${command}" in
        run)          cmd_run ;;
        status)       cmd_status ;;
        test)         cmd_test ;;
        config)       cmd_config "$@" ;;
        logs)         cmd_logs "$@" ;;
        version|--version|-v) cmd_version ;;
        help|--help|-h)       cmd_help ;;
        reconfigure)  cmd_reconfigure ;;
        uninstall)    cmd_uninstall ;;
        *)
            echo "Unknown command: ${command}"
            echo "Run 'claude-keeper help' for usage."
            exit 1
            ;;
    esac
}

main "$@"
