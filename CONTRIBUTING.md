# Contributing

## Workflow

- Use pull requests (no direct commits to `main`).
- Keep changes minimal and aligned with the constraints in [docs/architecture.md](docs/architecture.md).
- Prefer small, reviewable commits with clear messages.

## Required: test before opening a PR

This repo treats the devcontainer as the canonical “clean room” environment.

If you haven’t used devcontainers before, don’t worry: it’s a Docker image with all the tools this repo expects
(shellcheck, shfmt, bats, kcov, markdownlint, systemd-analyze, etc.).
Running CI inside it means we all see the same results, instead of “works on my machine”.

Before opening (or updating) a PR, please run the full pipeline in the devcontainer and make sure it’s green.

Why so strict? Most of the code here is Bash + systemd glue.
Small differences in tool versions can change lint results and even test behavior.
The devcontainer keeps reviews and CI predictable.

### CI pipeline at a glance

These are the same pipeline parts used by GitHub Actions (jobs run in parallel; this diagram is the logical order
when running locally):

```mermaid
flowchart LR
  lint_sh[lint-sh] --> lint_yaml[lint-yaml]
  lint_yaml --> lint_systemd[lint-systemd]
  lint_systemd --> lint_markdown[lint-markdown]
  lint_markdown --> test_all[test-all] --> test_coverage[test-coverage]
```

### What the stages mean

The pipeline is split into stages so you can run the part you’re working on without waiting for everything.

- `lint-sh`: sanity checks for shell scripts (syntax, shellcheck, formatting).
  This catches common Bash footguns before you deploy it onto a host.
- `lint-yaml`: lints YAML files (cloud-init examples and GitHub workflow config).
- `lint-systemd`: verifies `systemd` unit files.
  This doesn’t start services; it checks the unit files are valid and consistent.
- `lint-markdown`: lints Markdown formatting so docs stay readable.
- `tests` (GitHub check: `test-all`): runs Bats tests (unit + integration) that exercise the scripts.
- `coverage` (GitHub check: `test-coverage`): runs the tests under `kcov` and enforces 100% line coverage for `scripts/`.
  That strict gate is intentional: appliance scripts tend to have lots of branches and “only happens on a bad day”
  paths, and we want those paths tested before they ship.

### Option A: VS Code devcontainer (recommended)

1. Open the repository in VS Code.
2. Run “Dev Containers: Reopen in Container”.
3. In the devcontainer terminal:

```bash
./scripts/ci.sh
```

That runs the same pipeline GitHub Actions runs for this repo.

### Option B: Docker CLI (no VS Code)

Build the devcontainer image:

```bash
docker build -t runner-devcontainer -f .devcontainer/Dockerfile .
```

Run the full pipeline inside it:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  runner-devcontainer \
  bash -lc './scripts/ci.sh'
```

### Pipeline parts (optional)

You can run individual stages by name:

```bash
./scripts/ci.sh lint-sh
./scripts/ci.sh lint-yaml
./scripts/ci.sh lint-systemd
./scripts/ci.sh lint-markdown
./scripts/ci.sh tests
./scripts/ci.sh coverage
```

### Local runs (non-devcontainer)

If you already have the toolchain installed on your machine, you can also run:

```bash
make ci
```

Local environments can drift (tool versions, missing dependencies).
If local results differ from CI, trust the devcontainer/CI result and treat local runs as “best effort”.
