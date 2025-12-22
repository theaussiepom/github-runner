#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
	# Ensure network check uses stubs.
	write_config_env ''
}

teardown() {
	teardown_test_root
}

bootstrap_script() {
	echo "$APPLIANCE_REPO_ROOT/scripts/bootstrap.sh"
}

@test "bootstrap: installed marker exits early" {
	touch "$TEST_ROOT/var/lib/runner/installed"
	run env APPLIANCE_DRY_RUN=1 bash "$(bootstrap_script)"
	[ "$status" -eq 0 ]
}

@test "bootstrap: network not ready" {
	write_config_env $'APPLIANCE_REPO_URL="https://example.invalid/repo"\nAPPLIANCE_REPO_REF="main"'
	GETENT_HOSTS_EXIT_CODE=1 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 bash "$(bootstrap_script)"
	[ "$status" -ne 0 ]
}

@test "bootstrap: missing repo url" {
	write_config_env 'APPLIANCE_REPO_REF="main"'
	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 bash "$(bootstrap_script)"
	[ "$status" -ne 0 ]
}

@test "bootstrap: missing repo ref" {
	write_config_env 'APPLIANCE_REPO_URL="https://example.invalid/repo"'
	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 bash "$(bootstrap_script)"
	[ "$status" -ne 0 ]
}

@test "bootstrap: clone path and installer dry-run" {
	write_config_env $'APPLIANCE_REPO_URL="https://example.invalid/repo"\nAPPLIANCE_REPO_REF="main"'
	checkout_dir="$TEST_ROOT/opt/runner"
	mkdir -p "$checkout_dir/scripts"
	cat >"$checkout_dir/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$checkout_dir/scripts/install.sh"

	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 APPLIANCE_CHECKOUT_DIR="$checkout_dir" bash "$(bootstrap_script)"
	[ "$status" -eq 0 ]
}

@test "bootstrap: reuse checkout path and installer dry-run" {
	write_config_env $'APPLIANCE_REPO_URL="https://example.invalid/repo"\nAPPLIANCE_REPO_REF="main"'
	checkout_dir="$TEST_ROOT/opt/runner"
	mkdir -p "$checkout_dir/.git" "$checkout_dir/scripts"
	cat >"$checkout_dir/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$checkout_dir/scripts/install.sh"

	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 APPLIANCE_CHECKOUT_DIR="$checkout_dir" bash "$(bootstrap_script)"
	[ "$status" -eq 0 ]
}

@test "bootstrap: installer missing" {
	write_config_env $'APPLIANCE_REPO_URL="https://example.invalid/repo"\nAPPLIANCE_REPO_REF="main"'
	checkout_dir="$TEST_ROOT/opt/runner"
	mkdir -p "$checkout_dir/.git"

	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=1 APPLIANCE_CHECKOUT_DIR="$checkout_dir" bash "$(bootstrap_script)"
	[ "$status" -ne 0 ]
}

@test "bootstrap: installer exec" {
	write_config_env $'APPLIANCE_REPO_URL="https://example.invalid/repo"\nAPPLIANCE_REPO_REF="main"'
	checkout_dir="$TEST_ROOT/opt/runner"
	mkdir -p "$checkout_dir/.git" "$checkout_dir/scripts"
	cat >"$checkout_dir/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "installer-ran"
EOF
	chmod +x "$checkout_dir/scripts/install.sh"

	GETENT_HOSTS_EXIT_CODE=0 CURL_EXIT_CODE=0 run env APPLIANCE_DRY_RUN=0 APPLIANCE_CHECKOUT_DIR="$checkout_dir" bash "$(bootstrap_script)"
	[ "$status" -eq 0 ]
	[[ "$output" == *"installer-ran"* ]]
}
