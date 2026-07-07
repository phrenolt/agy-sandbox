#!/usr/bin/env bash
# Build the agy-sandbox image. Re-run to update to the latest agy release.
set -euo pipefail

if command -v podman &>/dev/null; then
  engine=podman
elif command -v docker &>/dev/null; then
  engine=docker
else
  echo "Error: neither podman nor docker found." >&2; exit 1
fi
echo ">> using: $engine"

$engine build -t localhost/agy-sandbox:latest -f Containerfile .
echo ">> built: localhost/agy-sandbox:latest"
echo ">> run:   agy-sandbox"
