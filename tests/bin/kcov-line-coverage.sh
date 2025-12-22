#!/usr/bin/env bash
set -euo pipefail

# This repo uses kcov for bash line coverage.
# This script is executed by tests/bin/run-bats-kcov.sh.
#
# Important nuance:
# - kcov's bash coverage does not reliably attribute coverage across child bash
#   processes in some environments.
# - The kcov runner therefore sets KCOV_WRAP=1 and expects this script to
#   self-wrap each invoked script/command under kcov and then merge those
#   wrapped reports into $KCOV_WRAP_OUT_DIR/kcov-merged.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

: "${APPLIANCE_REPO_ROOT:=${REPO_ROOT}}"

require_cmd_quiet() {
  command -v "$1" >/dev/null 2>&1
}

tmp_dir="${REPO_ROOT}/tests/.tmp/kcov-line-coverage"
rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"

# Prefer stubs for side-effecting commands.
export PATH="${REPO_ROOT}/tests/stubs:${PATH}"

# Keep all filesystem writes under a fake root.
export APPLIANCE_ROOT="$tmp_dir/root"
mkdir -p "$APPLIANCE_ROOT"

export APPLIANCE_CALLS_FILE="$tmp_dir/calls.log"
export APPLIANCE_CALLS_FILE_APPEND="$tmp_dir/calls-append.log"
export APPLIANCE_PATHS_FILE="$tmp_dir/paths.log"
export APPLIANCE_PATH_COVERAGE=1

# Minimal config env for scripts that read config.
mkdir -p "$APPLIANCE_ROOT/etc/runner"
cat >"$APPLIANCE_ROOT/etc/runner/config.env" <<'EOF'
APPLIANCE_LOG_PREFIX="runner"
APPLIANCE_DRY_RUN=1
EOF

# Load libs in-process so we can exercise pure functions without forks.
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/logging.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/config.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/path.sh"

kcov_wrap_enabled=0
kcov_parts_dir=""

kcov_has_flag() {
  local flag="$1"
  local help
  help="$(kcov --help --uncommon-options 2>&1 || kcov --help 2>&1 || true)"
  grep -Fq -- "$flag" <<<"$help"
}

kcov_wrap_init() {
  if [[ "${KCOV_WRAP:-0}" != "1" ]]; then
    return 0
  fi
  if ! require_cmd_quiet kcov; then
    echo "KCOV_WRAP=1 but kcov not found" >&2
    exit 127
  fi
  if [[ -z "${KCOV_WRAP_OUT_DIR:-}" ]]; then
    echo "KCOV_WRAP=1 but KCOV_WRAP_OUT_DIR is not set" >&2
    exit 1
  fi

  kcov_wrap_enabled=1

  # IMPORTANT:
  # Some environments (notably networked filesystems) can be flaky with deep
  # recursive deletes and occasionally return "Directory not empty".
  # To keep CI deterministic, avoid deleting previous runs and instead allocate
  # a fresh parts directory per invocation.
  kcov_parts_dir="$(mktemp -d "${KCOV_WRAP_OUT_DIR}/kcov-parts.XXXXXX")"

  # mktemp creates 0700 by default; if the coverage was generated as root
  # (e.g. via a container), GitHub's artifact upload step can fail to scan it.
  chmod a+rX "$kcov_parts_dir" 2>/dev/null || true
}

kcov_wrap_run() {
  local label="$1"
  shift

  if [[ "$kcov_wrap_enabled" != "1" ]]; then
    "$@"
    return $?
  fi

  local out="${kcov_parts_dir}/${label}"
  rm -rf "$out"

  local -a args=()
  if kcov_has_flag '--bash-parser=cmd'; then
    args+=(--bash-parser=/bin/bash)
  fi
  if kcov_has_flag '--bash-method=method'; then
    args+=(--bash-method=DEBUG)
  fi
  if kcov_has_flag '--report-type'; then
    args+=(--report-type=html --report-type=json)
  fi
  args+=(
    --include-path="$REPO_ROOT/scripts"
    --exclude-pattern="$REPO_ROOT/tests,$REPO_ROOT/tests/vendor,$REPO_ROOT/scripts/dev,$REPO_ROOT/scripts/ci.sh,$REPO_ROOT/scripts/ci"
  )

  local arg_order="${KCOV_ARG_ORDER:-opts_first}"

  local -a kcov_cmd=(kcov)
  if [[ "$arg_order" == "out_first" ]]; then
    kcov_cmd+=("$out" "${args[@]}" "$@")
  else
    kcov_cmd+=("${args[@]}" "$out" "$@")
  fi

  local timeout_seconds="${KCOV_WRAP_TIMEOUT_SECONDS:-}"
  if [[ -n "$timeout_seconds" && -x "$(command -v timeout 2>/dev/null || true)" ]]; then
    timeout --foreground -k 1s "${timeout_seconds}s" "${kcov_cmd[@]}" >/dev/null 2>&1 || true
    chmod -R a+rX "$out" 2>/dev/null || true
    return 0
  fi

  "${kcov_cmd[@]}" >/dev/null
  chmod -R a+rX "$out" 2>/dev/null || true
}

