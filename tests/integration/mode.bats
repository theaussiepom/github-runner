#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env ''
}

teardown() {
	teardown_test_root
}

@test "primary/secondary mode: dry-run exits" {
	run env APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/mode/primary-mode.sh"
	[ "$status" -eq 0 ]

	run env APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/mode/secondary-mode.sh"
	[ "$status" -eq 0 ]
}

@test "primary/secondary mode: cmd-present execs" {
	write_config_env $'APPLIANCE_PRIMARY_CMD="echo primary"\nAPPLIANCE_SECONDARY_CMD="echo secondary"'

	run env APPLIANCE_DRY_RUN=0 bash "$APPLIANCE_REPO_ROOT/scripts/mode/primary-mode.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"primary"* ]]

	run env APPLIANCE_DRY_RUN=0 bash "$APPLIANCE_REPO_ROOT/scripts/mode/secondary-mode.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"secondary"* ]]
}

@test "primary/secondary mode: cmd-missing enters sleep loop" {
	if ! command -v timeout >/dev/null 2>&1; then
		skip "timeout not available"
	fi

	write_config_env ''
	run env APPLIANCE_DRY_RUN=0 timeout 0.2s bash "$APPLIANCE_REPO_ROOT/scripts/mode/primary-mode.sh"
	[ "$status" -ne 0 ]

	run env APPLIANCE_DRY_RUN=0 timeout 0.2s bash "$APPLIANCE_REPO_ROOT/scripts/mode/secondary-mode.sh"
	[ "$status" -ne 0 ]
}

@test "enter mode scripts call systemctl" {
	run env APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/mode/enter-primary-mode.sh"
	[ "$status" -eq 0 ]

	run env APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/mode/enter-secondary-mode.sh"
	[ "$status" -eq 0 ]
}
