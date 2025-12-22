#!/usr/bin/env bats

# shellcheck disable=SC1091
load '../helpers/common.bash'

setup() {
	setup_test_root
	# Do not source any libs here; this runs last as a pure assertion.
}

teardown() {
	teardown_test_root
}

@test "unit suite covers all required lib-* path IDs" {
	required_file="$APPLIANCE_REPO_ROOT/tests/coverage/required-paths.txt"
	paths_log="$APPLIANCE_PATHS_FILE"

	[ -f "$required_file" ]
	[ -f "$paths_log" ]

	missing=()
	while IFS= read -r id; do
		[[ -n "$id" ]] || continue
		[[ "$id" == \#* ]] && continue
		[[ "$id" == lib-* ]] || continue
		if ! grep -Fqx -- "PATH $id" "$paths_log"; then
			missing+=("$id")
		fi
	done <"$required_file"

	if [[ "${#missing[@]}" -gt 0 ]]; then
		printf 'Missing lib path IDs:\n' >&2
		printf '%s\n' "${missing[@]}" >&2
		return 1
	fi
}
