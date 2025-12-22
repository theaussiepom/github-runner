#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env ''
}

teardown() {
	teardown_test_root
}

@test "healthcheck: primary active" {
	SYSTEMCTL_ACTIVE_PRIMARY=0 run env APPLIANCE_DRY_RUN=0 bash "$APPLIANCE_REPO_ROOT/scripts/healthcheck.sh"
	[ "$status" -eq 0 ]
}

@test "healthcheck: primary inactive (dry-run)" {
	SYSTEMCTL_ACTIVE_PRIMARY=1 run env APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/healthcheck.sh"
	[ "$status" -eq 0 ]
}

@test "healthcheck: primary inactive (start secondary)" {
	SYSTEMCTL_ACTIVE_PRIMARY=1 SYSTEMCTL_ACTIVE_SECONDARY=1 run env APPLIANCE_DRY_RUN=0 bash "$APPLIANCE_REPO_ROOT/scripts/healthcheck.sh"
	[ "$status" -eq 0 ]
}