kcov_wrap_run_stdin() {
  local label="$1"
  local stdin_file="$2"
  shift 2

  if [[ "$kcov_wrap_enabled" != "1" ]]; then
    "$@" <"$stdin_file"
    return $?
  fi

  local out="${kcov_parts_dir}/${label}"
  rm -rf "$out"

  local -a args=()
  if kcov_has_flag '--bash-parser=cmd'; then
    args+=(--bash-parser=/bin/bash)
  fi
  if kcov_has_flag '--bash-method=method'; then
    args+=(--bash-method=DEBUG)
  fi
  if kcov_has_flag '--report-type'; then
    args+=(--report-type=html --report-type=json)
  fi
  args+=(
    --include-path="$REPO_ROOT/scripts"
    --exclude-pattern="$REPO_ROOT/tests,$REPO_ROOT/tests/vendor,$REPO_ROOT/scripts/dev,$REPO_ROOT/scripts/ci.sh,$REPO_ROOT/scripts/ci"
  )

  local arg_order="${KCOV_ARG_ORDER:-opts_first}"

  local -a kcov_cmd=(kcov)
  if [[ "$arg_order" == "out_first" ]]; then
    kcov_cmd+=("$out" "${args[@]}" "$@")
  else
    kcov_cmd+=("${args[@]}" "$out" "$@")
  fi

  local timeout_seconds="${KCOV_WRAP_TIMEOUT_SECONDS:-}"
  if [[ -n "$timeout_seconds" && -x "$(command -v timeout 2>/dev/null || true)" ]]; then
    timeout --foreground -k 1s "${timeout_seconds}s" "${kcov_cmd[@]}" <"$stdin_file" >/dev/null 2>&1 || true
    chmod -R a+rX "$out" 2>/dev/null || true
    return 0
  fi

  "${kcov_cmd[@]}" <"$stdin_file" >/dev/null
  chmod -R a+rX "$out" 2>/dev/null || true
}

