#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
	setup_test_root
}

teardown() {
	teardown_test_root
}

@test "integration suite covers all required non-lib path IDs" {
	required_file="$APPLIANCE_REPO_ROOT/tests/coverage/required-paths.txt"
	paths_log="$APPLIANCE_PATHS_FILE"

	[ -f "$required_file" ]
	[ -f "$paths_log" ]

	missing=()
	while IFS= read -r id; do
		[[ -n "$id" ]] || continue
		[[ "$id" == \#* ]] && continue
		[[ "$id" == lib-* ]] && continue
		if ! grep -Fqx -- "PATH $id" "$paths_log"; then
			missing+=("$id")
		fi
	done <"$required_file"

	if [[ "${#missing[@]}" -gt 0 ]]; then
		printf 'Missing integration path IDs:\n' >&2
		printf '%s\n' "${missing[@]}" >&2
		return 1
	fi
}
