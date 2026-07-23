#!/usr/bin/env bash
#
# agy-sandbox specific tests. Reuses the shared assert helpers from the
# agents-sandbox-common submodule. Pure shell — no container, no network.
#
# Covers the agy-specific wiring AND the parity contract (same dev matrix +
# shared entrypoint the other sandbox must also satisfy).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO/common/tests/asserts.sh"

# --- rendered install block: agy-specific runtime wiring ---------------------
block="$(mktemp)"; trap 'rm -f "$block"' EXIT
"$REPO/install.sh" --print > "$block"
# shellcheck disable=SC1090
source "$block"

assert_eq "$SBX_TOOL" "agy" "block sets SBX_TOOL=agy"
assert_eq "${SBX_PROJECT_LABEL:-}" "z" "agy mounts project :z (devcontainer co-mount)"
for fn in agy-sandbox agy-sandbox-sh agy-sandbox-update agy-sandbox-prompt \
          agy-sandbox-check-update _agy_prompt_im _agy_update_hook _sbx_sandbox_base; do
  if declare -F "$fn" >/dev/null; then _t_pass "fn $fn"; else _t_fail "missing fn $fn"; fi
done
assert_eq "${SBX_UPDATE_HOOK:-}" "_agy_update_hook" "agy registers its update hook"

# --- Containerfile: agy specifics + parity contract --------------------------
cf="$(cat "$REPO/Containerfile")"
assert_contains "$cf" "FROM debian:trixie-slim"              "base = debian:trixie-slim"
assert_contains "$cf" "SBX_AGENT=agy"                        "sets SBX_AGENT=agy"
assert_contains "$cf" "common/container/entrypoint.sh"       "uses shared entrypoint"
for arg in INSTALL_CARGO INSTALL_PIP INSTALL_NODE INSTALL_PNPM \
           INSTALL_JDK INSTALL_GRADLE INSTALL_GO INSTALL_POSTGRES; do
  assert_contains "$cf" "ARG $arg" "declares $arg"
done

# --- build.sh delegates to the shared lib ------------------------------------
assert_contains "$(cat "$REPO/build.sh")" "common/build-lib.sh" "build.sh sources shared build-lib"

echo
echo "== agy-sandbox: $((TESTS_RUN - TESTS_FAIL))/$TESTS_RUN passed, $TESTS_FAIL failed =="
[ "$TESTS_FAIL" -eq 0 ]
