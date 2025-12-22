# Glossary

Short definitions for terms used across the docs.

## Appliance concepts

- **Bootstrap**: The first-boot script that fetches/clones a pinned repo ref and runs the installer.
- **Install marker**: A file (default: `/var/lib/runner/installed`) that prevents rerunning install.
- **Repo pinning**: Installing from a specific branch/tag/commit via `APPLIANCE_REPO_URL` + `APPLIANCE_REPO_REF`.

## Linux + systemd

- **systemd**: The Linux init/service manager. Starts services at boot, restarts them on failure, and enforces ordering.
- **Unit**: A systemd configuration file that describes something systemd manages (for example: `.service`, `.timer`).
- **Service**: A unit (`.service`) describing how to run a process (ExecStart, restart policy, dependencies).
- **Timer**: A unit (`.timer`) that triggers a service on a schedule.
- **ConditionPathExists**: A directive that conditions unit start on a path existing (or not existing).
- **journald**: The system logging daemon used by systemd.
- **journalctl**: The command used to read logs from journald.

## GitHub runner

- **Container hooks**: A GitHub Actions runner integration point configured via
  `ACTIONS_RUNNER_CONTAINER_HOOKS`. The runner invokes a hook script with a JSON payload and expects a
  JSON response written to a response file.

## Isolation

- **systemd-nspawn**: A lightweight container manager that can boot a full userspace with a systemd
  PID1 inside a guest.

## Repo tooling

- **Devcontainer**: A Docker image + configuration used to provide a consistent toolchain for development and CI.
- **Bats (Bash Automated Testing System)**: The test framework used for Bash scripts.
- **kcov**: Coverage tool used here to measure Bash line coverage and enforce 100% coverage in CI.
