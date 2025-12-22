#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	# shellcheck source=scripts/lib/common.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/common.sh"
	# shellcheck source=scripts/lib/logging.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh"
}

teardown() {
	teardown_test_root
}

@test "lib-logging: prefix default/override" {
	unset -v APPLIANCE_LOG_PREFIX
	run appliance_log_prefix
	[ "$status" -eq 0 ]
	[ "$output" = "runner" ]

	APPLIANCE_LOG_PREFIX="custom"
	run appliance_log_prefix
	[ "$status" -eq 0 ]
	[ "$output" = "custom" ]
}

@test "lib-logging: log/warn" {
	APPLIANCE_LOG_PREFIX="t"
	run log "hello"
	[ "$status" -eq 0 ]

	run warn "oops"
	[ "$status" -eq 0 ]
}

@test "lib-logging: die exits non-zero" {
	APPLIANCE_LOG_PREFIX="t"
	run bash -c "source \"$APPLIANCE_REPO_ROOT/scripts/lib/common.sh\"; source \"$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh\"; die boom"
	[ "$status" -ne 0 ]
}
