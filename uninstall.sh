#!/usr/bin/env bash
# claude-keeper uninstaller for macOS and Linux

set -euo pipefail

readonly INSTALL_DIR="${HOME}/.local/share/claude-keeper"
readonly BIN_LINK="${HOME}/.local/bin/claude-keeper"
readonly CONFIG_DIR="${HOME}/.config/claude-keeper"

info() {
    printf '\033[1;34m==>\033[0m %s\n' "$1"
}

success() {
    printf '\033[1;32m==>\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33mWARN:\033[0m %s\n' "$1"
}

KEEP_CONFIG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-config)
            KEEP_CONFIG=1
            ;;
        --help|-h)
            echo "claude-keeper uninstaller"
            echo ""
            echo "Usage: bash uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-config   Keep config file after removal"
            echo "  --help          Show this help"
            exit 0
            ;;
        *)
            warn "Unknown option: $1 (ignoring)"
            ;;
    esac
    shift
done

info "Uninstalling claude-keeper..."

# -- Remove Scheduler --

OS="$(uname -s)"

if [[ "${OS}" == "Darwin" ]]; then
    # macOS: launchd
    plist="${HOME}/Library/LaunchAgents/com.claude-keeper.updater.plist"
    if [[ -f "${plist}" ]]; then
        launchctl unload "${plist}" 2>/dev/null || true
        rm -f "${plist}"
        info "Removed launchd plist"
    fi
else
    # Linux: systemd
    if systemctl --user is-enabled claude-keeper.timer &>/dev/null 2>&1; then
        systemctl --user stop claude-keeper.timer 2>/dev/null || true
        systemctl --user disable claude-keeper.timer 2>/dev/null || true
        info "Disabled systemd timer"
    fi
    rm -f "${HOME}/.config/systemd/user/claude-keeper.service" \
          "${HOME}/.config/systemd/user/claude-keeper.timer"
    systemctl --user daemon-reload 2>/dev/null || true

    # Cron
    if crontab -l 2>/dev/null | grep -q "claude-keeper"; then
        crontab -l 2>/dev/null | grep -v "claude-keeper" | crontab - 2>/dev/null || true
        info "Removed cron entry"
    fi
fi

# -- Remove Symlink --

if [[ -L "${BIN_LINK}" ]] || [[ -f "${BIN_LINK}" ]]; then
    rm -f "${BIN_LINK}"
    info "Removed symlink: ${BIN_LINK}"
fi

# -- Remove Install Directory --

if [[ -d "${INSTALL_DIR}" ]]; then
    rm -rf "${INSTALL_DIR}"
    info "Removed install directory: ${INSTALL_DIR}"
fi

# -- Remove Config (optional) --

if [[ "${KEEP_CONFIG}" -eq 0 ]]; then
    if [[ -d "${CONFIG_DIR}" ]]; then
        rm -rf "${CONFIG_DIR}"
        info "Removed config directory: ${CONFIG_DIR}"
    fi
else
    if [[ -d "${CONFIG_DIR}" ]]; then
        warn "Config preserved at: ${CONFIG_DIR}"
    fi
fi

echo ""
success "claude-keeper has been uninstalled."
