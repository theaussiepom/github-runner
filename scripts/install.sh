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

runner_dir() {
	echo "${RUNNER_ACTIONS_RUNNER_DIR:-$(appliance_path /opt/runner/actions-runner)}"
}

runner_user() {
	echo "${APPLIANCE_USER:-appliance}"
}

runner_is_installed() {
	local dir
	dir="$(runner_dir)"
	[[ -x "$dir/runsvc.sh" ]]
}

runner_is_configured() {
	local dir
	dir="$(runner_dir)"
	[[ -f "$dir/.runner" || -f "$dir/.credentials" ]]
}

default_actions_runner_version() {
	# Default version used when RUNNER_ACTIONS_RUNNER_VERSION is not set.
	# Caveat: may not be the latest available runner.
	echo "2.330.0"
}

resolve_actions_runner_version() {
	if [[ -n "${RUNNER_ACTIONS_RUNNER_VERSION:-}" ]]; then
		echo "$RUNNER_ACTIONS_RUNNER_VERSION"
		return 0
	fi
	default_actions_runner_version
}

resolve_actions_runner_arch() {
	# Translate uname -m into the runner's expected arch suffix.
	if [[ -n "${RUNNER_ACTIONS_RUNNER_ARCH:-}" ]]; then
		echo "$RUNNER_ACTIONS_RUNNER_ARCH"
		return 0
	fi

	local machine
	machine="$(uname -m)"
	case "$machine" in
	x86_64)
		echo "x64"
		;;
	aarch64)
		echo "arm64"
		;;
	armv7l | armv6l)
		echo "arm"
		;;
	*)
		die "Unsupported architecture for actions runner: $machine"
		;;
	esac
}

resolve_actions_runner_tarball_url() {
	# Precedence:
	# 1) Explicit URL if provided.
	# 2) Derived URL when configuring a runner (url+token) or when version is set.
	if [[ -n "${RUNNER_ACTIONS_RUNNER_TARBALL_URL:-}" ]]; then
		echo "$RUNNER_ACTIONS_RUNNER_TARBALL_URL"
		return 0
	fi

	# Only derive a URL if the install is actually needed.
	if [[ -z "${RUNNER_ACTIONS_RUNNER_VERSION:-}" && (-z "${RUNNER_GITHUB_URL:-}" || -z "${RUNNER_REGISTRATION_TOKEN:-}") ]]; then
		echo ""
		return 0
	fi

	local version
	version="$(resolve_actions_runner_version)"
	local arch
	arch="$(resolve_actions_runner_arch)"

	echo "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-${arch}-${version}.tar.gz"
}

install_actions_runner_if_configured() {
	# Optional feature:
	# Install the official GitHub Actions runner under RUNNER_ACTIONS_RUNNER_DIR.
	# The tarball URL can be provided directly, or derived from RUNNER_ACTIONS_RUNNER_VERSION.
	local tarball_url
	tarball_url="$(resolve_actions_runner_tarball_url)"
	if [[ -z "$tarball_url" ]]; then
		cover_path "install:actions-runner-url-missing"
		return 0
	fi
	cover_path "install:actions-runner-url-present"

	local dir
	dir="$(runner_dir)"

	if runner_is_installed; then
		cover_path "install:actions-runner-already-installed"
		return 0
	fi
	cover_path "install:actions-runner-install"

	local user
	user="$(runner_user)"

	run_cmd mkdir -p "$dir"

	local tgz="$dir/actions-runner.tar.gz"
	run_cmd curl -fL -o "$tgz" "$tarball_url"
	run_cmd tar xzf "$tgz" -C "$dir"

	# Runner-provided dependency installer; must run as root.
	if [[ -x "$dir/bin/installdependencies.sh" ]]; then
		run_cmd "$dir/bin/installdependencies.sh"
	fi

	# Ensure the runner files are owned by the dedicated user.
	run_cmd chown -R "$user:$user" "$dir"
}

