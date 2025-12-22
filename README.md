# runner

Bash + systemd appliance for running a single GitHub Actions self-hosted runner on Linux (including Raspberry Pi).

Goal:

- Keep exactly one host runner process managed by systemd.
- Route job execution into an ephemeral `systemd-nspawn` guest (systemd PID1 semantics)
  via GitHub Actions runner container hooks.

## Documentation

- [Architecture](docs/architecture.md)
- [Config examples](docs/config-examples.md)
- [Glossary](docs/glossary.md)

## Quick start (dev + CI)

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

At a glance, systemd manages two key units:

- `runner-install.service` (first-boot installer; retried until it succeeds)
- `runner.service` (runs the configured GitHub runner)

## Installation (cloud-init / Pi Imager)

The recommended install flow is:

1. cloud-init writes `/etc/runner/config.env`.
2. cloud-init installs a one-time installer unit + bootstrap script.
3. systemd runs `runner-install.service` until install succeeds.

Examples:

- [examples/pi-imager/user-data.example.yml](examples/pi-imager/user-data.example.yml)
- [cloud-init/user-data.example.yml](cloud-init/user-data.example.yml)

## Configuration

Runtime configuration lives in `/etc/runner/config.env`.

Required (first-boot bootstrap):

- `APPLIANCE_REPO_URL`
- `APPLIANCE_REPO_REF` (branch/tag/commit; pinning to a tag/commit is recommended)

Optional:

- `APPLIANCE_CHECKOUT_DIR` (default: `/opt/runner`)
- `APPLIANCE_INSTALLED_MARKER` (default: `/var/lib/runner/installed`)
- `APPLIANCE_APT_PACKAGES` (space-separated extra packages for install)
- `APPLIANCE_DRY_RUN=1` (do not modify system; record intended actions)

Runner:

- `RUNNER_ACTIONS_RUNNER_DIR` (default: `/opt/runner/actions-runner`)
- `RUNNER_HOOKS_DIR` (default: `/usr/local/lib/runner`)

Job isolation (`systemd-nspawn`):

- `RUNNER_NSPAWN_BASE_ROOTFS` (default: `/var/lib/runner/nspawn/base-rootfs`)
- `RUNNER_NSPAWN_READY_TIMEOUT_S` (default: `20`)
- `RUNNER_NSPAWN_BIND` / `RUNNER_NSPAWN_BIND_RO` (space-separated bind mount entries)

## Day-2 operations

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

If you cannot use cloud-init, you can install via SSH.

1. Install prerequisites:

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
