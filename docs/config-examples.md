# Configuration examples

runner is configured via `/etc/runner/config.env`.

Notes:

- `APPLIANCE_REPO_URL` + `APPLIANCE_REPO_REF` are required for first-boot installs (bootstrap clones the repo).
- A line like `FOO=` means “set but empty”.

---

## 1) Minimal: pin the repo

```bash
# Required: bootstrap pin
APPLIANCE_REPO_URL=https://github.com/your-org/github-runner.git
APPLIANCE_REPO_REF=main
```

---

## 2) Deterministic installs: pin to a tag or commit SHA

```bash
APPLIANCE_REPO_URL=https://github.com/your-org/github-runner.git
APPLIANCE_REPO_REF=v0.1.0
```

---

## 3) Customize checkout, install packages, and nspawn settings

```bash
APPLIANCE_REPO_URL=https://github.com/your-org/github-runner.git
APPLIANCE_REPO_REF=main

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
