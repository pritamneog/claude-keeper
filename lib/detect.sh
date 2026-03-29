#!/usr/bin/env bash
# claude-keeper: Installation method detection
# Detects how Claude Code was installed on this system.
# Priority: homebrew > npm > winget > native > unknown_in_path > not_installed

set -euo pipefail

# Well-known binary locations for fallback when PATH is minimal (e.g. launchd).
# These are checked when `command -v` fails.
readonly _BREW_PATHS=("/opt/homebrew/bin/brew" "/usr/local/bin/brew" "/home/linuxbrew/.linuxbrew/bin/brew")
readonly _NPM_PATHS=("/opt/homebrew/bin/npm" "/usr/local/bin/npm")
readonly _CLAUDE_NATIVE_PATH="${HOME}/.local/bin/claude"

# Find a command by name, falling back to well-known paths.
# Usage: _find_cmd "brew" "${_BREW_PATHS[@]}"
# Prints the resolved path, or empty string if not found.
_find_cmd() {
    local name="$1"
    shift

    # Try PATH first
    local found
    found="$(command -v "${name}" 2>/dev/null)" && { printf '%s' "${found}"; return 0; }

    # Fall back to well-known locations
    local path
    for path in "$@"; do
        if [[ -x "${path}" ]]; then
            printf '%s' "${path}"
            return 0
        fi
    done

    return 1
}

# Detect the Claude Code installation method.
# Prints one of: homebrew, npm, winget, native, unknown_in_path, not_installed
detect_install_method() {
    # 1. Homebrew (macOS/Linux)
    local brew_bin
    brew_bin="$(_find_cmd "brew" "${_BREW_PATHS[@]}")" || true
    if [[ -n "${brew_bin}" ]]; then
        if "${brew_bin}" list --cask claude-code &>/dev/null 2>&1; then
            printf 'homebrew'
            return 0
        fi
    fi

    # 2. npm
    local npm_bin
    npm_bin="$(_find_cmd "npm" "${_NPM_PATHS[@]}")" || true
    if [[ -n "${npm_bin}" ]]; then
        if "${npm_bin}" list -g @anthropic-ai/claude-code &>/dev/null 2>&1; then
            printf 'npm'
            return 0
        fi
    fi

    # 3. WinGet (Windows/WSL -- unlikely on pure bash but check anyway)
    if command -v winget &>/dev/null; then
        if winget list Anthropic.ClaudeCode &>/dev/null 2>&1; then
            printf 'winget'
            return 0
        fi
    fi

    # 4. Native installer (binary at well-known location)
    if [[ -x "${_CLAUDE_NATIVE_PATH}" ]]; then
        printf 'native'
        return 0
    fi

    # 5. Claude is somewhere in PATH but we can't determine how
    if command -v claude &>/dev/null; then
        printf 'unknown_in_path'
        return 0
    fi

    # 6. Not installed
    printf 'not_installed'
    return 0
}

# Get the current Claude Code version string.
# Returns empty string if claude is not available.
get_claude_version() {
    local claude_bin
    claude_bin="$(_find_cmd "claude" "${_CLAUDE_NATIVE_PATH}")" || true
    if [[ -n "${claude_bin}" ]]; then
        "${claude_bin}" --version 2>/dev/null || printf ''
    else
        printf ''
    fi
}

# Print a human-readable description of the detected method.
describe_method() {
    local method="$1"
    case "${method}" in
        homebrew)        echo "Homebrew (brew upgrade claude-code)" ;;
        npm)             echo "npm (npm install -g @anthropic-ai/claude-code)" ;;
        winget)          echo "WinGet (winget upgrade Anthropic.ClaudeCode)" ;;
        native)          echo "Native installer (claude update)" ;;
        unknown_in_path) echo "Unknown (claude found in PATH but install method unclear)" ;;
        not_installed)   echo "Not installed (claude not found)" ;;
        *)               echo "Unknown method: ${method}" ;;
    esac
}
