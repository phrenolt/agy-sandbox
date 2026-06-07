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

set -euo pipefail

MARK_START="# >>> agy-sandbox >>>"
MARK_END="# <<< agy-sandbox <<<"

read -r -d '' BLOCK <<'BLOCK_EOF' || true
# >>> agy-sandbox >>>
# Managed by install.sh — edit the script, not this block (re-run to update).

# Launch the Antigravity CLI inside a Podman container.
# Config, auth tokens, and Electron/Chromium cache are persisted to
# ~/.local/share/agy-sandbox so auth survives between sessions.
#
# podman unshare chown maps the config dir to the container's agy user (UID 1000)
# in Podman's user namespace — the host sees it as a subUID, not your real user.
#
# Build the image first:  cd ~/Projects/agy-sandbox && ./build.sh
agy-sandbox() {
  printf '>> agy will see: %s\n   Run from here? [y/N] ' "$PWD"
  local answer; read -r answer
  [[ "${answer:-}" =~ ^[Yy]$ ]] || { echo "Cancelled."; return 0; }
  local config_dir="$HOME/.local/share/agy-sandbox"
  mkdir -p "$config_dir"
  podman unshare chown -R 1000:1000 "$config_dir"
  podman run --rm -it \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    -e TERM="${TERM:-xterm-256color}" \
    -v "$config_dir":/home/agy:Z \
    -v "$PWD":/work:Z \
    localhost/agy-sandbox:latest \
    "$@"
}

# Non-interactive prompt — output goes to stdout, pipeable, no project dir mounted.
# Usage:  agy-sandbox-prompt "write a hello world in Go"
#         result=$(agy-sandbox-prompt "summarise this text: ...")
agy-sandbox-prompt() {
  [ -z "${*:-}" ] && { echo "usage: agy-sandbox-prompt <prompt>" >&2; return 1; }
  local config_dir="$HOME/.local/share/agy-sandbox"
  mkdir -p "$config_dir"
  podman unshare chown -R 1000:1000 "$config_dir"
  podman run --rm -i \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    -v "$config_dir":/home/agy:Z \
    localhost/agy-sandbox:latest \
    --print "$*"
}
# <<< agy-sandbox <<<
BLOCK_EOF

detect_rc() {
  if [ -n "${1:-}" ]; then echo "$1"; return; fi
  case "${SHELL:-}" in
    *zsh) echo "$HOME/.zshrc" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

strip_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  sed "/^${MARK_START}$/,/^${MARK_END}$/d" "$file"
}

case "${1:-}" in
  --print)
    printf '%s\n' "$BLOCK"
    exit 0
    ;;
  --uninstall)
    RC="$(detect_rc "${2:-}")"
    [ -f "$RC" ] || { echo "Nothing to remove: $RC not found."; exit 0; }
    cp "$RC" "$RC.bak.$(date +%Y%m%d-%H%M%S)"
    strip_block "$RC" > "$RC.tmp" && mv "$RC.tmp" "$RC"
    echo "Removed agy-sandbox from $RC (backup saved)."
    exit 0
    ;;
esac

RC="$(detect_rc "${1:-}")"
touch "$RC"
cp "$RC" "$RC.bak.$(date +%Y%m%d-%H%M%S)"
{ strip_block "$RC"; printf '\n%s\n' "$BLOCK"; } > "$RC.tmp"
mv "$RC.tmp" "$RC"

echo "Installed agy-sandbox into $RC"
echo "Run:  source $RC"
echo "Then: agy-sandbox"
