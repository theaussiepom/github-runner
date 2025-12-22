#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "healthcheck [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

is_active() { systemctl is-active --quiet "$1"; }

main() {
  export APPLIANCE_LOG_PREFIX="healthcheck"
  load_config_env

  local primary_service="${APPLIANCE_PRIMARY_SERVICE:-template-appliance-primary.service}"
  local secondary_service="${APPLIANCE_SECONDARY_SERVICE:-template-appliance-secondary.service}"

  if is_active "$primary_service"; then
    cover_path "healthcheck:primary-active"
    log "$primary_service active"
    exit 0
  fi
  cover_path "healthcheck:primary-inactive"

  log "$primary_service inactive; starting $secondary_service"
  if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "healthcheck:dry-run"
    record_call "systemctl start $secondary_service"
    exit 0
  fi

  cover_path "healthcheck:start-secondary"
  run_cmd systemctl start "$secondary_service" || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
