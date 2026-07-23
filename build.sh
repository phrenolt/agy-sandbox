#!/usr/bin/env bash
# Build the agy-sandbox image. Re-run to update to the latest agy release.
# Build logic is shared across the *-sandbox repos — see common/build-lib.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBX_TOOL=agy
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common/build-lib.sh"
sbx_build_main "$@"
