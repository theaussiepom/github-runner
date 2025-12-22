#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	# shellcheck source=scripts/lib/common.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/common.sh"
	# shellcheck source=scripts/lib/logging.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh"
	# shellcheck source=scripts/lib/config.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/config.sh"
}

teardown() {
	teardown_test_root
}

@test "lib-config: env default path" {
	unset -v APPLIANCE_CONFIG_ENV
	run appliance_config_env_path
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_ROOT/etc/template-appliance/config.env" ]
}

@test "lib-config: env override path" {
	APPLIANCE_CONFIG_ENV="$TEST_ROOT/custom.env"
	run appliance_config_env_path
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_ROOT/custom.env" ]
}

@test "lib-config: load missing is ok" {
	APPLIANCE_CONFIG_ENV="$TEST_ROOT/missing.env"
	run load_config_env
	[ "$status" -eq 0 ]
}

@test "lib-config: load present" {
	write_config_env 'APPLIANCE_PRIMARY_CMD="echo hello"'
	load_config_env
	[ "$?" -eq 0 ]
	[ "${APPLIANCE_PRIMARY_CMD:-}" = "echo hello" ]
}
