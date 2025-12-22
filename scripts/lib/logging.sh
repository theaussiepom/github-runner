#!/usr/bin/env bash
set -euo pipefail

# Logging helpers.

logging__cover_path_raw() {
  [[ "${APPLIANCE_PATH_COVERAGE:-0}" == "1" ]] || return 0

  local path_id="${1:-}"
  [[ -n "$path_id" ]] || return 0

  local path_file="${APPLIANCE_PATHS_FILE:-${APPLIANCE_CALLS_FILE_APPEND:-${APPLIANCE_CALLS_FILE:-}}}"
  [[ -n "$path_file" ]] || return 0

  local dir
  dir="${path_file%/*}"
  if [[ -n "$dir" && "$dir" != "$path_file" ]]; then
    mkdir -p "$dir" 2> /dev/null || true
  fi
  printf 'PATH %s\n' "$path_id" >> "$path_file" 2> /dev/null || true
}

appliance_log_prefix() {
  # Allow callers to override the prefix for nicer logs.
  if [[ -n "${APPLIANCE_LOG_PREFIX:-}" ]]; then
    logging__cover_path_raw "lib-logging:prefix-override"
  else
    logging__cover_path_raw "lib-logging:prefix-default"
  fi
  echo "${APPLIANCE_LOG_PREFIX:-template-appliance}"
}

log() {
  logging__cover_path_raw "lib-logging:log"
  echo "$(appliance_log_prefix): $*" >&2
}

warn() {
  logging__cover_path_raw "lib-logging:warn"
  echo "$(appliance_log_prefix) [warn]: $*" >&2
}

die() {
  logging__cover_path_raw "lib-logging:die"
  echo "$(appliance_log_prefix) [error]: $*" >&2
  exit 1
}
