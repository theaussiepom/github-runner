#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if command -v shfmt > /dev/null 2>&1; then
  exec shfmt "$@"
fi

if ! command -v docker > /dev/null 2>&1; then
  echo "shfmt: command not found" >&2
  echo "Either install shfmt locally, or use the devcontainer (Docker) toolchain." >&2
  exit 127
fi

image="${SHFMT_DOCKER_IMAGE:-runner-devcontainer:local}"

if ! docker image inspect "$image" > /dev/null 2>&1; then
  echo "Building devcontainer image ($image) to provide shfmt..." >&2
  docker build -t "$image" -f "$repo_root/.devcontainer/Dockerfile" "$repo_root" >&2
fi

translated_args=()
for arg in "$@"; do
  if [[ "$arg" == "$repo_root" ]]; then
    translated_args+=("/work")
  elif [[ "$arg" == "$repo_root"/* ]]; then
    translated_args+=("/work/${arg#"$repo_root"/}")
  else
    translated_args+=("$arg")
  fi
done

exec docker run --rm -i \
  -v "$repo_root:/work" \
  -w /work \
  "$image" \
  shfmt "${translated_args[@]}"
