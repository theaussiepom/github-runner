# Configuration examples

runner is configured via `/etc/runner/config.env`.

Notes:

- `RUNNER_BOOTSTRAP_REPO_URL` + `RUNNER_BOOTSTRAP_REPO_REF` tell the host where to `git clone` this installer from.
  Use your fork URL if you maintain one.
  If you omit them, bootstrap defaults to this repo on `main`.
- A line like `FOO=` means “set but empty”.

If you’re not sure what to put in here:

- Start with the “Minimal” example.
- Then only add the options you actually need.

---

## 1) Minimal: pin the repo

```bash
# Preferred: bootstrap pin
RUNNER_BOOTSTRAP_REPO_URL=https://github.com/your-org/github-runner.git
RUNNER_BOOTSTRAP_REPO_REF=main
```

What this does:

- On first boot, runner’s bootstrap script clones `RUNNER_BOOTSTRAP_REPO_URL` at `RUNNER_BOOTSTRAP_REPO_REF` and
  runs the installer from that checkout.
- Pinning to a tag or commit is the easiest way to make installs repeatable.

---

## 1b) Minimal end-to-end (SSH installs): install + configure the runner

```bash
# Optional: actions runner version to install.
# Default: 2.330.0 (may not be the latest).
# The GitHub “New self-hosted runner” page shows the current version in its commands.
# RUNNER_ACTIONS_RUNNER_VERSION=2.330.0

# GitHub URL to register against.
# Registration token from GitHub UI: Settings → Actions → Runners → New self-hosted runner.
# Use either:
# - Repo runner: https://github.com/<owner>/<repo>
# - Org runner:  https://github.com/<org>
RUNNER_GITHUB_URL=

# Registration token from GitHub UI: Settings → Actions → Runners → New self-hosted runner.
# Note: short-lived (expires); not a PAT.
RUNNER_REGISTRATION_TOKEN=

# Optional: runner display name (defaults to hostname)
# RUNNER_NAME=pi-runner
```

---

## 2) Deterministic installs: pin to a tag or commit SHA

```bash
RUNNER_BOOTSTRAP_REPO_URL=https://github.com/your-org/github-runner.git
RUNNER_BOOTSTRAP_REPO_REF=v0.1.0
```

---

## 3) Customize checkout, install packages, and nspawn settings

```bash
RUNNER_BOOTSTRAP_REPO_URL=https://github.com/your-org/github-runner.git
RUNNER_BOOTSTRAP_REPO_REF=main

# Where bootstrap clones the repo
APPLIANCE_CHECKOUT_DIR=/opt/runner

# Space-separated list of extra packages to install
APPLIANCE_APT_PACKAGES="ca-certificates curl git"

# Runner installation location
RUNNER_ACTIONS_RUNNER_DIR=/opt/runner/actions-runner

# systemd-nspawn base rootfs to use for ephemeral guests
RUNNER_NSPAWN_BASE_ROOTFS=/var/lib/runner/nspawn/base-rootfs

# Optional bind mounts into the guest (space-separated)
RUNNER_NSPAWN_BIND="/dev/dri:/dev/dri"
RUNNER_NSPAWN_BIND_RO="/etc/resolv.conf:/etc/resolv.conf"
```

Tips:

- `APPLIANCE_APT_PACKAGES` is for anything you want available on the host (for example `jq`).
- The `RUNNER_NSPAWN_BIND*` settings are useful when your jobs need access to a specific device or host file.
