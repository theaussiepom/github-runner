#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "enter-primary-mode [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

main() {
  export APPLIANCE_LOG_PREFIX="enter-primary-mode"

  cover_path "enter-primary-mode:stop-secondary"
  svc_stop template-appliance-secondary.service || true

  cover_path "enter-primary-mode:start-primary"
  svc_start template-appliance-primary.service
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
