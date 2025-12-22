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
config_env="$tmp_dir/config.env"
cat >"$config_env" <<'EOF'
APPLIANCE_LOG_PREFIX="template-appliance"
APPLIANCE_PRIMARY_CMD=""
APPLIANCE_SECONDARY_CMD=""
APPLIANCE_DRY_RUN=1
EOF

export APPLIANCE_CONFIG_ENV="$config_env"

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
  kcov_parts_dir="${KCOV_WRAP_OUT_DIR}/kcov-parts"
  rm -rf "$kcov_parts_dir" "${KCOV_WRAP_OUT_DIR}/kcov-merged"
  mkdir -p "$kcov_parts_dir"
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
    --exclude-pattern="$REPO_ROOT/tests,$REPO_ROOT/tests/vendor,$REPO_ROOT/scripts/ci.sh,$REPO_ROOT/scripts/ci"
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
    return 0
  fi

  "${kcov_cmd[@]}" >/dev/null
}

kcov_wrap_merge() {
  if [[ "$kcov_wrap_enabled" != "1" ]]; then
    return 0
  fi
  mkdir -p "${KCOV_WRAP_OUT_DIR}/kcov-merged"

  shopt -s nullglob
  parts=("${kcov_parts_dir}"/*)
  shopt -u nullglob

  if [[ "${#parts[@]}" -eq 0 ]]; then
    echo "KCOV_WRAP enabled but produced no kcov parts" >&2
    exit 1
  fi

  kcov --merge "${KCOV_WRAP_OUT_DIR}/kcov-merged" "${parts[@]}" >/dev/null
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

# config.sh: env override/default + load present/missing
export APPLIANCE_CONFIG_ENV="$tmp_dir/config.override.env"
printf '%s\n' 'APPLIANCE_LOG_PREFIX="override"' >"$APPLIANCE_CONFIG_ENV"
appliance_config_env_path >/dev/null
load_config_env

export APPLIANCE_CONFIG_ENV="$tmp_dir/config.missing.env"
rm -f "$APPLIANCE_CONFIG_ENV"
load_config_env

unset -v APPLIANCE_CONFIG_ENV
appliance_config_env_path >/dev/null

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
ln -sf "$REPO_ROOT/scripts/healthcheck.sh" "$no_lib_dir/healthcheck.sh"
ln -sf "$REPO_ROOT/scripts/mode/primary-mode.sh" "$no_lib_dir/primary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/secondary-mode.sh" "$no_lib_dir/secondary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/enter-primary-mode.sh" "$no_lib_dir/enter-primary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/enter-secondary-mode.sh" "$no_lib_dir/enter-secondary-mode.sh"

( set +e; kcov_wrap_run "bootstrap-no-lib" "$no_lib_dir/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "healthcheck-no-lib" "$no_lib_dir/healthcheck.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "primary-no-lib" "$no_lib_dir/primary-mode.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "secondary-no-lib" "$no_lib_dir/secondary-mode.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "enter-primary-no-lib" "$no_lib_dir/enter-primary-mode.sh"; exit 0 ) >/dev/null 2>&1 || true
( set +e; kcov_wrap_run "enter-secondary-no-lib" "$no_lib_dir/enter-secondary-mode.sh"; exit 0 ) >/dev/null 2>&1 || true

# bootstrap.sh: hit key branches without touching the network.
export APPLIANCE_DRY_RUN=1
export APPLIANCE_REPO_URL="https://example.invalid/repo.git"
export APPLIANCE_REPO_REF="deadbeef"
export APPLIANCE_CHECKOUT_DIR="$tmp_dir/checkout"

# installed marker early return
marker="$tmp_dir/installed.marker"
printf '%s\n' ok >"$marker"
export APPLIANCE_INSTALLED_MARKER="$marker"
kcov_wrap_run "bootstrap-installed" "$REPO_ROOT/scripts/bootstrap.sh" >/dev/null 2>&1 || true
rm -f "$marker"

# missing repo url / ref
unset -v APPLIANCE_REPO_URL
( set +e; kcov_wrap_run "bootstrap-missing-url" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
export APPLIANCE_REPO_URL="https://example.invalid/repo.git"
unset -v APPLIANCE_REPO_REF
( set +e; kcov_wrap_run "bootstrap-missing-ref" "$REPO_ROOT/scripts/bootstrap.sh"; exit 0 ) >/dev/null 2>&1 || true
export APPLIANCE_REPO_REF="deadbeef"

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

# healthcheck.sh: active/inactive + dry-run + start-secondary
export APPLIANCE_DRY_RUN=1
export SYSTEMCTL_ACTIVE_PRIMARY=0
kcov_wrap_run "healthcheck-primary-active" "$REPO_ROOT/scripts/healthcheck.sh" >/dev/null 2>&1 || true
export SYSTEMCTL_ACTIVE_PRIMARY=1
export APPLIANCE_PRIMARY_SERVICE="template-appliance-primary.service"
export APPLIANCE_SECONDARY_SERVICE="template-appliance-secondary.service"

# Force inactive by telling stub systemctl to say "inactive".
export SYSTEMCTL_ACTIVE_PRIMARY=1
kcov_wrap_run "healthcheck-dry-run" "$REPO_ROOT/scripts/healthcheck.sh" >/dev/null 2>&1 || true

export APPLIANCE_DRY_RUN=0
kcov_wrap_run "healthcheck-start-secondary" "$REPO_ROOT/scripts/healthcheck.sh" >/dev/null 2>&1 || true

# Cover healthcheck LIB_DIR fallback branch (SCRIPT_DIR/../lib).
healthcheck_fallback_root="$tmp_dir/healthcheck-fallback"
mkdir -p "$healthcheck_fallback_root/scripts"
ln -sf "$REPO_ROOT/scripts/lib" "$healthcheck_fallback_root/lib"
ln -sf "$REPO_ROOT/scripts/healthcheck.sh" "$healthcheck_fallback_root/scripts/healthcheck.sh"
kcov_wrap_run "healthcheck-libdir-fallback" "$healthcheck_fallback_root/scripts/healthcheck.sh" >/dev/null 2>&1 || true

# primary/secondary mode: dry-run, cmd-missing loop (timeout), cmd-present exec
export APPLIANCE_DRY_RUN=1
kcov_wrap_run "primary-dry-run" "$REPO_ROOT/scripts/mode/primary-mode.sh" >/dev/null 2>&1 || true
kcov_wrap_run "secondary-dry-run" "$REPO_ROOT/scripts/mode/secondary-mode.sh" >/dev/null 2>&1 || true

export APPLIANCE_DRY_RUN=0
unset -v APPLIANCE_PRIMARY_CMD

# Make the infinite sleep loop terminate quickly for coverage by stubbing sleep
# to fail once (set -e exits the script).
sleep_fail_stub_dir="$tmp_dir/stubs-sleep-fail"
mkdir -p "$sleep_fail_stub_dir"
cat >"$sleep_fail_stub_dir/sleep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$sleep_fail_stub_dir/sleep"
old_path_sleep="$PATH"
export PATH="$sleep_fail_stub_dir:$PATH"
kcov_wrap_run "primary-cmd-missing" "$REPO_ROOT/scripts/mode/primary-mode.sh" >/dev/null 2>&1 || true
unset -v APPLIANCE_SECONDARY_CMD
kcov_wrap_run "secondary-cmd-missing" "$REPO_ROOT/scripts/mode/secondary-mode.sh" >/dev/null 2>&1 || true
export PATH="$old_path_sleep"
rm -rf "$sleep_fail_stub_dir"

export APPLIANCE_PRIMARY_CMD="true"
kcov_wrap_run "primary-exec" "$REPO_ROOT/scripts/mode/primary-mode.sh" >/dev/null 2>&1 || true
export APPLIANCE_SECONDARY_CMD="true"
kcov_wrap_run "secondary-exec" "$REPO_ROOT/scripts/mode/secondary-mode.sh" >/dev/null 2>&1 || true

# Cover mode scripts LIB_DIR="$SCRIPT_DIR/lib" branch.
mode_with_lib="$tmp_dir/mode-with-lib"
mkdir -p "$mode_with_lib"
ln -sf "$REPO_ROOT/scripts/lib" "$mode_with_lib/lib"
ln -sf "$REPO_ROOT/scripts/mode/primary-mode.sh" "$mode_with_lib/primary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/secondary-mode.sh" "$mode_with_lib/secondary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/enter-primary-mode.sh" "$mode_with_lib/enter-primary-mode.sh"
ln -sf "$REPO_ROOT/scripts/mode/enter-secondary-mode.sh" "$mode_with_lib/enter-secondary-mode.sh"
export APPLIANCE_DRY_RUN=1
kcov_wrap_run "primary-libdir-direct" "$mode_with_lib/primary-mode.sh" >/dev/null 2>&1 || true
kcov_wrap_run "secondary-libdir-direct" "$mode_with_lib/secondary-mode.sh" >/dev/null 2>&1 || true
kcov_wrap_run "enter-primary-libdir-direct" "$mode_with_lib/enter-primary-mode.sh" >/dev/null 2>&1 || true
kcov_wrap_run "enter-secondary-libdir-direct" "$mode_with_lib/enter-secondary-mode.sh" >/dev/null 2>&1 || true

# enter mode scripts: ensure stop/start calls are exercised (systemctl is stubbed)
export APPLIANCE_DRY_RUN=0
kcov_wrap_run "enter-primary" "$REPO_ROOT/scripts/mode/enter-primary-mode.sh" >/dev/null 2>&1 || true
kcov_wrap_run "enter-secondary" "$REPO_ROOT/scripts/mode/enter-secondary-mode.sh" >/dev/null 2>&1 || true

# install.sh: cover key branches without side effects (DRY_RUN + stubs).
export APPLIANCE_DRY_RUN=1
export APPLIANCE_ALLOW_NON_ROOT=1
export APPLIANCE_INSTALLED_MARKER="$tmp_dir/install.marker"
export APPLIANCE_INSTALL_LOCK="$tmp_dir/install.lock"
rm -f "$APPLIANCE_INSTALLED_MARKER" "$APPLIANCE_INSTALL_LOCK"
kcov_wrap_run "install-full-dry-run" "$REPO_ROOT/scripts/install.sh" >/dev/null 2>&1 || true

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
kcov_wrap_run "install-root-ok-user-created" "$REPO_ROOT/scripts/install.sh" >/dev/null 2>&1 || true
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

kcov_wrap_merge
