#!/usr/bin/env bash
set -euo pipefail

# Bootstrap entrypoint invoked by systemd on first boot.
#
# Responsibilities:
# - Wait for network (systemd retries this unit on failure)
# - Fetch/clone the repo at a pinned ref
# - Run scripts/install.sh from that checkout

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "runner bootstrap [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

network_ok() {
  # DNS + HTTPS reachability (kept simple).
  getent hosts github.com > /dev/null 2>&1 && curl -fsS https://github.com > /dev/null 2>&1
}

default_bootstrap_repo_url() {
  echo "https://github.com/theaussiepom/github-runner.git"
}

default_bootstrap_repo_ref() {
  echo "main"
}

resolve_bootstrap_repo_url() {
  if [[ -n "${RUNNER_BOOTSTRAP_REPO_URL:-}" ]]; then
    cover_path "bootstrap:repo-url-runner-bootstrap"
    echo "$RUNNER_BOOTSTRAP_REPO_URL"
    return 0
  fi
  cover_path "bootstrap:repo-url-default"
  default_bootstrap_repo_url
}

resolve_bootstrap_repo_ref() {
  if [[ -n "${RUNNER_BOOTSTRAP_REPO_REF:-}" ]]; then
    cover_path "bootstrap:repo-ref-runner-bootstrap"
    echo "$RUNNER_BOOTSTRAP_REPO_REF"
    return 0
  fi
  cover_path "bootstrap:repo-ref-default"
  default_bootstrap_repo_ref
}

main() {
  export APPLIANCE_LOG_PREFIX="runner bootstrap"

  local installed_marker
  installed_marker="${APPLIANCE_INSTALLED_MARKER:-$(appliance_path /var/lib/runner/installed)}"

  if [[ -f "$installed_marker" ]]; then
    cover_path "bootstrap:installed-marker"
    log "Marker present; nothing to do."
    exit 0
  fi

  load_config_env

  require_cmd curl
  require_cmd git

  if ! network_ok; then
    cover_path "bootstrap:network-not-ready"
    die "Network not ready yet"
  fi
  cover_path "bootstrap:network-ok"

  local repo_url
  repo_url="$(resolve_bootstrap_repo_url)"
  if [[ -z "${RUNNER_BOOTSTRAP_REPO_URL:-}" ]]; then
    log "Repo URL not set; defaulting to $repo_url (set RUNNER_BOOTSTRAP_REPO_URL to override)"
  fi

  local repo_ref
  repo_ref="$(resolve_bootstrap_repo_ref)"
  if [[ -z "${RUNNER_BOOTSTRAP_REPO_REF:-}" ]]; then
    log "Repo ref not set; defaulting to $repo_ref (set RUNNER_BOOTSTRAP_REPO_REF to override; pinning is recommended)"
  fi

  local checkout_dir="${APPLIANCE_CHECKOUT_DIR:-$(appliance_path /opt/runner)}"

  if [[ ! -d "$checkout_dir/.git" ]]; then
    cover_path "bootstrap:clone"
    log "Cloning $repo_url -> $checkout_dir"
    run_cmd rm -rf "$checkout_dir"
    run_cmd git clone --no-checkout "$repo_url" "$checkout_dir"
  else
    cover_path "bootstrap:reuse-checkout"
  fi

  log "Fetching ref $repo_ref"
  run_cmd git -C "$checkout_dir" fetch --depth 1 origin "$repo_ref"
  run_cmd git -C "$checkout_dir" checkout -f FETCH_HEAD

  if [[ ! -x "$checkout_dir/scripts/install.sh" ]]; then
    cover_path "bootstrap:installer-missing"
    die "Installer not found or not executable: $checkout_dir/scripts/install.sh"
  fi

  log "Running installer"
  if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "bootstrap:installer-dry-run"
    record_call "exec $checkout_dir/scripts/install.sh"
    exit 0
  fi

  cover_path "bootstrap:installer-exec"
  exec "$checkout_dir/scripts/install.sh"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
