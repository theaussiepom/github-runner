#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="runner"'

	# Provide a base rootfs path in the sandbox for ci-nspawn-run (used by hooks).
	mkdir -p "$TEST_ROOT/var/lib/runner/nspawn/base-rootfs"
	mkdir -p "$TEST_ROOT/work"
}

teardown() {
	teardown_test_root
}

@test "container-hooks: coverage success paths" {
	local resp_prepare_container="$TEST_ROOT/resp-prepare-container.json"
	local resp_prepare_none="$TEST_ROOT/resp-prepare-none.json"
	local resp_run_script_1="$TEST_ROOT/resp-run-script-1.json"
	local resp_run_script_2="$TEST_ROOT/resp-run-script-2.json"
	local resp_cleanup="$TEST_ROOT/resp-cleanup.json"

	local payload_prepare_container
	payload_prepare_container='{"command":"prepare_job","responseFile":"'$resp_prepare_container'","args":{"container":{"image":"ubuntu:22.04"}},"state":{}}'
	local payload_prepare_none
	payload_prepare_none='{"command":"prepare_job","responseFile":"'$resp_prepare_none'","args":{},"state":{}}'

	local payload_run_script_1
	payload_run_script_1='{"command":"run_script_step","responseFile":"'$resp_run_script_1'","args":{"entryPoint":"echo","entryPointArgs":["hi"],"workingDirectory":"/ci/work","environmentVariables":{"FOO":"bar"},"prependPath":[]},"state":{}}'
	local payload_run_script_2
	payload_run_script_2='{"command":"run_script_step","responseFile":"'$resp_run_script_2'","args":{"entryPoint":"echo","entryPointArgs":["hi"],"environmentVariables":{},"prependPath":[]},"state":{}}'

	local payload_cleanup
	payload_cleanup='{"command":"cleanup_job","responseFile":"'$resp_cleanup'","args":{},"state":{}}'

	run env \
		APPLIANCE_ALLOW_NON_ROOT=1 \
		APPLIANCE_DRY_RUN=1 \
		GITHUB_WORKSPACE="$TEST_ROOT/work" \
		RESP_PREPARE_CONTAINER="$resp_prepare_container" \
		RESP_PREPARE_NONE="$resp_prepare_none" \
		RESP_RUN_SCRIPT_1="$resp_run_script_1" \
		RESP_RUN_SCRIPT_2="$resp_run_script_2" \
		RESP_CLEANUP="$resp_cleanup" \
		PAYLOAD_PREPARE_CONTAINER="$payload_prepare_container" \
		PAYLOAD_PREPARE_NONE="$payload_prepare_none" \
		PAYLOAD_RUN_SCRIPT_1="$payload_run_script_1" \
		PAYLOAD_RUN_SCRIPT_2="$payload_run_script_2" \
		PAYLOAD_CLEANUP="$payload_cleanup" \
		bash -c '
			set -euo pipefail
			source "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"

			main <<<"$PAYLOAD_PREPARE_CONTAINER"
			grep -Fq -- "\"isAlpine\":false" "$RESP_PREPARE_CONTAINER"

			main <<<"$PAYLOAD_PREPARE_NONE"
			grep -Fq -- "\"state\"" "$RESP_PREPARE_NONE"
			! grep -Fq -- "\"isAlpine\"" "$RESP_PREPARE_NONE"

			main <<<"$PAYLOAD_RUN_SCRIPT_1"
			grep -Fq -- "systemd-run" "$APPLIANCE_CALLS_FILE"
			grep -Fq -- "--setenv=FOO=bar" "$APPLIANCE_CALLS_FILE"
			grep -Fq -- "--working-directory=/ci/work" "$APPLIANCE_CALLS_FILE"
			grep -Fq -- "\"state\"" "$RESP_RUN_SCRIPT_1"

			main <<<"$PAYLOAD_RUN_SCRIPT_2"
			grep -Fq -- "\"state\"" "$RESP_RUN_SCRIPT_2"

			main <<<"$PAYLOAD_CLEANUP"
			grep -Fq -- "\"state\"" "$RESP_CLEANUP"
		'
	[ "$status" -eq 0 ]
}

@test "container-hooks: run_container_step fails but writes response" {
	local resp="$TEST_ROOT/resp-run-container.json"
	local payload
	payload='{"command":"run_container_step","responseFile":"'$resp'","args":{},"state":{}}'

	run env APPLIANCE_ALLOW_NON_ROOT=1 PAYLOAD="$payload" bash -c '
		set -euo pipefail
		source "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"
		main <<<"$PAYLOAD"
	'
	[ "$status" -ne 0 ]
	assert_file_contains "$resp" '"state"'
}

@test "container-hooks: unknown command fails but writes response" {
	local resp="$TEST_ROOT/resp-unknown.json"
	local payload
	payload='{"command":"nope","responseFile":"'$resp'","args":{},"state":{}}'

	run env APPLIANCE_ALLOW_NON_ROOT=1 PAYLOAD="$payload" bash -c '
		set -euo pipefail
		source "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"
		main <<<"$PAYLOAD"
	'
	[ "$status" -ne 0 ]
	assert_file_contains "$resp" '"state"'
}

@test "container-hooks: invalid payload fails" {
	local payload
	payload='{"responseFile":"'$TEST_ROOT'/resp.json","args":{},"state":{}}'

	run env APPLIANCE_ALLOW_NON_ROOT=1 PAYLOAD="$payload" bash -c '
		set -euo pipefail
		source "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"
		main <<<"$PAYLOAD"
	'
	[ "$status" -ne 0 ]
}
