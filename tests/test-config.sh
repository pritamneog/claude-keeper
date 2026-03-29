#!/usr/bin/env bash
# Tests for lib/config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/config.sh"

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

assert_exit() {
    local expected_exit="$1"
    shift
    local label="$1"
    shift
    _test_count=$((_test_count + 1))

    local actual_exit=0
    "$@" >/dev/null 2>&1 || actual_exit=$?

    if [[ "${actual_exit}" -ne "${expected_exit}" ]]; then
        _fail_count=$((_fail_count + 1))
        echo "FAIL: ${label}"
        echo "  expected exit: ${expected_exit}"
        echo "  actual exit:   ${actual_exit}"
    else
        echo "PASS: ${label}"
    fi
}

# -- Setup: use temp config directory --

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

export XDG_CONFIG_HOME="${TEST_DIR}/config"
export XDG_DATA_HOME="${TEST_DIR}/data"

echo "=== config.sh tests ==="
echo ""

# Test: create_default_config creates the file
create_default_config
cfg="$(config_path)"
assert_eq "$(test -f "${cfg}" && echo "exists")" "exists" "create_default_config creates file"

# Test: read_config reads existing values
val="$(read_config "enabled")"
assert_eq "${val}" "true" "read_config reads 'enabled'"

val="$(read_config "update_time")"
assert_eq "${val}" "09:00" "read_config reads 'update_time'"

val="$(read_config "install_method")"
assert_eq "${val}" "auto" "read_config reads 'install_method'"

# Test: read_config returns empty for missing key
val="$(read_config "nonexistent_key")"
assert_eq "${val}" "" "read_config returns empty for missing key"

# Test: write_config updates existing key
write_config "update_time" "14:30"
val="$(read_config "update_time")"
assert_eq "${val}" "14:30" "write_config updates existing key"

# Test: write_config adds new key
write_config "custom_key" "custom_value"
val="$(read_config "custom_key")"
assert_eq "${val}" "custom_value" "write_config adds new key"

# Test: read_config_or_default returns value when present
val="$(read_config_or_default "enabled" "false")"
assert_eq "${val}" "true" "read_config_or_default returns value when present"

# Test: read_config_or_default returns default when absent
val="$(read_config_or_default "absent_key" "default_val")"
assert_eq "${val}" "default_val" "read_config_or_default returns default when absent"

# Test: validate_config passes for valid config
write_config "update_time" "09:00"
assert_exit 0 "validate_config passes for valid config" validate_config

# Test: validate_config fails for invalid time
write_config "update_time" "25:00"
assert_exit 1 "validate_config fails for invalid time (25:00)" validate_config

# Test: validate_config fails for bad enabled value
write_config "update_time" "09:00"
write_config "enabled" "yes"
assert_exit 1 "validate_config fails for invalid enabled (yes)" validate_config

# Test: validate_config fails for bad install_method
write_config "enabled" "true"
write_config "install_method" "apt"
assert_exit 1 "validate_config fails for invalid install_method (apt)" validate_config

# Reset for next test
write_config "install_method" "auto"

# Test: validate_config handles 08:00 without octal error
write_config "update_time" "08:00"
assert_exit 0 "validate_config handles 08:00 (octal-safe)" validate_config

# Test: create_default_config does not overwrite
write_config "update_time" "14:30"
create_default_config
val="$(read_config "update_time")"
assert_eq "${val}" "14:30" "create_default_config preserves existing config"

# -- Summary --

echo ""
echo "$((_test_count - _fail_count))/${_test_count} tests passed"

if [[ "${_fail_count}" -gt 0 ]]; then
    exit 1
fi
