#!/usr/bin/env bash
# claude-keeper: Core upgrade logic
# Dispatches the correct upgrade command based on detected installation method.

set -euo pipefail

# -- Internal Helpers --

# Run a command, capturing stdout+stderr and exit code.
# Sets global-ish variables: _upgrade_output, _upgrade_exit_code
_run_upgrade_command() {
    local cmd=("$@")
    _upgrade_output=""
    _upgrade_exit_code=0

    _upgrade_output="$("${cmd[@]}" 2>&1)" || _upgrade_exit_code=$?
}

# -- Public API --

# Execute the upgrade for the given installation method.
# Arguments: method
# Returns: exit code from the upgrade command
# Prints: upgrade output to stdout
run_upgrade() {
    local method="$1"

    case "${method}" in
        native)
            local claude_bin
            claude_bin="$(_resolve_cmd "claude" "${_CLAUDE_NATIVE_PATH}")"
            _run_upgrade_command "${claude_bin}" update
            ;;
        homebrew)
            local brew_bin
            brew_bin="$(_resolve_cmd "brew" "${_BREW_PATHS[@]}")"
            local cask
            cask="$(detect_brew_claude_cask "${brew_bin}" 2>/dev/null)" || cask="claude-code"
            _run_upgrade_command "${brew_bin}" upgrade --cask "${cask}"
            ;;
        npm)
            local npm_bin
            npm_bin="$(_resolve_cmd "npm" "${_NPM_PATHS[@]}")"
            _run_upgrade_command "${npm_bin}" install -g @anthropic-ai/claude-code
            ;;
        winget)
            _run_upgrade_command winget upgrade Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements
            ;;
        unknown_in_path)
            _upgrade_output="Claude found in PATH but install method unknown. Cannot auto-upgrade. Set 'install_method' in config to override."
            _upgrade_exit_code=1
            ;;
        not_installed)
            _upgrade_output="Claude Code is not installed."
            _upgrade_exit_code=1
            ;;
        *)
            _upgrade_output="Unknown install method: ${method}"
            _upgrade_exit_code=1
            ;;
    esac

    if [[ -n "${_upgrade_output}" ]]; then
        printf '%s\n' "${_upgrade_output}"
    fi
    return "${_upgrade_exit_code}"
}

# Run the pre-update hook if configured.
# Returns 0 if no hook is set, or the hook's exit code.
run_pre_hook() {
    local hook_path="$1"

    if [[ -z "${hook_path}" ]]; then
        return 0
    fi

    if [[ ! -f "${hook_path}" ]]; then
        printf 'Pre-update hook not found: %s\n' "${hook_path}" >&2
        return 1
    fi

    if [[ ! -x "${hook_path}" ]]; then
        printf 'Pre-update hook not executable: %s\n' "${hook_path}" >&2
        return 1
    fi

    "${hook_path}" 2>&1
}

# Run the post-update hook if configured.
# Returns 0 if no hook is set, or the hook's exit code.
run_post_hook() {
    local hook_path="$1"

    if [[ -z "${hook_path}" ]]; then
        return 0
    fi

    if [[ ! -f "${hook_path}" ]]; then
        printf 'Post-update hook not found: %s\n' "${hook_path}" >&2
        return 1
    fi

    if [[ ! -x "${hook_path}" ]]; then
        printf 'Post-update hook not executable: %s\n' "${hook_path}" >&2
        return 1
    fi

    "${hook_path}" 2>&1
}

# Full upgrade pipeline: hooks + version capture + upgrade + logging.
# This is the main entry point called by `claude-keeper run`.
# Arguments: method, pre_hook, post_hook
# Resolve a command to its full path, using detect.sh fallback paths.
# This ensures upgrade commands work under launchd's minimal PATH.
_resolve_cmd() {
    local name="$1"
    shift
    _find_cmd "${name}" "$@" || { printf '%s' "${name}"; }
}

# Requires: lib/detect.sh and lib/log.sh to be sourced
run_full_upgrade() {
    local method="$1"
    local pre_hook="${2:-}"
    local post_hook="${3:-}"

    # Capture version before upgrade
    local old_version
    old_version="$(get_claude_version)"

    # Run pre-hook
    if [[ -n "${pre_hook}" ]]; then
        log_info "Running pre-update hook: ${pre_hook}"
        local hook_output hook_exit=0
        hook_output="$(run_pre_hook "${pre_hook}" 2>&1)" || hook_exit=$?
        if [[ "${hook_exit}" -ne 0 ]]; then
            log_error "Pre-update hook failed (exit=${hook_exit}): ${hook_output}"
            return 1
        fi
        if [[ -n "${hook_output}" ]]; then
            log_info "Pre-hook output: ${hook_output}"
        fi
    fi

    # Run upgrade
    log_info "Upgrade started (method=${method})"
    local upgrade_exit=0
    run_upgrade "${method}" || upgrade_exit=$?

    # Capture version after upgrade
    local new_version
    new_version="$(get_claude_version)"

    # Log the result
    log_upgrade_result "${old_version:-unknown}" "${new_version:-unknown}" "${upgrade_exit}" "${method}"

    # Run post-hook (even if upgrade failed -- user may want cleanup)
    if [[ -n "${post_hook}" ]]; then
        log_info "Running post-update hook: ${post_hook}"
        local post_output post_hook_exit=0
        post_output="$(run_post_hook "${post_hook}" 2>&1)" || post_hook_exit=$?
        if [[ "${post_hook_exit}" -ne 0 ]]; then
            log_warn "Post-update hook failed (exit=${post_hook_exit}): ${post_output}"
        fi
        if [[ -n "${post_output}" ]]; then
            log_info "Post-hook output: ${post_output}"
        fi
    fi

    return "${upgrade_exit}"
}
