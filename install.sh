#!/usr/bin/env bash
# claude-keeper installer for macOS and Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/<user>/claude-keeper/main/install.sh | bash
# Or: bash install.sh [--time HH:MM]

set -euo pipefail

# -- Constants --

readonly INSTALL_DIR="${HOME}/.local/share/claude-keeper"
readonly BIN_LINK="${HOME}/.local/bin/claude-keeper"
readonly REPO_BASE="https://raw.githubusercontent.com/pritamneog/claude-keeper/main"

# Files to download (relative to repo root)
readonly FILES=(
    "claude-keeper.sh"
    "lib/log.sh"
    "lib/config.sh"
    "lib/detect.sh"
    "lib/upgrade.sh"
    "lib/scheduler-macos.sh"
    "lib/scheduler-linux.sh"
    "uninstall.sh"
)

# -- Helpers --

info() {
    printf '\033[1;34m==>\033[0m %s\n' "$1"
}

success() {
    printf '\033[1;32m==>\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33mWARN:\033[0m %s\n' "$1"
}

error() {
    printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2
}

die() {
    error "$1"
    exit 1
}

# -- Argument Parsing --

UPDATE_TIME="09:00"
LOCAL_INSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --time)
            shift
            UPDATE_TIME="${1:-}"
            if [[ -z "${UPDATE_TIME}" ]]; then
                die "--time requires a value in HH:MM format"
            fi
            if ! [[ "${UPDATE_TIME}" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
                die "Invalid time format: ${UPDATE_TIME}. Use HH:MM (24h)."
            fi
            local_hour="${UPDATE_TIME%%:*}"
            if [[ "$((10#${local_hour}))" -gt 23 ]]; then
                die "Invalid hour: ${local_hour}. Must be 0-23."
            fi
            ;;
        --local)
            LOCAL_INSTALL=1
            ;;
        --help|-h)
            echo "claude-keeper installer"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --time HH:MM    Set daily update time (default: 09:00)"
            echo "  --local         Install from local files instead of GitHub"
            echo "  --help          Show this help"
            exit 0
            ;;
        *)
            die "Unknown option: $1. Use --help for usage."
            ;;
    esac
    shift
done

# -- Preflight Checks --

info "claude-keeper installer"
echo ""

# Check OS
OS="$(uname -s)"
case "${OS}" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      die "Unsupported OS: ${OS}. Use install.ps1 for Windows." ;;
esac
info "Platform: ${PLATFORM}"

# Check for claude
if ! command -v claude &>/dev/null; then
    warn "Claude Code not found in PATH."
    warn "Install Claude Code first, then re-run this installer."
    warn "Continuing anyway (claude-keeper will detect on first run)..."
fi

# Check for curl
if ! command -v curl &>/dev/null; then
    die "curl is required but not found. Install curl and try again."
fi

# -- Installation --

# Check for existing installation
if [[ -d "${INSTALL_DIR}" ]]; then
    info "Existing installation found. Reconfiguring..."
    RECONFIGURE=1
else
    RECONFIGURE=0
fi

# Create directories
info "Installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/lib" "${INSTALL_DIR}/logs"
mkdir -p "$(dirname "${BIN_LINK}")"

if [[ "${LOCAL_INSTALL}" -eq 1 ]]; then
    # Install from local directory (for development)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    info "Installing from local: ${SCRIPT_DIR}"

    cp "${SCRIPT_DIR}/claude-keeper.sh" "${INSTALL_DIR}/bin/claude-keeper.sh"
    cp "${SCRIPT_DIR}/lib/"*.sh "${INSTALL_DIR}/lib/"
    if [[ -f "${SCRIPT_DIR}/uninstall.sh" ]]; then
        cp "${SCRIPT_DIR}/uninstall.sh" "${INSTALL_DIR}/uninstall.sh"
    fi
