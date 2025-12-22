#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "primary-mode [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

main() {
  export APPLIANCE_LOG_PREFIX="primary-mode"
  load_config_env

  if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "primary-mode:dry-run"
    record_call "exec primary"
    exit 0
  fi

  if [[ -z "${APPLIANCE_PRIMARY_CMD:-}" ]]; then
    cover_path "primary-mode:cmd-missing"
    log "APPLIANCE_PRIMARY_CMD is not set; sleeping"
    while true; do sleep 3600; done
  fi

  cover_path "primary-mode:cmd-present"
  log "Starting primary command"
  exec bash -lc "$APPLIANCE_PRIMARY_CMD"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
