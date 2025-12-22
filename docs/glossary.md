# Glossary

Short definitions for terms used across the docs.

## Appliance concepts

- **Mode**: One of the mutually-exclusive runtime states managed by systemd.
- **Primary mode**: The main workload, run by `template-appliance-primary.service`.
- **Secondary mode**: The fallback workload, run by `template-appliance-secondary.service`.
- **Failover**: Automatically starting secondary mode if primary mode is not active.
- **Repo pinning**: Installing from a specific branch/tag/commit via `APPLIANCE_REPO_URL` + `APPLIANCE_REPO_REF`.

## Linux + systemd

- **systemd**: The Linux init/service manager. Starts services at boot, restarts them on failure, and enforces ordering.
- **Unit**: A systemd configuration file that describes something systemd manages (for example: `.service`, `.timer`).
- **Service**: A unit (`.service`) describing how to run a process (ExecStart, restart policy, dependencies).
- **Timer**: A unit (`.timer`) that triggers a service on a schedule.
- **ConditionPathExists**: A directive that conditions unit start on a path existing (or not existing).
- **journald**: The system logging daemon used by systemd.
- **journalctl**: The command used to read logs from journald.

## Repo tooling

- **Devcontainer**: A Docker image + configuration used to provide a consistent toolchain for development and CI.
- **Bats (Bash Automated Testing System)**: The test framework used for Bash scripts.
- **kcov**: Coverage tool used here to measure Bash line coverage and enforce 100% coverage in CI.
