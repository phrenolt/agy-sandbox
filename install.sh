#!/usr/bin/env bash
#
# install.sh — install the agy-sandbox shell function
#
# Adds agy-sandbox to ~/.bashrc (or ~/.zshrc), idempotent.
# Re-running replaces the existing block rather than duplicating it.
#
# Usage:
#   ./install.sh            # auto-detects ~/.bashrc or ~/.zshrc
#   ./install.sh --print    # print the block without installing
#   ./install.sh --uninstall
#
# Shared install/build/launcher logic lives in common/ (the sandbox-common
# submodule); only the agy-specific block below is repo-local.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBX_TOOL=agy
SBX_SCRIPT_DIR="$SCRIPT_DIR"
SBX_BUILD_ARGS="--auto"
SBX_RUN_HINT="agy-sandbox (or agy-sandbox-sh to enter the container)"

read -r -d '' SBX_BLOCK <<'BLOCK_EOF' || true
# >>> agy-sandbox >>>
# Managed by install.sh — edit the script / common lib, not this block (re-run to update).
source "__SBX_COMMON_DIR__/lib.sh"
SBX_TOOL=agy
# Project dir mounted :z (shared) so a cooperating VSCode devcontainer can
# co-mount the same directory without an SELinux MCS label collision.
SBX_PROJECT_LABEL=z
SBX_SOURCE_DIR="__SBX_SOURCE_DIR__"

# Check if an update is available for agy without downloading it.
agy-sandbox-check-update() {
  local auto_mode=0
  [ "${1:-}" = "--auto" ] && auto_mode=1

  local platform="linux_amd64"
  if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    platform="linux_arm64"
  fi
  local manifest_url="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${platform}.json"

  local latest_version
  latest_version=$(curl -fsSL --max-time 3 "$manifest_url" 2>/dev/null | head -c 10240 | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n 1)

  if [ -z "$latest_version" ]; then
    [ $auto_mode -eq 0 ] && echo "Error: Could not fetch latest version info." >&2
    return 1
  fi

  if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    [ $auto_mode -eq 0 ] && echo "Error: Fetched version string has an invalid format: $latest_version" >&2
    return 1
  fi

  local current_version
  current_version=$(agy-sandbox-prompt --version 2>/dev/null | awk '{print $NF}' || echo "unknown")

  if [ "$current_version" != "$latest_version" ] && [ "$current_version" != "unknown" ]; then
    echo -e "\033[1;32mUpdate available: $current_version -> $latest_version\033[0m"
    return 2
  else
    if [ $auto_mode -eq 0 ]; then
      echo "Current version: $current_version"
      echo "Latest version:  $latest_version"
      echo "You are up to date."
    fi
    return 0
  fi
}

# Hook run before each launch: throttled auto update-check (max once / 24h).
_agy_update_hook() {
  local last_check="$HOME/.config/agy-sandbox/last-update-check"
  local now; now=$(date +%s)
  local last_time; last_time=$(cat "$last_check" 2>/dev/null || echo 0)
  if [ $((now - last_time)) -gt 86400 ]; then
    mkdir -p "$HOME/.config/agy-sandbox"
    echo "$now" > "$last_check"
    agy-sandbox-check-update --auto
    if [ $? -eq 2 ]; then
      read -e -p ">> Update now? [y/N] " update_choice
      case "$update_choice" in
        [Yy]*) agy-sandbox-update ;;
      esac
    fi
  fi
}
SBX_UPDATE_HOOK=_agy_update_hook

agy-sandbox()        { _sbx_sandbox_base "" "agy-sandbox" "$@"; }
agy-sandbox-sh()     { _sbx_sandbox_base "/bin/bash" "agy-sandbox-sh" "$@"; }
agy-sandbox-update() { _sbx_update; }

# agy-specific interactive model picker. Everything else uses the shared prompt
# (plain text becomes `agy --print "<text>"`).
_agy_prompt_im() {
  _sbx_require_podman || return 1
  [ $# -gt 0 ] || { echo "usage: agy-sandbox-prompt --im <prompt>" >&2; return 1; }
  local config_dir="$HOME/.local/share/agy-sandbox"
  mkdir -p "$config_dir"
  podman unshare chown -R 1000:1000 "$config_dir"
  local image_id; image_id="$(_sbx_resolve_image)" || return 1

  local prompt="$*"
  local models_output model_list
  models_output="$(podman run --rm --name agy-sandbox-prompt --replace \
    --cap-drop=ALL --security-opt=no-new-privileges \
    -v "$config_dir":/home/agy:Z "$image_id" models)" || return

  model_list="$(printf '%s\n' "$models_output" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' | tr '\r' '\n' | sed '/^[[:space:]]*$/d' | grep -v 'Fetching')" || {
    echo "$models_output" >&2
    echo "Error: could not read any models from 'agy models' output." >&2
    return 1
  }
  [ -n "$model_list" ] || {
    echo "$models_output" >&2
    echo "Error: could not read any models from 'agy models' output." >&2
    return 1
  }

  echo "Available models:" >&2
  printf '%s\n' "$model_list" | awk '{ printf "%3d) %s\n", NR, $0 }' >&2

  local choice selected_model
  while true; do
    printf '>> model number: ' >&2
    IFS= read -r choice || return 1
    case "$choice" in
      ''|*[!0-9]*) echo "Enter a model number from the list." >&2 ;;
      *)
        selected_model="$(printf '%s\n' "$model_list" | sed -n "${choice}p")"
        [ -n "$selected_model" ] && break
        echo "Enter a model number from the list." >&2 ;;
    esac
  done

  podman run --rm --name agy-sandbox-prompt --replace \
    --cap-drop=ALL --security-opt=no-new-privileges \
    -v "$config_dir":/home/agy:Z "$image_id" \
    --model "$selected_model" --prompt "$prompt"
}

# Non-interactive agy wrapper.
#   agy-sandbox-prompt "write hello world in Go"      # -> agy --print "..."
#   agy-sandbox-prompt --im "write hello world in Go" # interactive model pick
#   agy-sandbox-prompt --model gemini-3.1-pro --prompt "..."
#   agy-sandbox-prompt models
agy-sandbox-prompt() {
  if [ "${1:-}" = "--im" ]; then shift; _agy_prompt_im "$@"; return; fi
  _sbx_prompt --print "$@"
}
# <<< agy-sandbox <<<
BLOCK_EOF

SBX_BLOCK="${SBX_BLOCK//__SBX_COMMON_DIR__/$SCRIPT_DIR/common}"
SBX_BLOCK="${SBX_BLOCK//__SBX_SOURCE_DIR__/$SCRIPT_DIR}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common/install-lib.sh"
sbx_install_main "$@"
