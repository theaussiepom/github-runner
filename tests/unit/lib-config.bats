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
	run appliance_config_env_path
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_ROOT/etc/runner/config.env" ]
}

@test "lib-config: load missing is ok" {
	rm -f "$TEST_ROOT/etc/runner/config.env"
	run load_config_env
	[ "$status" -eq 0 ]
}

@test "lib-config: load present" {
	write_config_env 'RUNNER_TEST_VAR="hello"'
	load_config_env
	[ "$?" -eq 0 ]
	[ "${RUNNER_TEST_VAR:-}" = "hello" ]
}
