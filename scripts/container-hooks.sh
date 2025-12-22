#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Runner "container hooks" entrypoint.
#
# This script is used when ACTIONS_RUNNER_CONTAINER_HOOKS points to it.
# It implements the minimal subset of the container hooks protocol needed to
# run job containers without Docker.
#
# Contract intent: route container job execution through ci-nspawn-run.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "container-hooks [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

payload_file=""

cleanup_payload() {
  if [[ -n "${payload_file:-}" ]]; then
    rm -f "$payload_file" > /dev/null 2>&1 || true
  fi
}

json_get_required_str() {
  local payload_path="$1"
  local key="$2"
  jq -er --arg key "$key" '.[ $key ] | select(type == "string" and length > 0)' "$payload_path"
}

json_args_get_str() {
  local payload_path="$1"
  local key="$2"
  jq -r --arg key "$key" '((.args // {})[$key] // "") | if type == "string" then . else "" end' "$payload_path"
}

json_args_get_str_list() {
  local payload_path="$1"
  local key="$2"
  jq -r --arg key "$key" '((.args // {})[$key] // []) | if type == "array" then .[] | select(type == "string") else empty end' "$payload_path"
}

json_args_get_env_kv_lines() {
  local payload_path="$1"
  jq -r '(.args.environmentVariables // {}) | if type == "object" then to_entries[] | select(.key | type == "string" and . != "") | select(.value | type == "string") | "\(.key)\t\(.value)" else empty end' "$payload_path"
}

main() {
  export APPLIANCE_LOG_PREFIX="runner hooks"
  load_config_env

  require_cmd jq

  cover_path "container-hooks:called"

  payload_file="$(mktemp)"
  trap cleanup_payload EXIT
  cat > "$payload_file"

  local cmd
  if ! cmd="$(json_get_required_str "$payload_file" "command")"; then
    die "Invalid container hook payload (unable to read command)"
  fi

  local response_file
  if ! response_file="$(json_get_required_str "$payload_file" "responseFile")"; then
    die "Invalid container hook payload (unable to read responseFile)"
  fi

  # The runner creates the response file before running the hook, but we
  # defensively ensure the parent dir exists.
  mkdir -p "$(appliance_dirname "$response_file")"

  write_response() {
    local json="$1"
    printf '%s\n' "$json" > "$response_file"
  }

  case "$cmd" in
    prepare_job)
      cover_path "container-hooks:prepare-job"

      local has_container
      has_container="$(
        jq -r '(.args // {}) | if (type == "object" and .container != null) then "1" else "0" end' "$payload_file"
      )"

      if [[ "$has_container" == "1" ]]; then
        # Runner requires isAlpine when a job container exists.
        write_response '{"state":{},"isAlpine":false}'
      else
        write_response '{"state":{}}'
      fi
      ;;

    run_script_step)
      cover_path "container-hooks:run-script-step"

      local entry_point
      entry_point="$(json_args_get_str "$payload_file" "entryPoint")"
      [[ -n "$entry_point" ]] || die "Invalid container hook payload (missing entryPoint)"

      local working_directory
      working_directory="$(json_args_get_str "$payload_file" "workingDirectory")"

      local -a entry_args=()
      local entry_args_file
      entry_args_file="$(mktemp)"
      json_args_get_str_list "$payload_file" "entryPointArgs" > "$entry_args_file" || true
      local -a entry_arg_lines=()
      mapfile -t entry_arg_lines < "$entry_args_file" || true
      local line
      for line in "${entry_arg_lines[@]}"; do
        [[ -n "$line" ]] || continue
        entry_args+=("$line")
      done
      rm -f "$entry_args_file" > /dev/null 2>&1 || true

      local -a env_args=()
      local env_args_file
      env_args_file="$(mktemp)"
      json_args_get_env_kv_lines "$payload_file" > "$env_args_file" || true
      local -a env_kv_lines=()
      mapfile -t env_kv_lines < "$env_args_file" || true
      local kv
      for kv in "${env_kv_lines[@]}"; do
        [[ -n "$kv" ]] || continue
        local k
        local v
        k="${kv%%$'\t'*}"
        v="${kv#*$'\t'}"
        [[ -n "$k" ]] || continue
        env_args+=(--env "$k=$v")
      done
      rm -f "$env_args_file" > /dev/null 2>&1 || true

      local -a nspawn_cmd=("$SCRIPT_DIR/ci-nspawn-run.sh")
      if [[ -n "$working_directory" ]]; then
        nspawn_cmd+=(--cwd "$working_directory")
      fi
      if [[ ${#env_args[@]} -gt 0 ]]; then
        nspawn_cmd+=("${env_args[@]}")
      fi
      nspawn_cmd+=(-- "$entry_point" "${entry_args[@]}")

      "${nspawn_cmd[@]}"

      write_response '{"state":{}}'
      ;;

    cleanup_job)
      cover_path "container-hooks:cleanup-job"
      write_response '{"state":{}}'
      ;;

    run_container_step)
      cover_path "container-hooks:run-container-step"
      write_response '{"state":{}}'
      die "container hooks: run_container_step not supported"
      ;;

    *)
      cover_path "container-hooks:unknown-command"
      write_response '{"state":{}}'
      die "Unknown container hook command: $cmd"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
