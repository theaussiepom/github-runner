#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

MARKER_FILE="${APPLIANCE_INSTALLED_MARKER:-$(appliance_path /var/lib/template-appliance/installed)}"
LOCK_FILE="${APPLIANCE_INSTALL_LOCK:-$(appliance_path /var/lock/template-appliance-install.lock)}"

require_root() {
  if [[ "${APPLIANCE_ALLOW_NON_ROOT:-0}" == "1" ]]; then
    cover_path "install:allow-non-root"
    return 0
  fi
  local effective_uid="${APPLIANCE_EUID_OVERRIDE:-${EUID:-$(id -u)}}"
  if [[ "$effective_uid" -ne 0 ]]; then
    cover_path "install:root-required"
    die "Must run as root"
  fi
  cover_path "install:root-ok"
}

ensure_user() {
  local user="${APPLIANCE_USER:-appliance}"
  if id -u "$user" > /dev/null 2>&1; then
    cover_path "install:user-exists"
    return 0
  fi

  cover_path "install:user-created"

  # Create a dedicated kiosk user.
  run_cmd useradd -m -s /bin/bash "$user"

  # Typical Raspberry Pi groups for X/input/audio.
  for g in video input audio render plugdev dialout; do
    if getent group "$g" > /dev/null 2>&1; then
      run_cmd usermod -aG "$g" "$user"
    fi
  done
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive

  # Keep the base set minimal. Extend your appliance by adding packages as needed.
  run_cmd apt-get update

  extra_pkgs=()
  if [[ -n "${APPLIANCE_APT_PACKAGES:-}" ]]; then
    # Space-separated list; intended for simple usage (e.g. "jq mosquitto-clients").
    read -r -a extra_pkgs <<< "$APPLIANCE_APT_PACKAGES"
  fi

  run_cmd apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    "${extra_pkgs[@]}"
}

install_files() {
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  local etc_dir
  local lib_dir
  local bin_dir
  local systemd_dir
  etc_dir="$(appliance_path /etc/template-appliance)"
  lib_dir="${APPLIANCE_LIBDIR:-$(appliance_path /usr/local/lib/template-appliance)}"
  bin_dir="${APPLIANCE_BINDIR:-$(appliance_path /usr/local/bin)}"
  systemd_dir="${APPLIANCE_SYSTEMD_DIR:-$(appliance_path /etc/systemd/system)}"

  run_cmd mkdir -p "$etc_dir"
  run_cmd mkdir -p "$lib_dir"
  run_cmd mkdir -p "$lib_dir/lib"
  run_cmd mkdir -p "$bin_dir"
  run_cmd mkdir -p "$systemd_dir"

  # Install bootstrap + core installer assets.
  run_cmd install -m 0755 "$repo_root/scripts/bootstrap.sh" "$lib_dir/bootstrap.sh"

  # Install shared lib helpers.
  if [[ -d "$repo_root/scripts/lib" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/lib/common.sh" "$lib_dir/lib/common.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/config.sh" "$lib_dir/lib/config.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/logging.sh" "$lib_dir/lib/logging.sh"
    if [[ -f "$repo_root/scripts/lib/path.sh" ]]; then
      run_cmd install -m 0755 "$repo_root/scripts/lib/path.sh" "$lib_dir/lib/path.sh"
    fi
  fi

  # Install appliance scripts.
  if [[ -f "$repo_root/scripts/mode/primary-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/primary-mode.sh" "$lib_dir/primary-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/secondary-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/secondary-mode.sh" "$lib_dir/secondary-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/enter-primary-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/enter-primary-mode.sh" "$lib_dir/enter-primary-mode.sh"
  fi
  if [[ -f "$repo_root/scripts/mode/enter-secondary-mode.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/mode/enter-secondary-mode.sh" "$lib_dir/enter-secondary-mode.sh"
  fi

  if [[ -f "$repo_root/scripts/healthcheck.sh" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/healthcheck.sh" "$lib_dir/healthcheck.sh"
  fi

  # Install systemd units.
  run_cmd install -m 0644 "$repo_root/systemd/template-appliance-install.service" "$systemd_dir/template-appliance-install.service"
  run_cmd install -m 0644 "$repo_root/systemd/template-appliance-primary.service" "$systemd_dir/template-appliance-primary.service"
  run_cmd install -m 0644 "$repo_root/systemd/template-appliance-secondary.service" "$systemd_dir/template-appliance-secondary.service"
  run_cmd install -m 0644 "$repo_root/systemd/template-appliance-healthcheck.service" "$systemd_dir/template-appliance-healthcheck.service"
  run_cmd install -m 0644 "$repo_root/systemd/template-appliance-healthcheck.timer" "$systemd_dir/template-appliance-healthcheck.timer"
}

enable_services() {
  run_cmd systemctl daemon-reload

  # Default to primary mode on boot; secondary mode is started by healthcheck/failover.
  run_cmd systemctl enable template-appliance-primary.service > /dev/null 2>&1 || true
  run_cmd systemctl enable template-appliance-healthcheck.timer > /dev/null 2>&1 || true
}

write_marker() {
  run_cmd mkdir -p "$(dirname "$MARKER_FILE")"
  if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
    cover_path "install:write-marker-dry-run"
    record_call "write_marker $MARKER_FILE"
    return 0
  fi
  cover_path "install:write-marker-write"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER_FILE"
}

main() {
  require_root
  load_config_env
  export APPLIANCE_LOG_PREFIX="template-appliance install"

  if [[ -f "$MARKER_FILE" ]]; then
    cover_path "install:marker-present-early"
    log "Already installed ($MARKER_FILE present)"
    exit 0
  fi

  run_cmd mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9> "$LOCK_FILE"
  if ! flock -n 9; then
    cover_path "install:lock-busy"
    die "Another installer instance is running"
  fi
  cover_path "install:lock-acquired"

  if [[ -f "$MARKER_FILE" ]]; then
    cover_path "install:marker-after-lock"
    log "Already installed (marker appeared while waiting for lock)"
    exit 0
  fi

  log "Ensuring user ${APPLIANCE_USER:-appliance}"
  ensure_user

  log "Installing packages"
  install_packages

  log "Installing files"
  install_files

  cover_path "install:optional-features-none"

  log "Enabling services"
  enable_services

  log "Writing marker"
  write_marker

  log "Install complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
