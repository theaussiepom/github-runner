#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	# Unit tests should not rely on external effects.
	write_config_env 'APPLIANCE_LOG_PREFIX="template-appliance"'

	# shellcheck source=scripts/lib/common.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/common.sh"
	# shellcheck source=scripts/lib/logging.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh"
}

teardown() {
	teardown_test_root
}

@test "lib-common: appliance_is_sourced true/false" {
	local script="$TEST_ROOT/check-sourced.sh"
	cat >"$script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "${APPLIANCE_REPO_ROOT}/scripts/lib/common.sh"
appliance_is_sourced
EOF
	chmod +x "$script"

	# Executed script: not sourced.
	run bash "$script"
	[ "$status" -eq 1 ]

	# Sourced script: sourced.
	run bash -c "source \"$script\""
	[ "$status" -eq 0 ]
}

@test "lib-common: appliance_root normalization" {
	APPLIANCE_ROOT="$TEST_ROOT/" run appliance_root
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_ROOT" ]

	APPLIANCE_ROOT="/" run appliance_root
	[ "$status" -eq 0 ]
	[ "$output" = "/" ]
}

@test "lib-common: appliance_path variants" {
	APPLIANCE_ROOT="$TEST_ROOT" run appliance_path relative.txt
	[ "$status" -eq 0 ]
	[ "$output" = "relative.txt" ]

	APPLIANCE_ROOT="/" run appliance_path /etc/foo
	[ "$status" -eq 0 ]
	[ "$output" = "/etc/foo" ]

	APPLIANCE_ROOT="$TEST_ROOT" run appliance_path /etc/foo
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_ROOT/etc/foo" ]
}

@test "lib-common: appliance_dirname edge cases" {
	run appliance_dirname ""
	[ "$status" -eq 0 ]
	[ "$output" = "." ]

	run appliance_dirname "file"
	[ "$status" -eq 0 ]
	[ "$output" = "." ]

	run appliance_dirname "/"
	[ "$status" -eq 0 ]
	[ "$output" = "/" ]

	run appliance_dirname "/a/b/c/"
	[ "$status" -eq 0 ]
	[ "$output" = "/a/b" ]

	run appliance_dirname "/a"
	[ "$status" -eq 0 ]
	[ "$output" = "/" ]
}

@test "lib-common: record_call primary/append present and absent" {
	# Present
	APPLIANCE_CALLS_FILE="$TEST_ROOT/calls.primary.log"
	APPLIANCE_CALLS_FILE_APPEND="$TEST_ROOT/calls.append.log"
	record_call "hello"
	assert_file_contains "$TEST_ROOT/calls.primary.log" "hello"
	assert_file_contains "$TEST_ROOT/calls.append.log" "hello"

	# Absent
	unset -v APPLIANCE_CALLS_FILE APPLIANCE_CALLS_FILE_APPEND
	record_call "ignored"
}

@test "lib-common: run_cmd dry-run vs exec" {
	APPLIANCE_DRY_RUN=1
	run run_cmd echo hi
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "echo hi"

	APPLIANCE_DRY_RUN=0
	run run_cmd bash -c 'exit 0'
	[ "$status" -eq 0 ]
}

@test "lib-common: appliance_realpath_m" {
	run appliance_realpath_m "/a/../b"
	[ "$status" -eq 0 ]
	[ "$output" = "/b" ]
}
