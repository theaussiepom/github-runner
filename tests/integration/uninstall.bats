#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="runner"'
}

teardown() {
	teardown_test_root
}

@test "uninstall: require_root branches" {
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=1; source \"$APPLIANCE_REPO_ROOT/scripts/uninstall.sh\"; require_root"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=0; export APPLIANCE_EUID_OVERRIDE=1000; source \"$APPLIANCE_REPO_ROOT/scripts/uninstall.sh\"; require_root"
	[ "$status" -ne 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=0; export APPLIANCE_EUID_OVERRIDE=0; source \"$APPLIANCE_REPO_ROOT/scripts/uninstall.sh\"; require_root"
	[ "$status" -eq 0 ]
}

@test "uninstall: dry-run removes everything (safe on partial install)" {
	# Create partial install artifacts.
	mkdir -p "$TEST_ROOT/usr/local/lib/runner" "$TEST_ROOT/usr/local/bin" "$TEST_ROOT/etc/systemd/system" "$TEST_ROOT/var/lib/runner"
	touch "$TEST_ROOT/etc/systemd/system/runner.service"
	touch "$TEST_ROOT/etc/systemd/system/runner-install.service"
	touch "$TEST_ROOT/usr/local/bin/ci-nspawn-run"
	touch "$TEST_ROOT/usr/local/bin/runner-uninstall"
	touch "$TEST_ROOT/var/lib/runner/installed"

	run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/uninstall.sh"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemctl disable --now runner.service"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "rm -f"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "rm -rf"
}
