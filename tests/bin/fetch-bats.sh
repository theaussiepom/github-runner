#!/usr/bin/env bash
set -euo pipefail

# Fetch bats-core + bats-support + bats-assert into tests/vendor.
# This keeps CI and local runs consistent without requiring system packages.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIR="$ROOT_DIR/tests/vendor"

clone_or_update() {
	local repo_url="$1"
	local dest_dir="$2"
	local ref="${3:-}"

	if [[ -d "$dest_dir/.git" ]]; then
		git -C "$dest_dir" fetch --depth 1 origin "${ref:-HEAD}" >/dev/null 2>&1 || true
		return 0
	fi

	mkdir -p "$(dirname "$dest_dir")"
	git clone --depth 1 "$repo_url" "$dest_dir"
	if [[ -n "$ref" ]]; then
		git -C "$dest_dir" checkout -f "$ref"
	fi
}

main() {
	mkdir -p "$VENDOR_DIR"

	clone_or_update https://github.com/bats-core/bats-core.git "$VENDOR_DIR/bats-core"
	clone_or_update https://github.com/bats-core/bats-support.git "$VENDOR_DIR/bats-support"
	clone_or_update https://github.com/bats-core/bats-assert.git "$VENDOR_DIR/bats-assert"

	echo "Fetched bats into $VENDOR_DIR" >&2
}

main "$@"
