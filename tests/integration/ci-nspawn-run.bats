#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="runner"'

	# Provide a base rootfs path in the sandbox.
	mkdir -p "$TEST_ROOT/var/lib/runner/nspawn/base-rootfs"
}

teardown() {
	teardown_test_root
}

@test "ci-nspawn-run: missing command" {
	run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh"
	[ "$status" -ne 0 ]
}

@test "ci-nspawn-run: base rootfs missing" {
	rm -rf "$TEST_ROOT/var/lib/runner/nspawn/base-rootfs"
	run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi
	[ "$status" -ne 0 ]
}

@test "ci-nspawn-run: dry-run records nspawn + systemd-run" {
	run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 GITHUB_WORKSPACE="$TEST_ROOT/work" bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemd-nspawn"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemd-run"
}

@test "ci-nspawn-run: dry-run supports extra binds" {
	run env \
		APPLIANCE_ALLOW_NON_ROOT=1 \
		APPLIANCE_DRY_RUN=1 \
		RUNNER_NSPAWN_BIND="/dev/dri:/dev/dri /dev/input:/dev/input" \
		RUNNER_NSPAWN_BIND_RO="/etc/hosts:/etc/hosts" \
		bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "--bind=/dev/dri:/dev/dri"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "--bind=/dev/input:/dev/input"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "--bind-ro=/etc/hosts:/etc/hosts"
}

@test "ci-nspawn-run: machine timeout cleanup" {
	# Force the wait loop to time out immediately.
	# machinectl show stub exits non-zero by default.
	run env \
		APPLIANCE_ALLOW_NON_ROOT=1 \
		APPLIANCE_DRY_RUN=0 \
		RUNNER_NSPAWN_READY_TIMEOUT_S=0 \
		bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi
	[ "$status" -ne 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "machinectl terminate"
}

@test "ci-nspawn-run: exec path powers off machine" {
	# Make the machine appear immediately.
	run env \
		APPLIANCE_ALLOW_NON_ROOT=1 \
		APPLIANCE_DRY_RUN=0 \
		MACHINECTL_SHOW_EXIT_CODE=0 \
		bash "$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemd-run -M"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "machinectl poweroff"
}
