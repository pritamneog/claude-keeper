#!/usr/bin/env bash
# claude-keeper: Configuration management
# Safe config read/write/validate. Parsed with grep|cut, NEVER source'd.

set -euo pipefail

# -- Constants --

readonly CONFIG_DIR_NAME="claude-keeper"
readonly CONFIG_FILE_NAME="config"

readonly DEFAULT_ENABLED="true"
readonly DEFAULT_UPDATE_TIME="09:00"
readonly DEFAULT_INSTALL_METHOD="auto"
readonly DEFAULT_LOG_RETENTION_DAYS="30"
readonly DEFAULT_PRE_UPDATE_HOOK=""
readonly DEFAULT_POST_UPDATE_HOOK=""

# -- Directory Resolution --

config_dir() {
    if [[ "${XDG_CONFIG_HOME:-}" != "" ]]; then
        printf '%s/%s' "${XDG_CONFIG_HOME}" "${CONFIG_DIR_NAME}"
    else
        printf '%s/.config/%s' "${HOME}" "${CONFIG_DIR_NAME}"
    fi
}

config_path() {
    printf '%s/%s' "$(config_dir)" "${CONFIG_FILE_NAME}"
}

# -- Internal Helpers --

_ensure_config_dir() {
    local dir
    dir="$(config_dir)"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
    fi
}

# -- Public API --

# Read a single config value. Returns empty string if key not found.
# Usage: read_config "update_time"
read_config() {
    local key="$1"
    local cfg
    cfg="$(config_path)"

    if [[ ! -f "${cfg}" ]]; then
        return 0
    fi

    # Safe parsing: grep for key=, extract value after first =
    # Strips inline comments and trims whitespace
    local value
    value="$(grep -m1 "^${key}=" "${cfg}" 2>/dev/null | cut -d= -f2- | sed 's/#.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" || true
    printf '%s' "${value}"
}

# Write a config key-value pair. Creates the file if it doesn't exist.
# If the key already exists, the line is replaced (immutable: writes new file).
# Usage: write_config "update_time" "14:00"
write_config() {
    local key="$1"
    local value="$2"

    _ensure_config_dir

    local cfg
    cfg="$(config_path)"

    if [[ ! -f "${cfg}" ]]; then
        printf '%s=%s\n' "${key}" "${value}" > "${cfg}"
        return 0
    fi

    # Build new file content (immutable pattern: write new, then replace)
    # Use config-dir-local temp file to avoid leaking to world-readable /tmp
    local tmp
    tmp="$(mktemp "$(config_dir)/config.tmp.XXXXXX")"
    # Clean up temp file on any exit path (signal, error, set -e)
    trap 'rm -f "${tmp}" 2>/dev/null' RETURN

    local found=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${key}="* ]]; then
            printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
            found=1
        else
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${cfg}"

    if [[ "${found}" -eq 0 ]]; then
        printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    fi

    mv "${tmp}" "${cfg}"
    # Disarm the trap since mv succeeded (file no longer exists at tmp path)
    trap - RETURN
}

# Validate all config values. Prints errors to stderr, returns non-zero on failure.
validate_config() {
    local errors=0

    local enabled
    enabled="$(read_config "enabled")"
    if [[ -n "${enabled}" ]] && [[ "${enabled}" != "true" ]] && [[ "${enabled}" != "false" ]]; then
        echo "ERROR: 'enabled' must be 'true' or 'false', got '${enabled}'" >&2
        errors=$((errors + 1))
    fi

    local update_time
    update_time="$(read_config "update_time")"
    if [[ -n "${update_time}" ]]; then
        if ! [[ "${update_time}" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
            echo "ERROR: 'update_time' must be HH:MM (24h), got '${update_time}'" >&2
            errors=$((errors + 1))
        else
            local hour
            hour="${update_time%%:*}"
            if [[ "$((10#${hour}))" -gt 23 ]]; then
                echo "ERROR: 'update_time' hour must be 0-23, got '${hour}'" >&2
                errors=$((errors + 1))
            fi
        fi
    fi

    local install_method
    install_method="$(read_config "install_method")"
    if [[ -n "${install_method}" ]]; then
        case "${install_method}" in
            auto|native|homebrew|npm|winget) ;;
            *)
                echo "ERROR: 'install_method' must be one of auto|native|homebrew|npm|winget, got '${install_method}'" >&2
                errors=$((errors + 1))
                ;;
        esac
    fi

    local log_retention_days
    log_retention_days="$(read_config "log_retention_days")"
    if [[ -n "${log_retention_days}" ]]; then
        if ! [[ "${log_retention_days}" =~ ^[0-9]+$ ]]; then
            echo "ERROR: 'log_retention_days' must be a non-negative integer, got '${log_retention_days}'" >&2
            errors=$((errors + 1))
        fi
    fi

    local pre_hook
    pre_hook="$(read_config "pre_update_hook")"
    if [[ -n "${pre_hook}" ]] && [[ ! -x "${pre_hook}" ]]; then
        echo "WARN: 'pre_update_hook' is set but not executable: ${pre_hook}" >&2
    fi

    local post_hook
    post_hook="$(read_config "post_update_hook")"
    if [[ -n "${post_hook}" ]] && [[ ! -x "${post_hook}" ]]; then
        echo "WARN: 'post_update_hook' is set but not executable: ${post_hook}" >&2
    fi

    [[ "${errors}" -eq 0 ]] && return 0 || return 1
}

# Create a default config file. Does not overwrite existing config.
create_default_config() {
    _ensure_config_dir

    local cfg
    cfg="$(config_path)"

    if [[ -f "${cfg}" ]]; then
        return 0
    fi

    cat > "${cfg}" << 'CONF'
# claude-keeper configuration
# Run 'claude-keeper reconfigure' after changing update_time

# Enable or disable auto-updates (true/false)
enabled=true

# Time to run daily update (24h format, HH:MM)
update_time=09:00

# Installation method override (auto-detected if 'auto')
# Valid: auto, native, homebrew, npm, winget
install_method=auto

# Log retention in days (0 = keep forever)
log_retention_days=30

# Pre-update hook (optional path to script run before upgrade)
pre_update_hook=

# Post-update hook (optional path to script run after upgrade)
post_update_hook=
CONF
}

# Print the current config to stdout.
show_config() {
    local cfg
    cfg="$(config_path)"

    if [[ ! -f "${cfg}" ]]; then
        echo "No config file found at ${cfg}"
        echo "Run 'claude-keeper reconfigure' to create one."
        return 1
    fi

    echo "Config: ${cfg}"
    echo "---"
    cat "${cfg}"
}

# Get config value with a fallback default.
read_config_or_default() {
    local key="$1"
    local default="$2"
    local value
    value="$(read_config "${key}")"
    if [[ -z "${value}" ]]; then
        printf '%s' "${default}"
    else
        printf '%s' "${value}"
    fi
}
