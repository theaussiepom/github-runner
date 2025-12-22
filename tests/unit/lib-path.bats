#!/usr/bin/env bats

# shellcheck disable=SC1091
load '../helpers/common.bash'

setup() {
	setup_test_root
	# shellcheck source=scripts/lib/common.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/common.sh"
	# shellcheck source=scripts/lib/logging.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/logging.sh"
	# shellcheck source=scripts/lib/path.sh
	source "$APPLIANCE_REPO_ROOT/scripts/lib/path.sh"
}

teardown() {
	teardown_test_root
}

@test "lib-path: is_under variants" {
	run appliance_path_is_under "/a" "/a"
	[ "$status" -eq 0 ]

	run appliance_path_is_under "/" "/anything"
	[ "$status" -eq 0 ]

	run appliance_path_is_under "/a" "/a/b"
	[ "$status" -eq 0 ]

	run appliance_path_is_under "/a" "/b"
	[ "$status" -ne 0 ]
}
