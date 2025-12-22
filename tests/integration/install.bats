#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	write_config_env 'APPLIANCE_LOG_PREFIX="runner"'
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
	touch "$TEST_ROOT/var/lib/runner/installed"
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
	marker="$TEST_ROOT/var/lib/runner/installed"
	APPLIANCE_STUB_FLOCK_EXIT_CODE=0 APPLIANCE_STUB_FLOCK_TOUCH_MARKER=1 APPLIANCE_INSTALLED_MARKER="$marker" run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: full dry-run flow reaches optional-features-none and writes marker (dry-run)" {
	write_config_env ''
	ID_APPLIANCE_EXISTS=1 APPLIANCE_STUB_FLOCK_EXIT_CODE=0 run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: auto-installs systemd-container when systemd-nspawn missing and installable" {
	write_config_env ''

	# Use an isolated PATH that includes apt-cache but *not* systemd-nspawn,
	# so install.sh takes the auto-install branch.
	make_isolated_path_with_stubs apt-cache dirname flock id getent

	ID_APPLIANCE_EXISTS=1 \
		APPLIANCE_STUB_FLOCK_EXIT_CODE=0 \
		APT_CACHE_HAS_SYSTEMD_CONTAINER=1 \
		run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: does not auto-install systemd-container when systemd-nspawn missing but not installable" {
	write_config_env ''

	make_isolated_path_with_stubs apt-cache dirname flock id getent

	ID_APPLIANCE_EXISTS=1 \
		APPLIANCE_STUB_FLOCK_EXIT_CODE=0 \
		APT_CACHE_HAS_SYSTEMD_CONTAINER=0 \
		run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
}

@test "install: ensure_user branches" {
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; ensure_user"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export ID_APPLIANCE_EXISTS=0; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; ensure_user"
	[ "$status" -eq 0 ]
}

@test "install: write_marker dry-run vs write" {
	marker="$TEST_ROOT/var/lib/runner/installed"
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_INSTALLED_MARKER=\"$marker\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; write_marker"
	[ "$status" -eq 0 ]

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=0; export APPLIANCE_INSTALLED_MARKER=\"$marker\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; write_marker"
	[ "$status" -eq 0 ]
	[ -f "$marker" ]
}

@test "install: actions runner url resolution branches" {
	# Explicit URL wins.
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export RUNNER_ACTIONS_RUNNER_TARBALL_URL=https://example.invalid/runner.tgz; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_tarball_url"
	[ "$status" -eq 0 ]
	[ "$output" = "https://example.invalid/runner.tgz" ]

	# No version + no url/token => empty.
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_tarball_url"
	[ "$status" -eq 0 ]
	[ -z "$output" ]

	# Derive default version when url+token present.
	run bash -c "set -euo pipefail; uname(){ echo x86_64; }; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export RUNNER_GITHUB_URL=https://github.com/example/repo; export RUNNER_REGISTRATION_TOKEN=token; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_tarball_url"
	[ "$status" -eq 0 ]
	[[ "$output" == "https://github.com/actions/runner/releases/download/v2.330.0/actions-runner-linux-x64-2.330.0.tar.gz" ]]
}

@test "install: actions runner arch resolution branches" {
	# Env override.
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export RUNNER_ACTIONS_RUNNER_ARCH=custom; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_arch"
	[ "$status" -eq 0 ]
	[ "$output" = "custom" ]

	# uname mappings.
	run bash -c "set -euo pipefail; uname(){ echo x86_64; }; export APPLIANCE_ROOT=\"$TEST_ROOT\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_arch"
	[ "$status" -eq 0 ]
	[ "$output" = "x64" ]

	run bash -c "set -euo pipefail; uname(){ echo aarch64; }; export APPLIANCE_ROOT=\"$TEST_ROOT\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_arch"
	[ "$status" -eq 0 ]
	[ "$output" = "arm64" ]

	run bash -c "set -euo pipefail; uname(){ echo armv7l; }; export APPLIANCE_ROOT=\"$TEST_ROOT\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_arch"
	[ "$status" -eq 0 ]
	[ "$output" = "arm" ]

	# Unsupported arch fails.
	run bash -c "set -euo pipefail; uname(){ echo mips64; }; export APPLIANCE_ROOT=\"$TEST_ROOT\"; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; resolve_actions_runner_arch"
	[ "$status" -ne 0 ]
}

