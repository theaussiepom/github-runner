# Configuration examples

template-appliance is configured via `/etc/template-appliance/config.env`.

Notes:

- `APPLIANCE_REPO_URL` + `APPLIANCE_REPO_REF` are required for first-boot installs (bootstrap clones the repo).
- `APPLIANCE_PRIMARY_CMD` and `APPLIANCE_SECONDARY_CMD` are required for runtime.
- A line like `FOO=` means “set but empty”.

---

## 1) Minimal: pin the repo + set mode commands

```bash
# Required: bootstrap pin
APPLIANCE_REPO_URL=https://github.com/your-org/template-appliance.git
APPLIANCE_REPO_REF=main

# Required: runtime commands
APPLIANCE_PRIMARY_CMD='echo "primary"; sleep infinity'
APPLIANCE_SECONDARY_CMD='echo "secondary"; sleep infinity'
```

---

## 2) Deterministic installs: pin to a tag or commit SHA

```bash
APPLIANCE_REPO_URL=https://github.com/your-org/template-appliance.git
APPLIANCE_REPO_REF=v0.1.0

APPLIANCE_PRIMARY_CMD='your-primary-binary --flag'
APPLIANCE_SECONDARY_CMD='your-secondary-binary --safe-mode'
```

---

## 3) Customize checkout and install packages

```bash
APPLIANCE_REPO_URL=https://github.com/your-org/template-appliance.git
APPLIANCE_REPO_REF=main

# Where bootstrap clones the repo
APPLIANCE_CHECKOUT_DIR=/opt/template-appliance

# Space-separated list of extra packages to install
APPLIANCE_APT_PACKAGES="jq ca-certificates"

APPLIANCE_PRIMARY_CMD='jq --version && sleep infinity'
APPLIANCE_SECONDARY_CMD='echo fallback && sleep infinity'
```