kcov_wrap_merge() {
  if [[ "$kcov_wrap_enabled" != "1" ]]; then
    return 0
  fi
  # Merge into a fresh directory, then atomically swap into place.
  local merged_out="${KCOV_WRAP_OUT_DIR}/kcov-merged.new"
  rm -rf "$merged_out" 2>/dev/null || true
  mkdir -p "$merged_out"

  # Ensure artifact upload can traverse the output directory.
  chmod a+rX "${KCOV_WRAP_OUT_DIR}" 2>/dev/null || true
  chmod a+rX "${kcov_parts_dir}" 2>/dev/null || true

  shopt -s nullglob
  parts=("${kcov_parts_dir}"/*)
  shopt -u nullglob

  if [[ "${#parts[@]}" -eq 0 ]]; then
    echo "KCOV_WRAP enabled but produced no kcov parts" >&2
    exit 1
  fi

  kcov --merge "$merged_out" "${parts[@]}" >/dev/null

  chmod -R a+rX "$merged_out" 2>/dev/null || true

  if [[ -e "${KCOV_WRAP_OUT_DIR}/kcov-merged" ]]; then
    mv "${KCOV_WRAP_OUT_DIR}/kcov-merged" "${KCOV_WRAP_OUT_DIR}/kcov-merged.old.$$" 2>/dev/null || true
  fi
  mv "$merged_out" "${KCOV_WRAP_OUT_DIR}/kcov-merged" 2>/dev/null || true
  chmod -R a+rX "${KCOV_WRAP_OUT_DIR}/kcov-merged" 2>/dev/null || true
}

kcov_wrap_init

# ---------- Library coverage ----------

# logging.sh: prefix default/override + log/warn/die
unset -v APPLIANCE_LOG_PREFIX
appliance_log_prefix >/dev/null
APPLIANCE_LOG_PREFIX="x" appliance_log_prefix >/dev/null
log "hello" || true
warn "hello" || true
( set +e; die "boom"; exit 0 ) >/dev/null 2>&1 || true

# common.sh: root/path/dirname/record/run/realpath
unset -v APPLIANCE_ROOT
appliance_root >/dev/null
APPLIANCE_ROOT="$tmp_dir/root/" appliance_root >/dev/null
APPLIANCE_ROOT="$tmp_dir/root" appliance_root >/dev/null

# common.sh: appliance_root invalid APPLIANCE_ROOT values (exercise both die() and no-die branches)
(
  set +e

  die() { echo "die: $*" >&2; return 1; }
  APPLIANCE_ROOT="relative" appliance_root >/dev/null 2>&1
  APPLIANCE_ROOT='/tmp/"bad' appliance_root >/dev/null 2>&1

  unset -f die
  APPLIANCE_ROOT="relative" appliance_root >/dev/null 2>&1
  APPLIANCE_ROOT='/tmp/"bad' appliance_root >/dev/null 2>&1

  exit 0
) || true

APPLIANCE_ROOT="$tmp_dir/root" appliance_path /etc/foo >/dev/null
APPLIANCE_ROOT="/" appliance_path /etc/foo >/dev/null
appliance_path relative/path >/dev/null

appliance_dirname "" >/dev/null
appliance_dirname "foo" >/dev/null
appliance_dirname "/" >/dev/null
appliance_dirname "/a/b/" >/dev/null
appliance_dirname "/a/b" >/dev/null

unset -v APPLIANCE_CALLS_FILE APPLIANCE_CALLS_FILE_APPEND
record_call "noop" || true
export APPLIANCE_CALLS_FILE="$tmp_dir/calls.log"
record_call "one" || true
export APPLIANCE_CALLS_FILE_APPEND="$tmp_dir/calls-append.log"
record_call "two" || true

APPLIANCE_DRY_RUN=1 run_cmd echo hi >/dev/null
APPLIANCE_DRY_RUN=0 run_cmd true

# common.sh: systemctl wrappers (dry-run avoids side effects)
APPLIANCE_DRY_RUN=1 svc_start runner.service >/dev/null
APPLIANCE_DRY_RUN=1 svc_stop runner.service >/dev/null

appliance_realpath_m "." >/dev/null

# appliance_is_sourced true/false branches.
is_sourced_helper="$tmp_dir/is-sourced-helper.sh"
cat >"$is_sourced_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_ROOT/scripts/lib/common.sh"
appliance_is_sourced >/dev/null 2>&1 || true
EOF
chmod +x "$is_sourced_helper"

is_sourced_wrapper="$tmp_dir/is-sourced-wrapper.sh"
cat >"$is_sourced_wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec -a bash "$is_sourced_helper"
EOF
chmod +x "$is_sourced_wrapper"

kcov_wrap_run "lib-common-is-sourced-false" "$is_sourced_helper" >/dev/null 2>&1 || true
kcov_wrap_run "lib-common-is-sourced-true" "$is_sourced_wrapper" >/dev/null 2>&1 || true

# config.sh: env default + load present/missing
export APPLIANCE_ROOT="$tmp_dir/root"
appliance_config_env_path >/dev/null
rm -f "$APPLIANCE_ROOT/etc/runner/config.env"
load_config_env

printf '%s\n' 'RUNNER_TEST_VAR="kcov"' >"$APPLIANCE_ROOT/etc/runner/config.env"
load_config_env

# path.sh: equal/base-root/child/false
appliance_path_is_under "/a" "/a" || true
appliance_path_is_under "/" "/anything" || true
appliance_path_is_under "/a" "/a/b" || true
appliance_path_is_under "/a" "/b" || true

# ---------- Script coverage ----------

# Cover scripts' "unable to locate scripts/lib" branches using symlinks.
no_lib_dir="$tmp_dir/no-lib"
mkdir -p "$no_lib_dir"
ln -sf "$REPO_ROOT/scripts/bootstrap.sh" "$no_lib_dir/bootstrap.sh"
ln -sf "$REPO_ROOT/scripts/ci-nspawn-run.sh" "$no_lib_dir/ci-nspawn-run.sh"
ln -sf "$REPO_ROOT/scripts/runner-service.sh" "$no_lib_dir/runner-service.sh"
ln -sf "$REPO_ROOT/scripts/container-hooks.sh" "$no_lib_dir/container-hooks.sh"
ln -sf "$REPO_ROOT/scripts/uninstall.sh" "$no_lib_dir/uninstall.sh"

( set +e; kcov_wrap_run "bootstrap-no-lib" "$no_lib_dir/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "ci-nspawn-run-no-lib" "$no_lib_dir/ci-nspawn-run.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "runner-service-no-lib" "$no_lib_dir/runner-service.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "container-hooks-no-lib" "$no_lib_dir/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "uninstall-no-lib" "$no_lib_dir/uninstall.sh"; exit 0 ) >/dev/null 2>&1 || true

# bootstrap.sh: hit key branches without touching the network.
export APPLIANCE_DRY_RUN=1
export APPLIANCE_CHECKOUT_DIR="$tmp_dir/checkout"

# installed marker early return
marker="$tmp_dir/installed.marker"
printf '%s\n' ok >"$marker"
export APPLIANCE_INSTALLED_MARKER="$marker"
kcov_wrap_run "bootstrap-installed" "$REPO_ROOT/scripts/bootstrap.sh" >/dev/null 2>&1 || true
rm -f "$marker"

# missing repo url / ref
unset -v RUNNER_BOOTSTRAP_REPO_URL RUNNER_BOOTSTRAP_REPO_REF

# Default repo url/ref branch (will proceed until installer is missing).
( set +e; kcov_wrap_run "bootstrap-default-repo" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true

# Preferred env var names.
export RUNNER_BOOTSTRAP_REPO_URL="https://example.invalid/repo.git"
export RUNNER_BOOTSTRAP_REPO_REF="deadbeef"
( set +e; kcov_wrap_run "bootstrap-runner-bootstrap-repo" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true

unset -v RUNNER_BOOTSTRAP_REPO_URL RUNNER_BOOTSTRAP_REPO_REF

# Force network failure via stubs by overriding curl for this one run.
old_path="$PATH"
no_net_stubs="$tmp_dir/stubs-no-network"
mkdir -p "$no_net_stubs"
cat >"$no_net_stubs/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$no_net_stubs/curl"
export PATH="$no_net_stubs:$PATH"
( set +e; kcov_wrap_run "bootstrap-network-not-ready" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
rm -rf "$no_net_stubs"
export PATH="$old_path"

# Reach installer-dry-run by pre-populating the checkout dir.
rm -rf "$APPLIANCE_CHECKOUT_DIR"
mkdir -p "$APPLIANCE_CHECKOUT_DIR/.git" "$APPLIANCE_CHECKOUT_DIR/scripts"
cat >"$APPLIANCE_CHECKOUT_DIR/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$APPLIANCE_CHECKOUT_DIR/scripts/install.sh"
kcov_wrap_run "bootstrap-dry-run" "$REPO_ROOT/scripts/bootstrap.sh" >/dev/null 2>&1 || true

# Cover LIB_DIR fallback branch (SCRIPT_DIR/../lib).
bootstrap_fallback_root="$tmp_dir/bootstrap-fallback"
mkdir -p "$bootstrap_fallback_root/scripts"
ln -sf "$REPO_ROOT/scripts/lib" "$bootstrap_fallback_root/lib"
ln -sf "$REPO_ROOT/scripts/bootstrap.sh" "$bootstrap_fallback_root/scripts/bootstrap.sh"
kcov_wrap_run "bootstrap-libdir-fallback" "$bootstrap_fallback_root/scripts/bootstrap.sh" >/dev/null 2>&1 || true

# Cover reuse-checkout + installer exec branches.
export APPLIANCE_DRY_RUN=0
kcov_wrap_run "bootstrap-installer-exec" "$REPO_ROOT/scripts/bootstrap.sh" >/dev/null 2>&1 || true
export APPLIANCE_DRY_RUN=1

# Cover clone branch + installer-missing branch.
export APPLIANCE_DRY_RUN=0
rm -rf "$APPLIANCE_CHECKOUT_DIR"
( set +e; kcov_wrap_run "bootstrap-clone-installer-missing" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
export APPLIANCE_DRY_RUN=1

# (legacy primary/secondary mode + healthcheck scripts removed)

# install.sh: cover key branches without side effects (DRY_RUN + stubs).
export APPLIANCE_DRY_RUN=1

# Ensure install.sh dependency logic is deterministic by controlling PATH.
# We cannot include /usr/bin or /bin because that would leak real systemd-nspawn,
# so build an isolated PATH with a minimal set of core tools + stubs.
make_isolated_path_dir() {
  local dir="$1"
  shift
  mkdir -p "$dir"

  local core_tools=(
    env bash sh
    cat rm mkdir rmdir mv cp ln chmod touch
    cut grep sed awk tr sort
    date mktemp head tail sleep
    uname hostname
  )

  local t src
  for t in "${core_tools[@]}"; do
    src=""
    if [[ -x "/bin/$t" ]]; then
      src="/bin/$t"
    elif [[ -x "/usr/bin/$t" ]]; then
      src="/usr/bin/$t"
    fi
    if [[ -n "$src" ]]; then
      ln -sf "$src" "$dir/$t"
    fi
  done

  local stub
  for stub in "$@"; do
    ln -sf "$REPO_ROOT/tests/stubs/$stub" "$dir/$stub"
  done
}

install_path_no_nspawn="$tmp_dir/install-path-no-nspawn"
make_isolated_path_dir "$install_path_no_nspawn" apt-cache dirname flock id getent

install_path_no_apt_cache="$tmp_dir/install-path-no-apt-cache"
make_isolated_path_dir "$install_path_no_apt_cache" dirname flock id getent

install_path_with_nspawn="$tmp_dir/install-path-with-nspawn"
make_isolated_path_dir "$install_path_with_nspawn" apt-cache dirname flock id getent systemd-nspawn

# Extra PATH variants to exercise actions-runner configure branches deterministically.
install_path_no_runuser="$tmp_dir/install-path-no-runuser"
make_isolated_path_dir "$install_path_no_runuser" apt-cache dirname flock id getent

install_path_with_runuser="$tmp_dir/install-path-with-runuser"
make_isolated_path_dir "$install_path_with_runuser" apt-cache dirname flock id getent runuser
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_INSTALLED_MARKER="$tmp_dir/install.marker"
export APPLIANCE_INSTALL_LOCK="$tmp_dir/install.lock"
rm -f "$APPLIANCE_INSTALLED_MARKER" "$APPLIANCE_INSTALL_LOCK"

install_full_dry_run_helper="$tmp_dir/install-full-dry-run-helper.sh"
cat >"$install_full_dry_run_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_no_nspawn"
export APT_CACHE_HAS_SYSTEMD_CONTAINER=1
source "$REPO_ROOT/scripts/install.sh"
main
EOF
chmod +x "$install_full_dry_run_helper"
kcov_wrap_run "install-full-dry-run" "$install_full_dry_run_helper" >/dev/null 2>&1 || true

install_no_apt_cache_helper="$tmp_dir/install-no-apt-cache-helper.sh"
cat >"$install_no_apt_cache_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_no_apt_cache"
source "$REPO_ROOT/scripts/install.sh"
main
EOF
chmod +x "$install_no_apt_cache_helper"
( set +e; kcov_wrap_run "install-no-apt-cache" "$install_no_apt_cache_helper"; exit 0 ) >/dev/null 2>&1 || true

# marker present early
printf '%s\n' ok >"$APPLIANCE_INSTALLED_MARKER"
kcov_wrap_run "install-marker-present" "$REPO_ROOT/scripts/install.sh" >/dev/null 2>&1 || true
rm -f "$APPLIANCE_INSTALLED_MARKER"

# lock busy
export APPLIANCE_STUB_FLOCK_EXIT_CODE=1
( set +e; kcov_wrap_run "install-lock-busy" "$REPO_ROOT/scripts/install.sh"; exit 0 ) >/dev/null 2>&1 || true
unset -v APPLIANCE_STUB_FLOCK_EXIT_CODE

# marker appears while waiting for lock
export APPLIANCE_STUB_FLOCK_TOUCH_MARKER=1
kcov_wrap_run "install-marker-after-lock" "$REPO_ROOT/scripts/install.sh" >/dev/null 2>&1 || true
unset -v APPLIANCE_STUB_FLOCK_TOUCH_MARKER
rm -f "$APPLIANCE_INSTALLED_MARKER"

# root-ok + user-created + apt packages parsing.
unset -v APPLIANCE_ALLOW_NON_ROOT
export APPLIANCE_EUID_OVERRIDE=0
export ID_APPLIANCE_EXISTS=0
export APPLIANCE_APT_PACKAGES="jq mosquitto-clients"

# Cover systemd-nspawn present branch.
install_root_ok_with_nspawn_helper="$tmp_dir/install-root-ok-with-nspawn-helper.sh"
cat >"$install_root_ok_with_nspawn_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_with_nspawn"
export APT_CACHE_HAS_SYSTEMD_CONTAINER=0
source "$REPO_ROOT/scripts/install.sh"
main
EOF
chmod +x "$install_root_ok_with_nspawn_helper"
kcov_wrap_run "install-root-ok-user-created" "$install_root_ok_with_nspawn_helper" >/dev/null 2>&1 || true

# Cover systemd-container unavailable branch when systemd-nspawn is missing.
install_root_ok_no_nspawn_helper="$tmp_dir/install-root-ok-no-nspawn-helper.sh"
cat >"$install_root_ok_no_nspawn_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_no_nspawn"
export APT_CACHE_HAS_SYSTEMD_CONTAINER=0
source "$REPO_ROOT/scripts/install.sh"
main
EOF
chmod +x "$install_root_ok_no_nspawn_helper"
kcov_wrap_run "install-root-ok-user-created-no-nspawn" "$install_root_ok_no_nspawn_helper" >/dev/null 2>&1 || true
unset -v APPLIANCE_EUID_OVERRIDE ID_APPLIANCE_EXISTS APPLIANCE_APT_PACKAGES

# root-required branch
export APPLIANCE_EUID_OVERRIDE=1000
( set +e; kcov_wrap_run "install-root-required" "$REPO_ROOT/scripts/install.sh"; exit 0 ) >/dev/null 2>&1 || true
unset -v APPLIANCE_EUID_OVERRIDE

# write_marker write branch (avoid running full installer)
install_write_marker_helper="$tmp_dir/install-write-marker-helper.sh"
cat >"$install_write_marker_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_ROOT/scripts/install.sh"
APPLIANCE_DRY_RUN=0
MARKER_FILE="$tmp_dir/install.write.marker"
write_marker
EOF
chmod +x "$install_write_marker_helper"
kcov_wrap_run "install-write-marker" "$install_write_marker_helper" >/dev/null 2>&1 || true

# actions-runner helper coverage (pure functions + branch selection)
install_actions_runner_helpers_helper="$tmp_dir/install-actions-runner-helpers-helper.sh"
cat >"$install_actions_runner_helpers_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_with_nspawn"
export APPLIANCE_ROOT="$tmp_dir/root-actions-runner-helpers"
mkdir -p "\$APPLIANCE_ROOT"
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_DRY_RUN=1
source "$REPO_ROOT/scripts/install.sh"

# runner_user
runner_user >/dev/null
APPLIANCE_USER="x" runner_user >/dev/null

# runner_is_configured
dir="\$(runner_dir)"
mkdir -p "\$dir"
touch "\$dir/.runner"
runner_is_configured >/dev/null || true
rm -f "\$dir/.runner"
touch "\$dir/.credentials"
runner_is_configured >/dev/null || true

# default/explicit version
unset -v RUNNER_ACTIONS_RUNNER_VERSION
resolve_actions_runner_version >/dev/null
RUNNER_ACTIONS_RUNNER_VERSION="9.9.9" resolve_actions_runner_version >/dev/null

# arch override + uname mapping
RUNNER_ACTIONS_RUNNER_ARCH="arm" resolve_actions_runner_arch >/dev/null
unset -v RUNNER_ACTIONS_RUNNER_ARCH
resolve_actions_runner_arch >/dev/null

# Cover additional uname mappings and unsupported arch.
stub_bin="\$(mktemp -d)"
cat >"\$stub_bin/uname" <<'EOS'
#!/usr/bin/env bash
echo "\${FAKE_UNAME_M:-x86_64}"
EOS
chmod +x "\$stub_bin/uname"
export PATH="\$stub_bin:$install_path_with_nspawn"
FAKE_UNAME_M=aarch64 resolve_actions_runner_arch >/dev/null
FAKE_UNAME_M=armv7l resolve_actions_runner_arch >/dev/null
( set +e; FAKE_UNAME_M=mips resolve_actions_runner_arch >/dev/null; exit 0 )

# tarball URL precedence/derivation/empty
RUNNER_ACTIONS_RUNNER_TARBALL_URL="https://example.invalid/runner.tgz" resolve_actions_runner_tarball_url >/dev/null
unset -v RUNNER_ACTIONS_RUNNER_TARBALL_URL
unset -v RUNNER_GITHUB_URL RUNNER_REGISTRATION_TOKEN
unset -v RUNNER_ACTIONS_RUNNER_VERSION
resolve_actions_runner_tarball_url >/dev/null
RUNNER_ACTIONS_RUNNER_VERSION="2.330.0" resolve_actions_runner_tarball_url >/dev/null
unset -v RUNNER_ACTIONS_RUNNER_VERSION
RUNNER_GITHUB_URL="https://github.com/example/repo" RUNNER_REGISTRATION_TOKEN="token" resolve_actions_runner_tarball_url >/dev/null

# actions-runner already-installed short circuit
dir="\$(runner_dir)"
mkdir -p "\$dir"
cat >"\$dir/runsvc.sh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "\$dir/runsvc.sh"
RUNNER_ACTIONS_RUNNER_TARBALL_URL="https://example.invalid/runner.tgz" install_actions_runner_if_configured
EOF
chmod +x "$install_actions_runner_helpers_helper"
kcov_wrap_run "install-actions-runner-helpers" "$install_actions_runner_helpers_helper" >/dev/null 2>&1 || true

# actions-runner install/configure coverage (dry-run)
install_actions_runner_flow_helper="$tmp_dir/install-actions-runner-flow-helper.sh"
cat >"$install_actions_runner_flow_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export APPLIANCE_ROOT="$tmp_dir/root-actions-runner-flow"
mkdir -p "\$APPLIANCE_ROOT"
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_DRY_RUN=1

# Force install branch via explicit URL.
export RUNNER_ACTIONS_RUNNER_TARBALL_URL="https://example.invalid/runner.tgz"
source "$REPO_ROOT/scripts/install.sh"

# Cover dependency installer branch when present.
dir="\$(runner_dir)"
mkdir -p "\$dir/bin"
cat >"\$dir/bin/installdependencies.sh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "\$dir/bin/installdependencies.sh"
install_actions_runner_if_configured

# Configure: vars missing is a no-op.
unset -v RUNNER_GITHUB_URL RUNNER_REGISTRATION_TOKEN
configure_actions_runner_if_configured

# Configure: vars present but missing config.sh -> die.
export RUNNER_GITHUB_URL="https://github.com/example/repo"
export RUNNER_REGISTRATION_TOKEN="token"
export RUNNER_NAME="test"
( set +e; configure_actions_runner_if_configured; exit 0 ) >/dev/null 2>&1 || true

# Configure: present + config.sh, cover both runuser and fallback branches.
dir="\$(runner_dir)"
mkdir -p "\$dir"
cat >"\$dir/config.sh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "\$dir/config.sh"

export PATH="$install_path_with_runuser"
configure_actions_runner_if_configured

export PATH="$install_path_no_runuser"
configure_actions_runner_if_configured
EOF
chmod +x "$install_actions_runner_flow_helper"
kcov_wrap_run "install-actions-runner-flow" "$install_actions_runner_flow_helper" >/dev/null 2>&1 || true

# install.sh: exercise optional-features-actions-runner + runner-service-start.
install_actions_runner_main_helper="$tmp_dir/install-actions-runner-main-helper.sh"
cat >"$install_actions_runner_main_helper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$install_path_with_nspawn"
export APPLIANCE_ROOT="$tmp_dir/root-actions-runner-main"
mkdir -p "\$APPLIANCE_ROOT/etc/runner"
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_DRY_RUN=1
export APPLIANCE_INSTALLED_MARKER="$tmp_dir/install.actions-runner-main.marker"
export APPLIANCE_INSTALL_LOCK="$tmp_dir/install.actions-runner-main.lock"
rm -f "\$APPLIANCE_INSTALLED_MARKER" "\$APPLIANCE_INSTALL_LOCK"

cat >"\$APPLIANCE_ROOT/etc/runner/config.env" <<'EOS'
APPLIANCE_LOG_PREFIX="runner"
APPLIANCE_DRY_RUN=1
RUNNER_GITHUB_URL="https://github.com/example/repo"
RUNNER_REGISTRATION_TOKEN="token"
RUNNER_ACTIONS_RUNNER_VERSION="2.330.0"
RUNNER_NAME="test"
EOS

# Pre-create installed+configured runner so main hits runner-service-start.
source "$REPO_ROOT/scripts/install.sh"
dir="\$(runner_dir)"
mkdir -p "\$dir"
cat >"\$dir/config.sh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "\$dir/config.sh"
cat >"\$dir/runsvc.sh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "\$dir/runsvc.sh"
touch "\$dir/.runner"

main
EOF
chmod +x "$install_actions_runner_main_helper"
kcov_wrap_run "install-actions-runner-main" "$install_actions_runner_main_helper" >/dev/null 2>&1 || true

# ---------- runner scripts ----------

# runner-service.sh: missing-runner + container-hooks/no-hooks + exec.
runner_dir="$APPLIANCE_ROOT/opt/runner/actions-runner"
hook_dir="$APPLIANCE_ROOT/usr/local/lib/runner"

( set +e; kcov_wrap_run "runner-service-missing" "$REPO_ROOT/scripts/runner-service.sh"; exit 0 ) >/dev/null 2>&1 || true

mkdir -p "$runner_dir" "$hook_dir"
cat >"$runner_dir/runsvc.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$runner_dir/runsvc.sh"

# Cover runner-service LIB_DIR fallback branch (SCRIPT_DIR/../lib).
runner_service_fallback_root="$tmp_dir/runner-service-fallback"
mkdir -p "$runner_service_fallback_root/scripts"
ln -sf "$REPO_ROOT/scripts/lib" "$runner_service_fallback_root/lib"
ln -sf "$REPO_ROOT/scripts/runner-service.sh" "$runner_service_fallback_root/scripts/runner-service.sh"
kcov_wrap_run "runner-service-libdir-fallback" "$runner_service_fallback_root/scripts/runner-service.sh" >/dev/null 2>&1 || true

kcov_wrap_run "runner-service-no-hooks" "$REPO_ROOT/scripts/runner-service.sh" >/dev/null 2>&1 || true

cat >"$hook_dir/container-hooks.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$hook_dir/container-hooks.sh"

kcov_wrap_run "runner-service-hooks" "$REPO_ROOT/scripts/runner-service.sh" >/dev/null 2>&1 || true

# container-hooks.sh: invoked -> die.
( set +e; kcov_wrap_run "container-hooks-called" "$REPO_ROOT/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

# Cover container-hooks LIB_DIR fallback branch (SCRIPT_DIR/../lib).
container_hooks_fallback_root="$tmp_dir/container-hooks-fallback"
mkdir -p "$container_hooks_fallback_root/scripts"
ln -sf "$REPO_ROOT/scripts/lib" "$container_hooks_fallback_root/lib"
ln -sf "$REPO_ROOT/scripts/container-hooks.sh" "$container_hooks_fallback_root/scripts/container-hooks.sh"
( set +e; kcov_wrap_run "container-hooks-libdir-fallback" "$container_hooks_fallback_root/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

# container-hooks.sh: exercise supported commands and common error paths.
container_hooks_work_dir="$tmp_dir/work"
container_hooks_resp_file="$tmp_dir/resp.json"

mkdir -p "$APPLIANCE_ROOT/var/lib/runner/nspawn/base-rootfs"
mkdir -p "$container_hooks_work_dir"

export GITHUB_WORKSPACE="$container_hooks_work_dir"
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_DRY_RUN=1

payload_container_hooks_prepare_container="$tmp_dir/container-hooks-prepare-container.payload.json"
cat >"$payload_container_hooks_prepare_container" <<JSON
{"command":"prepare_job","responseFile":"$container_hooks_resp_file","args":{"container":{"image":"ubuntu:22.04"}},"state":{}}
JSON
kcov_wrap_run_stdin "container-hooks-prepare-container" "$payload_container_hooks_prepare_container" "$REPO_ROOT/scripts/container-hooks.sh" >/dev/null 2>&1 || true

payload_container_hooks_prepare_none="$tmp_dir/container-hooks-prepare-none.payload.json"
cat >"$payload_container_hooks_prepare_none" <<JSON
{"command":"prepare_job","responseFile":"$container_hooks_resp_file","args":{},"state":{}}
JSON
kcov_wrap_run_stdin "container-hooks-prepare-none" "$payload_container_hooks_prepare_none" "$REPO_ROOT/scripts/container-hooks.sh" >/dev/null 2>&1 || true

payload_container_hooks_run_script="$tmp_dir/container-hooks-run-script.payload.json"
cat >"$payload_container_hooks_run_script" <<JSON
{"command":"run_script_step","responseFile":"$container_hooks_resp_file","args":{"entryPoint":"echo","entryPointArgs":["hi"],"workingDirectory":"/ci/work","environmentVariables":{"FOO":"bar"},"prependPath":[]},"state":{}}
JSON
kcov_wrap_run_stdin "container-hooks-run-script" "$payload_container_hooks_run_script" "$REPO_ROOT/scripts/container-hooks.sh" >/dev/null 2>&1 || true

payload_container_hooks_cleanup="$tmp_dir/container-hooks-cleanup.payload.json"
cat >"$payload_container_hooks_cleanup" <<JSON
{"command":"cleanup_job","responseFile":"$container_hooks_resp_file","args":{},"state":{}}
JSON
kcov_wrap_run_stdin "container-hooks-cleanup" "$payload_container_hooks_cleanup" "$REPO_ROOT/scripts/container-hooks.sh" >/dev/null 2>&1 || true

payload_container_hooks_run_container_step="$tmp_dir/container-hooks-run-container-step.payload.json"
cat >"$payload_container_hooks_run_container_step" <<JSON
{"command":"run_container_step","responseFile":"$container_hooks_resp_file","args":{},"state":{}}
JSON
( set +e; kcov_wrap_run_stdin "container-hooks-run-container-step" "$payload_container_hooks_run_container_step" "$REPO_ROOT/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

payload_container_hooks_unknown="$tmp_dir/container-hooks-unknown.payload.json"
cat >"$payload_container_hooks_unknown" <<JSON
{"command":"nope","responseFile":"$container_hooks_resp_file","args":{},"state":{}}
JSON
( set +e; kcov_wrap_run_stdin "container-hooks-unknown" "$payload_container_hooks_unknown" "$REPO_ROOT/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

payload_container_hooks_invalid="$tmp_dir/container-hooks-invalid.payload.json"
cat >"$payload_container_hooks_invalid" <<JSON
{"responseFile":"$container_hooks_resp_file","args":{},"state":{}}
JSON
( set +e; kcov_wrap_run_stdin "container-hooks-invalid" "$payload_container_hooks_invalid" "$REPO_ROOT/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

payload_container_hooks_invalid_response_file="$tmp_dir/container-hooks-invalid-response-file.payload.json"
cat >"$payload_container_hooks_invalid_response_file" <<JSON
{"command":"prepare_job","responseFile":"","args":{},"state":{}}
JSON
( set +e; kcov_wrap_run_stdin "container-hooks-invalid-response-file" "$payload_container_hooks_invalid_response_file" "$REPO_ROOT/scripts/container-hooks.sh"; exit 0 ) >/dev/null 2>&1 || true

# ci-nspawn-run.sh: missing-command, base-missing, dry-run, timeout, exec.
base_rootfs="$APPLIANCE_ROOT/var/lib/runner/nspawn/base-rootfs"
rm -rf "$base_rootfs"
( set +e; kcov_wrap_run "ci-nspawn-run-missing" "$REPO_ROOT/scripts/ci-nspawn-run.sh"; exit 0 ) >/dev/null 2>&1 || true

export APPLIANCE_DRY_RUN=1
( set +e; kcov_wrap_run "ci-nspawn-run-base-missing" "$REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi; exit 0 ) >/dev/null 2>&1 || true

mkdir -p "$base_rootfs"
export RUNNER_NSPAWN_BIND="/dev/dri:/dev/dri"
export RUNNER_NSPAWN_BIND_RO="/etc/hosts:/etc/hosts"
kcov_wrap_run "ci-nspawn-run-dry-run" "$REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi >/dev/null 2>&1 || true
unset -v RUNNER_NSPAWN_BIND RUNNER_NSPAWN_BIND_RO

export APPLIANCE_DRY_RUN=0
export RUNNER_NSPAWN_READY_TIMEOUT_S=0
export MACHINECTL_SHOW_EXIT_CODE=1
( set +e; kcov_wrap_run "ci-nspawn-run-timeout" "$REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi; exit 0 ) >/dev/null 2>&1 || true

export RUNNER_NSPAWN_READY_TIMEOUT_S=2
export MACHINECTL_SHOW_EXIT_CODE=0
kcov_wrap_run "ci-nspawn-run-exec" "$REPO_ROOT/scripts/ci-nspawn-run.sh" echo hi >/dev/null 2>&1 || true

unset -v RUNNER_NSPAWN_READY_TIMEOUT_S MACHINECTL_SHOW_EXIT_CODE
export APPLIANCE_DRY_RUN=1

# uninstall.sh: allow-non-root + root-required/root-ok.
export APPLIANCE_DRY_RUN=1
export APPLIANCE_ALLOW_NON_ROOT=1
kcov_wrap_run "uninstall-dry-run" "$REPO_ROOT/scripts/uninstall.sh" >/dev/null 2>&1 || true

unset -v APPLIANCE_ALLOW_NON_ROOT
export APPLIANCE_EUID_OVERRIDE=1000
( set +e; kcov_wrap_run "uninstall-root-required" "$REPO_ROOT/scripts/uninstall.sh"; exit 0 ) >/dev/null 2>&1 || true

export APPLIANCE_EUID_OVERRIDE=0
kcov_wrap_run "uninstall-root-ok" "$REPO_ROOT/scripts/uninstall.sh" >/dev/null 2>&1 || true
unset -v APPLIANCE_EUID_OVERRIDE

kcov_wrap_merge
