#!/usr/bin/env bash
# Tests for scheduler modules
# Only tests the macOS scheduler on Darwin, Linux scheduler on Linux.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source dependencies
export XDG_DATA_HOME="$(mktemp -d)/data"
source "${SCRIPT_DIR}/lib/log.sh"

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

OS="$(uname -s)"

echo "=== scheduler tests (${OS}) ==="
echo ""

if [[ "${OS}" == "Darwin" ]]; then
    source "${SCRIPT_DIR}/lib/scheduler-macos.sh"

    # Test: _generate_plist produces valid XML
    plist_content="$(_generate_plist 9 30 "/tmp/test.sh" "/tmp/stdout.log" "/tmp/stderr.log")"
    assert_contains "${plist_content}" "<integer>9</integer>" "plist contains correct hour"
    assert_contains "${plist_content}" "<integer>30</integer>" "plist contains correct minute"
    assert_contains "${plist_content}" "/tmp/test.sh" "plist contains script path"
    assert_contains "${plist_content}" "com.claude-keeper.updater" "plist contains correct label"
    assert_contains "${plist_content}" "<false/>" "plist has RunAtLoad false"

    # Test: handles leading-zero times (e.g., 08:05)
    plist_content="$(_generate_plist 8 5 "/tmp/test.sh" "/tmp/stdout.log" "/tmp/stderr.log")"
    assert_contains "${plist_content}" "<integer>8</integer>" "plist handles hour 8 correctly"
    assert_contains "${plist_content}" "<integer>5</integer>" "plist handles minute 5 correctly"

    # Note: We do NOT test install_schedule/uninstall_schedule here because
    # they modify real system state (launchctl load/unload). Those are tested
    # via the integration test (install.sh --local + uninstall.sh).

else
    source "${SCRIPT_DIR}/lib/scheduler-linux.sh"

    # Test: _generate_service produces valid unit
    service_content="$(_generate_service "/tmp/test.sh")"
    assert_contains "${service_content}" "ExecStart=/bin/bash /tmp/test.sh run" "service has correct ExecStart"
    assert_contains "${service_content}" "Type=oneshot" "service is oneshot"

    # Test: _generate_timer produces valid timer
    timer_content="$(_generate_timer 14 30)"
    assert_contains "${timer_content}" "OnCalendar=*-*-* 14:30:00" "timer has correct calendar"
    assert_contains "${timer_content}" "Persistent=true" "timer is persistent"

    # Test: handles leading-zero times
    timer_content="$(_generate_timer 08 05)"
    assert_contains "${timer_content}" "OnCalendar=*-*-* 08:05:00" "timer handles 08:05 correctly"
fi

# -- Summary --

echo ""
echo "$((_test_count - _fail_count))/${_test_count} tests passed"

if [[ "${_fail_count}" -gt 0 ]]; then
    exit 1
fi