configure_actions_runner_if_configured() {
	# Optional feature:
	# If the user provides GitHub URL + registration token, configure the runner.
	local github_url="${RUNNER_GITHUB_URL:-}"
	local reg_token="${RUNNER_REGISTRATION_TOKEN:-}"

	if [[ -z "$github_url" || -z "$reg_token" ]]; then
		cover_path "install:actions-runner-config-vars-missing"
		return 0
	fi
	cover_path "install:actions-runner-config-vars-present"

	local dir
	dir="$(runner_dir)"
	if [[ ! -x "$dir/config.sh" ]]; then
		cover_path "install:actions-runner-config-missing-configsh"
		die "Runner not installed yet (missing $dir/config.sh). Set RUNNER_ACTIONS_RUNNER_VERSION (or RUNNER_ACTIONS_RUNNER_TARBALL_URL) and re-run install."
	fi

	if runner_is_configured; then
		cover_path "install:actions-runner-already-configured"
		return 0
	fi
	cover_path "install:actions-runner-configure"

	local user
	user="$(runner_user)"

	local name="${RUNNER_NAME:-$(hostname)}"

	local -a cmd=("$dir/config.sh" --unattended --url "$github_url" --token "$reg_token" --name "$name")
	if command -v runuser >/dev/null 2>&1; then
		run_cmd runuser -u "$user" -- "${cmd[@]}"
	else
		# Fallback for environments without runuser.
		run_cmd su -s /bin/bash -c "\"$dir/config.sh\" --unattended --url \"$github_url\" --token \"$reg_token\" --name \"$name\"" "$user"
	fi
}

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
	if id -u "$user" >/dev/null 2>&1; then
		cover_path "install:user-exists"
		return 0
	fi

	cover_path "install:user-created"

	# Create a dedicated kiosk user.
	run_cmd useradd -m -s /bin/bash "$user"

	# Typical Raspberry Pi groups for X/input/audio.
	for g in video input audio render plugdev dialout; do
		if getent group "$g" >/dev/null 2>&1; then
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
		if ! command -v apt-cache >/dev/null 2>&1; then
			return 1
		fi
		if apt-cache show "$pkg" >/dev/null 2>&1; then
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
	if ! command -v systemd-nspawn >/dev/null 2>&1; then
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
		read -r -a extra_pkgs <<<"$APPLIANCE_APT_PACKAGES"
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

	run_cmd systemctl enable runner.service >/dev/null 2>&1 || true
}

write_marker() {
	run_cmd mkdir -p "$(dirname "$MARKER_FILE")"
	if [[ "${APPLIANCE_DRY_RUN:-0}" == "1" ]]; then
		cover_path "install:write-marker-dry-run"
		record_call "write_marker $MARKER_FILE"
		return 0
	fi
	cover_path "install:write-marker-write"
	date -u +%Y-%m-%dT%H:%M:%SZ >"$MARKER_FILE"
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
	exec 9>"$LOCK_FILE"
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

	log "Installing actions runner (optional)"
	install_actions_runner_if_configured

	log "Configuring actions runner (optional)"
	configure_actions_runner_if_configured

	if [[ -z "${RUNNER_ACTIONS_RUNNER_TARBALL_URL:-}" && -z "${RUNNER_ACTIONS_RUNNER_VERSION:-}" && (-z "${RUNNER_GITHUB_URL:-}" || -z "${RUNNER_REGISTRATION_TOKEN:-}") ]]; then
		cover_path "install:optional-features-none"
	else
		cover_path "install:optional-features-actions-runner"
	fi

	log "Enabling services"
	enable_services

	# If the runner is installed/configured, start it immediately.
	if runner_is_installed && runner_is_configured; then
		cover_path "install:runner-service-start"
		run_cmd systemctl enable --now runner.service >/dev/null 2>&1 || true
	else
		cover_path "install:runner-service-not-started"
	fi

	log "Writing marker"
	write_marker

	log "Install complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
