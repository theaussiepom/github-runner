#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="runner"'

	# Provide a base rootfs path in the sandbox for ci-nspawn-run (used by hooks).
	mkdir -p "$TEST_ROOT/var/lib/runner/nspawn/base-rootfs"
}

teardown() {
	teardown_test_root
}

@test "runner-service: missing runner fails" {
	run env APPLIANCE_ALLOW_NON_ROOT=1 bash "$APPLIANCE_REPO_ROOT/scripts/runner-service.sh"
	[ "$status" -ne 0 ]
}

@test "runner-service: no container hooks still runs" {
	mkdir -p "$TEST_ROOT/opt/runner/actions-runner"
	cat >"$TEST_ROOT/opt/runner/actions-runner/runsvc.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/opt/runner/actions-runner/runsvc.sh"

	run env APPLIANCE_ALLOW_NON_ROOT=1 bash "$APPLIANCE_REPO_ROOT/scripts/runner-service.sh"
	[ "$status" -eq 0 ]
}

@test "runner-service: sets container hooks when present" {
	mkdir -p "$TEST_ROOT/opt/runner/actions-runner"
	cat >"$TEST_ROOT/opt/runner/actions-runner/runsvc.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${ACTIONS_RUNNER_CONTAINER_HOOKS:-}" ]]; then
	# Fail if hooks weren't set.
	exit 2
fi
exit 0
EOF
	chmod +x "$TEST_ROOT/opt/runner/actions-runner/runsvc.sh"

	mkdir -p "$TEST_ROOT/usr/local/lib/runner"
	cat >"$TEST_ROOT/usr/local/lib/runner/container-hooks.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/usr/local/lib/runner/container-hooks.sh"

	run env APPLIANCE_ALLOW_NON_ROOT=1 bash "$APPLIANCE_REPO_ROOT/scripts/runner-service.sh"
	[ "$status" -eq 0 ]
}

@test "container-hooks: prepare_job writes response" {
	local resp="$TEST_ROOT/resp.json"
	local payload
	payload='{"command":"prepare_job","responseFile":"'$resp'","args":{"container":{"image":"ubuntu:22.04"}},"state":{}}'

	run env APPLIANCE_ALLOW_NON_ROOT=1 bash "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh" <<<"$payload"
	[ "$status" -eq 0 ]
	assert_file_contains "$resp" '"isAlpine":false'
}

@test "container-hooks: run_script_step routes through ci-nspawn-run" {
	mkdir -p "$TEST_ROOT/work"
	local resp="$TEST_ROOT/resp.json"
	local payload
	payload='{"command":"run_script_step","responseFile":"'$resp'","args":{"entryPoint":"echo","entryPointArgs":["hi"],"workingDirectory":"/ci/work","environmentVariables":{"FOO":"bar"},"prependPath":[]},"state":{}}'

	run env \
		APPLIANCE_ALLOW_NON_ROOT=1 \
		APPLIANCE_DRY_RUN=1 \
		GITHUB_WORKSPACE="$TEST_ROOT/work" \
		bash "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh" <<<"$payload"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemd-run"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "--setenv=FOO=bar"
	assert_file_contains "$APPLIANCE_CALLS_FILE" "--working-directory=/ci/work"
	assert_file_contains "$resp" '"state"'
}

@test "container-hooks: cleanup_job writes response" {
	local resp="$TEST_ROOT/resp.json"
	local payload
	payload='{"command":"cleanup_job","responseFile":"'$resp'","args":{},"state":{}}'

	run env APPLIANCE_ALLOW_NON_ROOT=1 bash "$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh" <<<"$payload"
	[ "$status" -eq 0 ]
	assert_file_contains "$resp" '"state"'
}
