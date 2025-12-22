#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="template-appliance"'
}

teardown() {
	teardown_test_root
}

@test "install: require_root branches" {
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; require_root"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=0; export APPLIANCE_EUID_OVERRIDE=1000; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; require_root"
	[ "$status" -ne 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_ALLOW_NON_ROOT=0; export APPLIANCE_EUID_OVERRIDE=0; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; require_root"
	[ "$status" -eq 0 ]
}

@test "install: marker present early" {
	write_config_env ''
	touch "$TEST_ROOT/var/lib/template-appliance/installed"
	run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: lock busy" {
	write_config_env ''
	APPLIANCE_STUB_FLOCK_EXIT_CODE=1 run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -ne 0 ]
}

@test "install: marker appears while waiting for lock" {
	write_config_env ''
	marker="$TEST_ROOT/var/lib/template-appliance/installed"
	APPLIANCE_STUB_FLOCK_EXIT_CODE=0 APPLIANCE_STUB_FLOCK_TOUCH_MARKER=1 APPLIANCE_INSTALLED_MARKER="$marker" run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: full dry-run flow reaches optional-features-none and writes marker (dry-run)" {
	write_config_env ''
	ID_APPLIANCE_EXISTS=1 APPLIANCE_STUB_FLOCK_EXIT_CODE=0 run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: ensure_user branches" {
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; ensure_user"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export ID_APPLIANCE_EXISTS=0; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; ensure_user"
	[ "$status" -eq 0 ]
}

@test "install: write_marker dry-run vs write" {
	marker="$TEST_ROOT/var/lib/template-appliance/installed"
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_INSTALLED_MARKER=\"$marker\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; write_marker"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=0; export APPLIANCE_INSTALLED_MARKER=\"$marker\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; write_marker"
	[ "$status" -eq 0 ]
	[ -f "$marker" ]
}
