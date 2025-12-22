#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "enter-secondary-mode [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

main() {
  export APPLIANCE_LOG_PREFIX="enter-secondary-mode"

  cover_path "enter-secondary-mode:stop-primary"
  svc_stop template-appliance-primary.service || true

  cover_path "enter-secondary-mode:start-secondary"
  svc_start template-appliance-secondary.service
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