@test "install: actions runner install via version (dry-run)" {
	write_config_env $'RUNNER_ACTIONS_RUNNER_VERSION=2.330.0'

	ID_APPLIANCE_EXISTS=1 \
		APPLIANCE_STUB_FLOCK_EXIT_CODE=0 \
		run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]

	# Verify the derived URL was used (host is x86_64 in CI container).
	assert_file_contains "$APPLIANCE_CALLS_FILE" "actions-runner-linux-x64-2.330.0.tar.gz"
}

@test "install: actions runner install runs dependency installer when present (dry-run)" {
	# Set explicit URL so install_actions_runner_if_configured takes the URL branch.
	mkdir -p "$TEST_ROOT/opt/runner/actions-runner/bin"
	cat >"$TEST_ROOT/opt/runner/actions-runner/bin/installdependencies.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/opt/runner/actions-runner/bin/installdependencies.sh"

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_ALLOW_NON_ROOT=1; export RUNNER_ACTIONS_RUNNER_TARBALL_URL=https://example.invalid/runner.tgz; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; install_actions_runner_if_configured"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "installdependencies.sh"
}

@test "install: actions runner configure branches" {
	# Missing config.sh should fail when url+token are present.
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export RUNNER_GITHUB_URL=https://github.com/example/repo; export RUNNER_REGISTRATION_TOKEN=token; export RUNNER_NAME=test; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; configure_actions_runner_if_configured"
	[ "$status" -ne 0 ]

	# Configure using runuser path.
	mkdir -p "$TEST_ROOT/opt/runner/actions-runner"
	cat >"$TEST_ROOT/opt/runner/actions-runner/config.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/opt/runner/actions-runner/config.sh"

	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_ALLOW_NON_ROOT=1; export RUNNER_GITHUB_URL=https://github.com/example/repo; export RUNNER_REGISTRATION_TOKEN=token; export RUNNER_NAME=test; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; configure_actions_runner_if_configured"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "runuser -u"

	# Configure using fallback (no runuser in PATH).
	# Keep dirname/mkdir available so the script can be sourced, but omit /usr/sbin
	# (where runuser commonly lives) to trigger the fallback branch.
	run bash -c "set -euo pipefail; export PATH=/usr/bin:/bin; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_ALLOW_NON_ROOT=1; export RUNNER_GITHUB_URL=https://github.com/example/repo; export RUNNER_REGISTRATION_TOKEN=token; export RUNNER_NAME=test; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; configure_actions_runner_if_configured"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "su -s"

	# Already configured should be a no-op.
	touch "$TEST_ROOT/opt/runner/actions-runner/.runner"
	run bash -c "set -euo pipefail; export APPLIANCE_ROOT=\"$TEST_ROOT\"; export APPLIANCE_DRY_RUN=1; export APPLIANCE_ALLOW_NON_ROOT=1; export RUNNER_GITHUB_URL=https://github.com/example/repo; export RUNNER_REGISTRATION_TOKEN=token; export RUNNER_NAME=test; export ID_APPLIANCE_EXISTS=1; source \"$APPLIANCE_REPO_ROOT/scripts/install.sh\"; configure_actions_runner_if_configured"
	[ "$status" -eq 0 ]
}

@test "install: starts runner service when runner already installed+configured (dry-run)" {
	write_config_env ''

	mkdir -p "$TEST_ROOT/opt/runner/actions-runner"
	cat >"$TEST_ROOT/opt/runner/actions-runner/runsvc.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$TEST_ROOT/opt/runner/actions-runner/runsvc.sh"
	touch "$TEST_ROOT/opt/runner/actions-runner/.runner"

	ID_APPLIANCE_EXISTS=1 \
		APPLIANCE_STUB_FLOCK_EXIT_CODE=0 \
		run env APPLIANCE_ALLOW_NON_ROOT=1 APPLIANCE_DRY_RUN=1 bash "$APPLIANCE_REPO_ROOT/scripts/install.sh"
	[ "$status" -eq 0 ]
	assert_file_contains "$APPLIANCE_CALLS_FILE" "systemctl enable --now runner.service"
}
