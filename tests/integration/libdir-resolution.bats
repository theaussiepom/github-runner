#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}

make_layout_with_parent_lib() {
	local src_script="$1"
	local name
	name="$(basename "$src_script")"

	local base="$TEST_ROOT/layout-${name%.*}"
	mkdir -p "$base/bin" "$base/lib"

	cp "$src_script" "$base/bin/$name"
	chmod +x "$base/bin/$name"

	# Provide libs at ../lib (not at ./lib) to exercise the LIB_DIR fallback.
	cp "$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh" "$base/lib/logging.sh"
	cp "$APPLIANCE_REPO_ROOT/scripts/lib/common.sh" "$base/lib/common.sh"
	cp "$APPLIANCE_REPO_ROOT/scripts/lib/config.sh" "$base/lib/config.sh"

	echo "$base/bin/$name"
}

@test "scripts: resolve libs from ../lib (fallback branch)" {
	# Note: each script has its own LIB_DIR resolution logic; we must exercise
	# the fallback for each file to satisfy line coverage.
	local scripts=(
		"$APPLIANCE_REPO_ROOT/scripts/bootstrap.sh"
		"$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh"
		"$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"
		"$APPLIANCE_REPO_ROOT/scripts/runner-service.sh"
	)

	# Make bootstrap exit quickly.
	local marker="$TEST_ROOT/marker.bootstrap"
	touch "$marker"

	for s in "${scripts[@]}"; do
		layout_script="$(make_layout_with_parent_lib "$s")"
		case "$(basename "$s")" in
			bootstrap.sh)
				run env APPLIANCE_ROOT="$TEST_ROOT" APPLIANCE_INSTALLED_MARKER="$marker" APPLIANCE_DRY_RUN=1 bash "$layout_script"
				[ "$status" -eq 0 ]
				;;
			ci-nspawn-run.sh)
				run env APPLIANCE_ROOT="$TEST_ROOT" APPLIANCE_DRY_RUN=1 bash "$layout_script" --help
				[ "$status" -eq 0 ]
				;;
			container-hooks.sh)
				run env APPLIANCE_ROOT="$TEST_ROOT" APPLIANCE_DRY_RUN=1 bash "$layout_script" </dev/null
				[ "$status" -ne 0 ]
				[[ "$output" != *"unable to locate scripts/lib"* ]]
				;;
			runner-service.sh)
				run env APPLIANCE_ROOT="$TEST_ROOT" APPLIANCE_DRY_RUN=1 bash "$layout_script"
				[ "$status" -ne 0 ]
				[[ "$output" != *"unable to locate scripts/lib"* ]]
				;;
			*)
				false
				;;
		esac
	done
}

@test "scripts: fail cleanly when libs cannot be located" {
	local scripts=(
		"$APPLIANCE_REPO_ROOT/scripts/bootstrap.sh"
		"$APPLIANCE_REPO_ROOT/scripts/ci-nspawn-run.sh"
		"$APPLIANCE_REPO_ROOT/scripts/container-hooks.sh"
		"$APPLIANCE_REPO_ROOT/scripts/runner-service.sh"
	)

	for s in "${scripts[@]}"; do
		name="$(basename "$s")"
		base="$TEST_ROOT/nolib-${name%.*}"
		mkdir -p "$base/bin"
		cp "$s" "$base/bin/$name"
		chmod +x "$base/bin/$name"

		run env APPLIANCE_ROOT="$TEST_ROOT" bash "$base/bin/$name" 2>&1
		[ "$status" -ne 0 ]
		[[ "$output" == *"unable to locate scripts/lib"* ]]
	done
}
