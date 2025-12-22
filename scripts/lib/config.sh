#!/usr/bin/env bash
set -euo pipefail

# Config loading helpers.

appliance_config_env_path() {
  # Location of the config.env file.
  # Tests can override with APPLIANCE_CONFIG_ENV.
  local configured="${APPLIANCE_CONFIG_ENV:-}"
  if [[ -n "$configured" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-config:env-override"
    fi
    echo "$configured"
    return 0
  fi
  if declare -F cover_path > /dev/null 2>&1; then
    cover_path "lib-config:env-default"
  fi
  appliance_path "/etc/template-appliance/config.env"
}

load_config_env() {
  local env_path
  env_path="$(appliance_config_env_path)"

  if [[ -f "$env_path" ]]; then
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-config:load-present"
    fi
    # shellcheck disable=SC1090
    source "$env_path"
  else
    if declare -F cover_path > /dev/null 2>&1; then
      cover_path "lib-config:load-missing"
    fi
  fi
}
