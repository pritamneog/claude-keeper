#!/usr/bin/env bash
# Tests for lib/upgrade.sh
# Uses mock commands to verify correct dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/detect.sh"
source "${SCRIPT_DIR}/lib/upgrade.sh"

# -- Test Framework --

_test_count=0
_fail_count=0

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    _test_count=$((_test_count + 1))

    if [[ "${actual}" != "${expected}" ]]; then
        _fail_count=$((_fail_count + 1))
        echo "FAIL: ${label}"
        echo "  expected: '${expected}'"
        echo "  actual:   '${actual}'"
    else
        echo "PASS: ${label}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    _test_count=$((_test_count + 1))

    if [[ "${haystack}" != *"${needle}"* ]]; then
        _fail_count=$((_fail_count + 1))
        echo "FAIL: ${label}"
        echo "  expected to contain: '${needle}'"
        echo "  actual: '${haystack}'"
    else
        echo "PASS: ${label}"
    fi
}

# -- Mock Setup --

MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "${MOCK_DIR}"' EXIT

# Override PATH to intercept commands
export PATH="${MOCK_DIR}:${PATH}"

# Use temp dirs for config/data
export XDG_CONFIG_HOME="${MOCK_DIR}/config"
export XDG_DATA_HOME="${MOCK_DIR}/data"

echo "=== upgrade.sh tests ==="
echo ""

# Test: unknown_in_path returns error
output="$(run_upgrade "unknown_in_path" 2>&1)" || true
assert_contains "${output}" "install method unknown" "unknown_in_path returns helpful error"

# Test: not_installed returns error
output="$(run_upgrade "not_installed" 2>&1)" || true
assert_contains "${output}" "not installed" "not_installed returns error message"

# Test: unknown method returns error
output="$(run_upgrade "flatpak" 2>&1)" || true
assert_contains "${output}" "Unknown install method" "unknown method returns error"

# Test: brew upgrade is called for homebrew
# Mock brew that (a) claims `claude-code` cask is installed for detection,
# (b) echoes the dispatched upgrade command.
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "list" ]]; then
    # Detection: only stable cask "installed"
    [[ "${3:-}" == "claude-code" ]]
    exit $?
fi
echo "mock: brew $*"
exit 0
MOCK
chmod +x "${MOCK_DIR}/brew"

output="$(run_upgrade "homebrew" 2>&1)"
assert_contains "${output}" "mock: brew upgrade --cask claude-code" "homebrew dispatches to brew upgrade --cask (stable)"

# Test: when @latest cask is installed, upgrade targets it
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "list" ]]; then
    [[ "${3:-}" == "claude-code@latest" ]]
    exit $?
fi
echo "mock: brew $*"
exit 0
MOCK
chmod +x "${MOCK_DIR}/brew"

output="$(run_upgrade "homebrew" 2>&1)"
assert_contains "${output}" "mock: brew upgrade --cask claude-code@latest" "homebrew dispatches to brew upgrade --cask claude-code@latest"

# Test: npm install is called for npm
cat > "${MOCK_DIR}/npm" << 'MOCK'
#!/usr/bin/env bash
echo "mock: npm $*"
exit 0
MOCK
chmod +x "${MOCK_DIR}/npm"

output="$(run_upgrade "npm" 2>&1)"
assert_contains "${output}" "mock: npm install -g @anthropic-ai/claude-code" "npm dispatches to npm install -g"

# Test: claude update is called for native
cat > "${MOCK_DIR}/claude" << 'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "update" ]]; then
    echo "mock: claude update"
    exit 0
elif [[ "$1" == "--version" ]]; then
    echo "1.0.0 (mock)"
    exit 0
fi
MOCK
chmod +x "${MOCK_DIR}/claude"

output="$(run_upgrade "native" 2>&1)"
assert_contains "${output}" "mock: claude update" "native dispatches to claude update"

# Test: pre-hook runs and can abort
HOOK_SCRIPT="${MOCK_DIR}/pre-hook.sh"
cat > "${HOOK_SCRIPT}" << 'MOCK'
#!/usr/bin/env bash
echo "pre-hook ran"
exit 1
MOCK
chmod +x "${HOOK_SCRIPT}"

output="$(run_pre_hook "${HOOK_SCRIPT}" 2>&1)" || true
assert_contains "${output}" "pre-hook ran" "pre-hook executes"

# Test: post-hook runs
cat > "${MOCK_DIR}/post-hook.sh" << 'MOCK'
#!/usr/bin/env bash
echo "post-hook ran"
exit 0
MOCK
chmod +x "${MOCK_DIR}/post-hook.sh"

output="$(run_post_hook "${MOCK_DIR}/post-hook.sh" 2>&1)"
assert_contains "${output}" "post-hook ran" "post-hook executes"

# Test: missing hook returns error
output="$(run_pre_hook "/nonexistent/hook.sh" 2>&1)" || true
assert_contains "${output}" "not found" "missing hook reports error"

# -- Summary --

echo ""
echo "$((_test_count - _fail_count))/${_test_count} tests passed"

if [[ "${_fail_count}" -gt 0 ]]; then
    exit 1
fi
