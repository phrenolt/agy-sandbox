#!/usr/bin/env bash
# Build the agy-sandbox image. Re-run to update to the latest agy release.
set -euo pipefail
podman build -t localhost/agy-sandbox:latest -f Containerfile .
echo ">> built: localhost/agy-sandbox:latest"
echo ">> run:   agy-sandbox"
