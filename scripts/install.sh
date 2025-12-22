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

  apt_pkg_available() {
    local pkg="$1"
    if ! command -v apt-cache > /dev/null 2>&1; then
      return 1
    fi
    if apt-cache show "$pkg" > /dev/null 2>&1; then
      cover_path "install:apt-pkg-available"
      return 0
    fi
    cover_path "install:apt-pkg-unavailable"
    return 1
  }

  local -a base_pkgs=(ca-certificates curl git jq)

  # If systemd-nspawn isn't present, try to install it when it's installable.
  # This avoids surprising runtime failures when workflows use job containers.
  local -a auto_pkgs=()
  if ! command -v systemd-nspawn > /dev/null 2>&1; then
    cover_path "install:missing-systemd-nspawn"
    if apt_pkg_available systemd-container; then
      cover_path "install:auto-install-systemd-container"
      auto_pkgs+=(systemd-container)
    else
      cover_path "install:auto-install-systemd-container-unavailable"
    fi
  else
    cover_path "install:has-systemd-nspawn"
  fi

  extra_pkgs=()
  if [[ -n "${APPLIANCE_APT_PACKAGES:-}" ]]; then
    # Space-separated list; intended for simple usage (e.g. "jq mosquitto-clients").
    read -r -a extra_pkgs <<< "$APPLIANCE_APT_PACKAGES"
  fi

  run_cmd apt-get install -y --no-install-recommends \
    "${base_pkgs[@]}" \
    "${auto_pkgs[@]}" \
    "${extra_pkgs[@]}"
}

install_files() {
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  local etc_dir
  local lib_dir
  local bin_dir
  local systemd_dir
  etc_dir="$(appliance_path /etc/runner)"
  lib_dir="${APPLIANCE_LIBDIR:-$(appliance_path /usr/local/lib/runner)}"
  bin_dir="${APPLIANCE_BINDIR:-$(appliance_path /usr/local/bin)}"
  systemd_dir="${APPLIANCE_SYSTEMD_DIR:-$(appliance_path /etc/systemd/system)}"

  run_cmd mkdir -p "$etc_dir"
  run_cmd mkdir -p "$lib_dir"
  run_cmd mkdir -p "$lib_dir/lib"
  run_cmd mkdir -p "$bin_dir"
  run_cmd mkdir -p "$systemd_dir"

  # Install bootstrap + core installer assets.
  run_cmd install -m 0755 "$repo_root/scripts/bootstrap.sh" "$lib_dir/bootstrap.sh"

  # Install runner management + job isolation helpers.
  run_cmd install -m 0755 "$repo_root/scripts/runner-service.sh" "$lib_dir/runner-service.sh"
  run_cmd install -m 0755 "$repo_root/scripts/container-hooks.sh" "$lib_dir/container-hooks.sh"
  run_cmd install -m 0755 "$repo_root/scripts/uninstall.sh" "$lib_dir/uninstall.sh"
  run_cmd install -m 0755 "$repo_root/scripts/ci-nspawn-run.sh" "$bin_dir/ci-nspawn-run"
  run_cmd ln -sf "$lib_dir/uninstall.sh" "$bin_dir/runner-uninstall"

  # Install shared lib helpers.
  if [[ -d "$repo_root/scripts/lib" ]]; then
    run_cmd install -m 0755 "$repo_root/scripts/lib/common.sh" "$lib_dir/lib/common.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/config.sh" "$lib_dir/lib/config.sh"
    run_cmd install -m 0755 "$repo_root/scripts/lib/logging.sh" "$lib_dir/lib/logging.sh"
    if [[ -f "$repo_root/scripts/lib/path.sh" ]]; then
      run_cmd install -m 0755 "$repo_root/scripts/lib/path.sh" "$lib_dir/lib/path.sh"
    fi
  fi

  # Only runner scripts are installed.

  # Install systemd units.
  run_cmd install -m 0644 "$repo_root/systemd/runner-install.service" "$systemd_dir/runner-install.service"
  run_cmd install -m 0644 "$repo_root/systemd/runner.service" "$systemd_dir/runner.service"
}

enable_services() {
  run_cmd systemctl daemon-reload

  run_cmd systemctl enable runner.service > /dev/null 2>&1 || true
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
  export APPLIANCE_LOG_PREFIX="runner install"

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
