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

# Loading agy after another sandbox must not overwrite that sandbox's state.
SBX_TOOL=codex
SBX_PROJECT_LABEL=Z
SBX_SOURCE_DIR=/tmp/codex-sandbox
SBX_UPDATE_HOOK=_codex_update_hook
# shellcheck disable=SC1090
source "$block"

assert_eq "$SBX_TOOL" "codex" "agy block preserves another sandbox's tool state"
assert_eq "$SBX_PROJECT_LABEL" "Z" "agy block preserves another sandbox's mount label"
assert_eq "$SBX_SOURCE_DIR" "/tmp/codex-sandbox" "agy block preserves another sandbox's source"
assert_eq "$SBX_UPDATE_HOOK" "_codex_update_hook" "agy block preserves another sandbox's hook"
for fn in agy-sandbox agy-sandbox-sh agy-sandbox-update agy-sandbox-prompt \
          agy-sandbox-check-update _agy_prompt_im _agy_update_hook \
          _sbx_v2_sandbox_base _sbx_v2_update _sbx_v2_prompt; do
  if declare -F "$fn" >/dev/null; then _t_pass "fn $fn"; else _t_fail "missing fn $fn"; fi
done

# Recreate the original failure condition: Codex state exists after agy. The
# agy wrappers must pass their own identity through the scoped v2 API.
SBX_TOOL=codex
SBX_SOURCE_DIR=/tmp/codex-sandbox

_sbx_v2_sandbox_base() {
  printf '%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5"
}
_sbx_v2_update() { printf '%s|%s' "$1" "$2"; }
_sbx_v2_prompt() { printf '%s|%s|%s' "$1" "$2" "$3"; }

assert_eq "$(agy-sandbox)" \
  "agy|z|_agy_update_hook||agy-sandbox" \
  "agy launcher stays scoped with Codex state"
assert_eq "$(agy-sandbox-sh)" \
  "agy|z|_agy_update_hook|/bin/bash|agy-sandbox-sh" \
  "agy shell launcher stays scoped with Codex state"
assert_eq "$(agy-sandbox-update)" \
  "agy|$REPO" \
  "agy updater rebuilds the agy source"
assert_eq "$(agy-sandbox-prompt --version)" \
  "agy|--print|--version" \
  "agy version check uses the agy image context"

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