else
    # Download from GitHub
    info "Downloading from GitHub..."

    # Download checksum manifest first (if available)
    CHECKSUM_FILE="${INSTALL_DIR}/checksums.sha256"
    HAS_CHECKSUMS=0
    curl -fsSL "${REPO_BASE}/checksums.sha256" -o "${CHECKSUM_FILE}" 2>/dev/null && HAS_CHECKSUMS=1 || true

    for file in "${FILES[@]}"; do
        dest_path="${INSTALL_DIR}"
        case "${file}" in
            claude-keeper.sh)   dest_path="${INSTALL_DIR}/bin/claude-keeper.sh" ;;
            lib/*)              dest_path="${INSTALL_DIR}/${file}" ;;
            uninstall.sh)       dest_path="${INSTALL_DIR}/uninstall.sh" ;;
        esac

        mkdir -p "$(dirname "${dest_path}")"
        curl -fsSL "${REPO_BASE}/${file}" -o "${dest_path}" || {
            # Critical files must download successfully
            case "${file}" in
                uninstall.sh)
                    warn "Failed to download ${file}. Skipping (non-critical)."
                    continue
                    ;;
                *)
                    die "Failed to download required file: ${file}"
                    ;;
            esac
        }

        # Verify checksum if manifest is available
        if [[ "${HAS_CHECKSUMS}" -eq 1 ]]; then
            expected_hash="$(grep " ${file}$" "${CHECKSUM_FILE}" 2>/dev/null | awk '{print $1}')"
            if [[ -n "${expected_hash}" ]]; then
                if command -v sha256sum &>/dev/null; then
                    actual_hash="$(sha256sum "${dest_path}" | awk '{print $1}')"
                elif command -v shasum &>/dev/null; then
                    actual_hash="$(shasum -a 256 "${dest_path}" | awk '{print $1}')"
                else
                    warn "No sha256sum/shasum found. Skipping integrity check."
                    actual_hash="${expected_hash}"
                fi
                if [[ "${expected_hash}" != "${actual_hash}" ]]; then
                    die "Integrity check failed for ${file}: expected ${expected_hash}, got ${actual_hash}"
                fi
            fi
        fi
    done
    rm -f "${CHECKSUM_FILE}" 2>/dev/null || true
fi

# Make executable
chmod +x "${INSTALL_DIR}/bin/claude-keeper.sh"
chmod +x "${INSTALL_DIR}/lib/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true

# Create symlink
if [[ -L "${BIN_LINK}" ]] || [[ -f "${BIN_LINK}" ]]; then
    rm -f "${BIN_LINK}"
fi
ln -s "${INSTALL_DIR}/bin/claude-keeper.sh" "${BIN_LINK}"
info "Symlinked: ${BIN_LINK} -> ${INSTALL_DIR}/bin/claude-keeper.sh"

# -- Configuration --

# Source config module to create default config
source "${INSTALL_DIR}/lib/log.sh"
source "${INSTALL_DIR}/lib/config.sh"
create_default_config

# Set the update time
write_config "update_time" "${UPDATE_TIME}"
info "Update time set to: ${UPDATE_TIME}"

# -- Detection --

source "${INSTALL_DIR}/lib/detect.sh"
METHOD="$(detect_install_method)"
info "Detected install method: $(describe_method "${METHOD}")"

if [[ "${METHOD}" == "native" ]]; then
    warn "Native installs auto-update already."
    warn "claude-keeper will run 'claude update' as a safety net."
fi

# -- Scheduler Setup --

HOUR="${UPDATE_TIME%%:*}"
MINUTE="${UPDATE_TIME##*:}"

if [[ "${PLATFORM}" == "macos" ]]; then
    source "${INSTALL_DIR}/lib/scheduler-macos.sh"
    install_schedule "${HOUR}" "${MINUTE}"
    info "Scheduler: launchd configured (daily at ${UPDATE_TIME})"
else
    source "${INSTALL_DIR}/lib/scheduler-linux.sh"
    install_schedule "${HOUR}" "${MINUTE}"
    if _has_systemd_user 2>/dev/null; then
        info "Scheduler: systemd timer configured (daily at ${UPDATE_TIME})"
    else
        info "Scheduler: cron configured (daily at ${UPDATE_TIME})"
    fi
fi

# -- Summary --

echo ""
success "claude-keeper installed successfully!"
echo ""
echo "  Install dir:  ${INSTALL_DIR}"
echo "  Config:       $(config_path)"
echo "  Logs:         $(log_dir)/"
echo "  Schedule:     Daily at ${UPDATE_TIME}"
echo "  Method:       $(describe_method "${METHOD}")"
echo ""
echo "  Commands:"
echo "    claude-keeper status           # Check status"
echo "    claude-keeper run              # Upgrade now"
echo "    claude-keeper test             # Dry run"
echo "    claude-keeper config set K V   # Change settings"
echo "    claude-keeper uninstall        # Remove completely"
echo ""

# Check if ~/.local/bin is in PATH
if ! echo "${PATH}" | tr ':' '\n' | grep -q "${HOME}/.local/bin"; then
    warn "~/.local/bin is not in your PATH."
    warn "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo ""
fi
