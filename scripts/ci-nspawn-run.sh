#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LIB_DIR=""
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/../lib"
else
  echo "ci-nspawn-run [error]: unable to locate scripts/lib" >&2
  exit 1
fi

# shellcheck source=scripts/lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$LIB_DIR/config.sh"

usage() {
  cat >&2 << 'EOF'
Usage:
  ci-nspawn-run <command...>

Boots an ephemeral systemd-nspawn guest (systemd PID1) and runs the provided
command inside it.

Bind mounts:
  - GitHub workspace is mounted to /ci/work.

Config:
  All configuration comes from /etc/runner/config.env.
EOF
}

machine_name() {
  local ts
  ts="$(date +%s)"
  echo "runner-job-${ts}-$$"
}

wait_for_machine() {
  local machine="$1"
  local deadline_s="${2:-20}"

  local start
  start="$(date +%s)"

  while true; do
    if machinectl show "$machine" > /dev/null 2>&1; then
      return 0
    fi

    local now
    now="$(date +%s)"
    if ((now - start >= deadline_s)); then
      return 1
    fi
    sleep 0.2
  done
}

main() {
  export APPLIANCE_LOG_PREFIX="ci-nspawn-run"
  load_config_env

  local -a env_kv=()
  local workdir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      --cwd)
        workdir="${2:-}"
        shift 2
        ;;
      --env)
        env_kv+=("${2:-}")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -lt 1 ]]; then
    cover_path "ci-nspawn-run:missing-command"
    usage
    die "Missing command"
  fi

  local workspace="${GITHUB_WORKSPACE:-$(pwd)}"

  local base_rootfs
  base_rootfs="${RUNNER_NSPAWN_BASE_ROOTFS:-$(appliance_path /var/lib/runner/nspawn/base-rootfs)}"
  if [[ ! -d "$base_rootfs" ]]; then
    cover_path "ci-nspawn-run:base-missing"
    die "Base rootfs missing: $base_rootfs"
  fi

  machine="$(machine_name)"

  local -a systemd_run_args=(
    -M "$machine"
    --wait
    --collect
    --pipe
  )
  if [[ -n "$workdir" ]]; then
    systemd_run_args+=("--working-directory=$workdir")
  fi
  if [[ ${#env_kv[@]} -gt 0 ]]; then
    local kv
    for kv in "${env_kv[@]}"; do
      systemd_run_args+=("--setenv=$kv")
    done
  fi

  local -a nspawn_args=(
    --quiet
    --boot
    --ephemeral
    --machine="$machine"
    --directory="$base_rootfs"
    --bind="$workspace:/ci/work"
    --setenv=GITHUB_WORKSPACE=/ci/work
  )

  # Optional extra bind mounts from config.
  # Format: space-separated entries:
  #   RUNNER_NSPAWN_BIND="/dev/dri:/dev/dri /dev/input:/dev/input"
  if [[ -n "${RUNNER_NSPAWN_BIND:-}" ]]; then
    cover_path "ci-nspawn-run:bind-extra"
    local entry
    for entry in ${RUNNER_NSPAWN_BIND}; do
      nspawn_args+=(--bind="$entry")
    done
  fi

  if [[ -n "${RUNNER_NSPAWN_BIND_RO:-}" ]]; then
    cover_path "ci-nspawn-run:bind-ro"
    local entry
    for entry in ${RUNNER_NSPAWN_BIND_RO}; do
      nspawn_args+=(--bind-ro="$entry")
    done
  fi

  cover_path "ci-nspawn-run:start"

  # In dry-run mode we only record what we *would* run. Do not require
  # systemd-nspawn/machinectl/systemd-run, since CI/devcontainers may not have
  # them installed.
  if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
    record_call "systemd-nspawn ${nspawn_args[*]}"
    record_call "systemd-run ${systemd_run_args[*]} -- /bin/bash -lc <cmd>"
    cover_path "ci-nspawn-run:dry-run"
    return 0
  fi

  require_cmd systemd-nspawn
  require_cmd machinectl
  require_cmd systemd-run

  nspawn_pid=""
  cleanup() {
    # Best-effort teardown.
    if [[ -n "$machine" ]]; then
      machinectl terminate "$machine" > /dev/null 2>&1 || true
    fi
    if [[ -n "$nspawn_pid" ]]; then
      kill "$nspawn_pid" > /dev/null 2>&1 || true
      wait "$nspawn_pid" > /dev/null 2>&1 || true
    fi
    cover_path "ci-nspawn-run:cleanup"
  }
  trap cleanup EXIT

  systemd-nspawn "${nspawn_args[@]}" &
  nspawn_pid="$!"

  if ! wait_for_machine "$machine" "${RUNNER_NSPAWN_READY_TIMEOUT_S:-20}"; then
    cover_path "ci-nspawn-run:machine-timeout"
    die "Machine did not come up: $machine"
  fi

  cover_path "ci-nspawn-run:exec"
  # Run the command inside the guest via systemd.
  systemd-run "${systemd_run_args[@]}" -- /bin/bash -lc "$(printf '%q ' "$@")"

  cover_path "ci-nspawn-run:poweroff"
  machinectl poweroff "$machine" > /dev/null 2>&1 || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
