#!/usr/bin/env bash
# Tests for lib/detect.sh
# Uses mock commands via PATH manipulation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/detect.sh"

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

# -- Mock Setup --

MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "${MOCK_DIR}"' EXIT

create_mock() {
    local name="$1"
    local exit_code="${2:-0}"
    local output="${3:-}"

    cat > "${MOCK_DIR}/${name}" << MOCK
#!/usr/bin/env bash
if [[ -n "${output}" ]]; then echo "${output}"; fi
exit ${exit_code}
MOCK
    chmod +x "${MOCK_DIR}/${name}"
}

remove_mock() {
    rm -f "${MOCK_DIR}/$1"
}

# Prepend mock dir to PATH
export PATH="${MOCK_DIR}:${PATH}"

# -- Tests --

echo "=== detect.sh tests ==="
echo ""

# Test: homebrew detected when brew list succeeds (stable cask)
remove_mock "brew"
remove_mock "npm"
# Mock: `brew list --cask claude-code@latest` fails, `claude-code` succeeds
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
# Args: list --cask <name>
if [[ "${3:-}" == "claude-code" ]]; then exit 0; fi
exit 1
MOCK
chmod +x "${MOCK_DIR}/brew"
result="$(detect_install_method)"
assert_eq "${result}" "homebrew" "detect homebrew when stable cask is installed"

# Test: homebrew detected when claude-code@latest cask is installed
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
if [[ "${3:-}" == "claude-code@latest" ]]; then exit 0; fi
exit 1
MOCK
chmod +x "${MOCK_DIR}/brew"
result="$(detect_install_method)"
assert_eq "${result}" "homebrew" "detect homebrew when @latest cask is installed"

# Test: detect_brew_claude_cask prefers @latest when both installed
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
# Both casks "installed"
exit 0
MOCK
chmod +x "${MOCK_DIR}/brew"
result="$(detect_brew_claude_cask "${MOCK_DIR}/brew")"
assert_eq "${result}" "claude-code@latest" "prefer @latest cask when both present"

# Test: npm detected when brew fails but npm succeeds
remove_mock "brew"
create_mock "brew" 1 ""
create_mock "npm" 0 "@anthropic-ai/claude-code"
result="$(detect_install_method)"
assert_eq "${result}" "npm" "detect npm when brew fails but npm succeeds"

# Test: homebrew wins over npm when both present
remove_mock "brew"
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
if [[ "${3:-}" == "claude-code" ]]; then exit 0; fi
exit 1
MOCK
chmod +x "${MOCK_DIR}/brew"
create_mock "npm" 0 "@anthropic-ai/claude-code"
result="$(detect_install_method)"
assert_eq "${result}" "homebrew" "homebrew wins priority over npm"

# Test: native detected when binary exists
remove_mock "brew"
remove_mock "npm"
create_mock "brew" 1 ""
create_mock "npm" 1 ""
# Create a fake native binary
mkdir -p "${HOME}/.local/bin"
REAL_CLAUDE="${HOME}/.local/bin/claude"
CLAUDE_EXISTED=0
if [[ -f "${REAL_CLAUDE}" ]]; then
    CLAUDE_EXISTED=1
fi
# We can't safely test native detection without touching the real filesystem.
# Skip this test if claude is already there (since we detected homebrew above).
echo "SKIP: native detection (would modify ~/.local/bin)"

# Test: describe_method outputs correctly
# describe_method for homebrew is now dynamic (reports actual cask);
# just verify it starts with the expected prefix and names a known cask.
cat > "${MOCK_DIR}/brew" << 'MOCK'
#!/usr/bin/env bash
if [[ "${3:-}" == "claude-code@latest" ]]; then exit 0; fi
exit 1
MOCK
chmod +x "${MOCK_DIR}/brew"
desc="$(describe_method "homebrew")"
assert_eq "${desc}" "Homebrew (brew upgrade --cask claude-code@latest)" "describe homebrew method with @latest cask"

desc="$(describe_method "npm")"
assert_eq "${desc}" "npm (npm install -g @anthropic-ai/claude-code)" "describe npm method"

desc="$(describe_method "native")"
assert_eq "${desc}" "Native installer (claude update)" "describe native method"

desc="$(describe_method "not_installed")"
assert_eq "${desc}" "Not installed (claude not found)" "describe not_installed method"

# -- Summary --

echo ""
echo "$((_test_count - _fail_count))/${_test_count} tests passed"

if [[ "${_fail_count}" -gt 0 ]]; then
    exit 1
fi
