# runner

This repo is a small “appliance” (a handful of Bash scripts + systemd unit files) that runs a single
GitHub Actions self-hosted runner on a Linux machine.

If you’re new to self-hosted runners: it’s GitHub’s runner program, but running on your own machine
instead of GitHub’s hosted runners.

Linux notes:

- This works on general Linux (Raspberry Pi is supported, but it’s not a requirement).
- systemd is used to start/stop things reliably at boot.

What it aims to do:

- Keep a single host runner process managed by systemd.
- When a workflow uses job containers, run the job steps inside a short-lived `systemd-nspawn` guest
  instead of using Docker.
  (If `systemd-nspawn` is new to you: it’s a lightweight container that boots a small Linux userspace
  with systemd inside it.)

## Quick start (Linux over SSH)

Works on systemd-based Linux with `apt` (for example Raspberry Pi OS / Debian / Ubuntu).

1. On GitHub, open your repo’s **Settings → Actions → Runners → New self-hosted runner** page.

1. On the host:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates curl git
```

1. Create `/etc/runner/config.env` using values from GitHub’s “New self-hosted runner” page:

```bash
sudo mkdir -p /etc/runner
sudo tee /etc/runner/config.env >/dev/null <<'EOF'
# Optional: actions runner version to install.
# Default: 2.330.0 (may not be the latest).
# The GitHub “New self-hosted runner” page shows the current version in its commands.
# RUNNER_ACTIONS_RUNNER_VERSION=2.330.0

# GitHub URL to register against.
# Get it from your repo/org’s GitHub UI: Settings → Actions → Runners → New self-hosted runner.
# Use either:
# - Repo runner: https://github.com/<owner>/<repo>
# - Org runner:  https://github.com/<org>
RUNNER_GITHUB_URL=

# Registration token from GitHub UI: Settings → Actions → Runners → New self-hosted runner.
# Note: short-lived (expires); not a PAT.
RUNNER_REGISTRATION_TOKEN=

# Optional: runner name (defaults to hostname)
# RUNNER_NAME=pi-runner
EOF
```

1. Clone this repo and run the installer:

```bash
sudo git clone https://github.com/theaussiepom/github-runner.git /opt/runner
cd /opt/runner
sudo ./scripts/install.sh
```

1. Verify it’s running:

```bash
systemctl status runner.service --no-pager
```

## Documentation

- [Architecture](docs/architecture.md)
- [Config examples](docs/config-examples.md)
- [Glossary](docs/glossary.md)

## Quick start (dev + CI)

If you want to run the repo’s checks locally, the easiest path is to use the devcontainer.
It’s a Docker image with the exact lint/test tools CI uses.

Build the devcontainer image:

```bash
docker build -t runner-devcontainer -f .devcontainer/Dockerfile .
```

Run the full CI pipeline inside it:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  runner-devcontainer \
  bash -lc './scripts/ci.sh'
```

Or, use the Makefile (requires `make` + Docker on your host):

```bash
make ci
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the required pre-PR checks.

## Runtime model

At runtime, systemd manages two services:

- `runner-install.service` (first-boot installer; retried until it succeeds)
- `runner.service` (runs the configured GitHub runner)

## Installation (cloud-init / Pi Imager)

The normal install flow is designed for “first boot” setups (cloud-init or Pi Imager):

1. cloud-init writes `/etc/runner/config.env`.
2. cloud-init installs a one-time installer unit + bootstrap script.
3. systemd runs `runner-install.service` until install succeeds.

Examples:

- [examples/pi-imager/user-data.example.yml](examples/pi-imager/user-data.example.yml)
- [cloud-init/user-data.example.yml](cloud-init/user-data.example.yml)

## Configuration

Runtime configuration lives in `/etc/runner/config.env`.

Bootstrap repo pin (used when the host needs to fetch this repo to install/update itself):

- `RUNNER_BOOTSTRAP_REPO_URL` (a `git clone` URL for this repo or your fork)
- `RUNNER_BOOTSTRAP_REPO_REF` (branch/tag/commit; pinning to a tag/commit is recommended)

If you omit these, bootstrap defaults to this repo on `main`.

Optional:

- `APPLIANCE_CHECKOUT_DIR` (default: `/opt/runner`)
- `APPLIANCE_INSTALLED_MARKER` (default: `/var/lib/runner/installed`)
- `APPLIANCE_APT_PACKAGES` (space-separated extra packages for install)
- `APPLIANCE_DRY_RUN=1` (do not modify system; record intended actions)

Runner paths:

- `RUNNER_ACTIONS_RUNNER_DIR` (default: `/opt/runner/actions-runner`)
- `RUNNER_HOOKS_DIR` (default: `/usr/local/lib/runner`)

Job isolation (`systemd-nspawn`) settings:

- `RUNNER_NSPAWN_BASE_ROOTFS` (default: `/var/lib/runner/nspawn/base-rootfs`)
- `RUNNER_NSPAWN_READY_TIMEOUT_S` (default: `20`)
- `RUNNER_NSPAWN_BIND` / `RUNNER_NSPAWN_BIND_RO` (space-separated bind mount entries)

## Day-2 operations

These are the “what’s running?” commands you’ll use most often.

Inspect service status:

```bash
systemctl status runner.service --no-pager
```

Inspect install/boot status:

```bash
systemctl status runner-install.service --no-pager
ls -l /var/lib/runner/installed || true
```

## Manual install (no cloud-init)

If you can’t use cloud-init, you can still install over SSH.

1. Install prerequisites (needed to fetch this repo):

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates curl git
```

1. Create `/etc/runner/config.env` (start from the example):

```bash
sudo mkdir -p /etc/runner
sudo cp /path/to/runner/examples/config.env.example /etc/runner/config.env
sudo nano /etc/runner/config.env
```

1. Clone the repo and run the installer as root:

```bash
git clone https://github.com/your-org/github-runner.git /opt/runner
cd /opt/runner
sudo ./scripts/install.sh
```

To have the installer perform a full end-to-end setup (download + configure the official GitHub Actions runner),
set these in `/etc/runner/config.env` before running `scripts/install.sh`:

- `RUNNER_ACTIONS_RUNNER_TARBALL_URL` (Linux ARM/ARM64 tarball URL from GitHub’s “New self-hosted runner” page)
- `RUNNER_GITHUB_URL` (repo or org URL)
- `RUNNER_REGISTRATION_TOKEN` (short-lived registration token)
- Optional: `RUNNER_NAME` (defaults to hostname)
