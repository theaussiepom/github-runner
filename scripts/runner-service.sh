#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "runner-service [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

main() {
  export APPLIANCE_LOG_PREFIX="runner runner"
  load_config_env

  local runner_dir="${RUNNER_ACTIONS_RUNNER_DIR:-$(appliance_path /opt/runner/actions-runner)}"
  local hook_dir="${RUNNER_HOOKS_DIR:-$(appliance_path /usr/local/lib/runner)}"

  local runsvc_path="$runner_dir/runsvc.sh"
  if [[ ! -x "$runsvc_path" && -x "$runner_dir/bin/runsvc.sh" ]]; then
    runsvc_path="$runner_dir/bin/runsvc.sh"
    cover_path "runner-service:runsvc-bin"
  else
    cover_path "runner-service:runsvc-root"
  fi

  if [[ ! -x "$runsvc_path" ]]; then
    cover_path "runner-service:missing-runner"
    die "Runner not installed/configured: missing $runner_dir/runsvc.sh (or $runner_dir/bin/runsvc.sh)"
  fi

  # Prefer using container hooks to avoid Docker.
  # If jobs use `container:`, these hooks can route execution through nspawn.
  if [[ -x "$hook_dir/container-hooks.sh" ]]; then
    export ACTIONS_RUNNER_CONTAINER_HOOKS="$hook_dir/container-hooks.sh"
    cover_path "runner-service:container-hooks"
  else
    cover_path "runner-service:no-container-hooks"
  fi

  cover_path "runner-service:exec"
  cd "$runner_dir"
  exec "$runsvc_path"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
