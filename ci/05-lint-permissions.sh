#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ci/lib.sh
source "$repo_root/ci/lib.sh"
ci_cd_repo_root

echo "== lint-permissions: executable bits =="

# We rely on git to carry executable bits across environments (especially CI).
# If these drift, GitHub Actions checkouts may lose +x and coverage wrapping breaks.

fail=0

check_git_mode() {
  local prefix="$1"
  local pattern_re="$2"
  local expected_mode="$3"

  # Check the *git index* mode, not the filesystem mode. In some dev/test
  # environments the worktree may be mounted 0777 which would mask missing +x.
  #
  # git ls-files --stage emits: <mode> <object> <stage> <path>
  while IFS=$'\t' read -r meta path; do
    [[ -n "$path" ]] || continue

    local mode
    mode="${meta%% *}"

    if [[ "$path" =~ $pattern_re ]]; then
      if [[ "$mode" != "$expected_mode" ]]; then
        echo "lint-permissions [error]: wrong git mode (expected $expected_mode): $path (got $mode)" >&2
        fail=1
      fi
    fi
  done < <(git ls-files --stage "$prefix")
}

check_git_mode "ci" '^ci/.*\.sh$' 100755
check_git_mode "scripts" '^scripts/.*\.sh$' 100755
check_git_mode "tests/bin" '^tests/bin/.*\.sh$' 100755

# Test stubs are invoked via PATH and must be executable, but they intentionally
# do not all end with .sh.
check_git_mode "tests/stubs" '^tests/stubs/.*' 100755

if [[ "$fail" -ne 0 ]]; then
  echo "lint-permissions [hint]: fix with: git update-index --chmod=+x <file>" >&2
  exit 1
fi
