#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

MARKER_FILE="${APPLIANCE_INSTALLED_MARKER:-$(appliance_path /var/lib/runner/installed)}"
LOCK_FILE="${APPLIANCE_INSTALL_LOCK:-$(appliance_path /var/lock/runner-install.lock)}"

require_root() {
  if [[ "${APPLIANCE_ALLOW_NON_ROOT:-0}" == "1" ]]; then
    cover_path "uninstall:allow-non-root"
    return 0
  fi
  local effective_uid="${APPLIANCE_EUID_OVERRIDE:-${EUID:-$(id -u)}}"
  if [[ "$effective_uid" -ne 0 ]]; then
    cover_path "uninstall:root-required"
    die "Must run as root"
  fi
  cover_path "uninstall:root-ok"
}

main() {
  require_root
  load_config_env
  export APPLIANCE_LOG_PREFIX="runner uninstall"

  local lib_dir="${APPLIANCE_LIBDIR:-$(appliance_path /usr/local/lib/runner)}"
  local bin_dir="${APPLIANCE_BINDIR:-$(appliance_path /usr/local/bin)}"
  local systemd_dir="${APPLIANCE_SYSTEMD_DIR:-$(appliance_path /etc/systemd/system)}"

  cover_path "uninstall:stop-services"
  run_cmd systemctl disable --now runner.service > /dev/null 2>&1 || true
  run_cmd systemctl disable --now runner-install.service > /dev/null 2>&1 || true
  run_cmd systemctl daemon-reload > /dev/null 2>&1 || true

  cover_path "uninstall:remove-units"
  run_cmd rm -f "$systemd_dir/runner.service" "$systemd_dir/runner-install.service" || true

  cover_path "uninstall:remove-bins"
  run_cmd rm -f "$bin_dir/ci-nspawn-run" "$bin_dir/runner-uninstall" || true

  cover_path "uninstall:remove-lib"
  run_cmd rm -rf "$lib_dir" || true

  cover_path "uninstall:remove-state"
  run_cmd rm -rf "$(appliance_path /var/lib/runner)" || true
  run_cmd rm -f "$LOCK_FILE" || true
  run_cmd rm -f "$MARKER_FILE" || true

  cover_path "uninstall:remove-config"
  run_cmd rm -rf "$(appliance_path /etc/runner)" || true

  cover_path "uninstall:done"
  log "Uninstall complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
