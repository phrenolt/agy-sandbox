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

# Detect container engine: prefer podman, fall back to docker.
_agy_engine() {
  if command -v podman &>/dev/null; then echo podman
  elif command -v docker &>/dev/null; then echo docker
  else echo ""; fi
}

# Launch the Antigravity CLI inside a container.
# Config, auth tokens, and Electron/Chromium cache are persisted to
# ~/.local/share/agy-sandbox so auth survives between sessions.
#
# Usage:
#   agy-sandbox                    # prompts for project dir (tab-completes)
#   agy-sandbox <dir>              # use <dir> as project dir
#   agy-sandbox <dir> <agy-args>   # ...and pass remaining args to agy
#
# Under podman, both the config dir and the project dir are chowned to
# UID 1000 inside podman's user namespace (host subUID ~525287) while
# the container is running. When the container exits, the project dir is
# chowned back to the host user; the config dir stays under the subUID
# because that is where auth tokens live.
#
# Build the image first:  cd /path/to/agy-sandbox && ./build.sh
agy-sandbox() {
  local engine; engine="$(_agy_engine)"
  [ -n "$engine" ] || { echo "Error: neither podman nor docker found." >&2; return 1; }

  local project_dir
  if [ $# -gt 0 ] && [ -d "$1" ]; then
    project_dir="$(realpath "$1")"; shift
  else
    read -e -p ">> project dir: " -i "$PWD" project_dir
    project_dir="${project_dir/#\~/$HOME}"
    [ -z "$project_dir" ] && { echo "Cancelled."; return 0; }
    if [ ! -d "$project_dir" ]; then
      echo "Error: '$project_dir' is not a directory." >&2; return 1
    fi
    project_dir="$(realpath "$project_dir")"
  fi
  echo ">> mounting: $project_dir -> /work"

  local config_dir="$HOME/.local/share/agy-sandbox"
  mkdir -p "$config_dir"

  local replace_flag=()
  if [ "$engine" = "podman" ]; then replace_flag=(--replace)
  else $engine rm -f agy-sandbox 2>/dev/null || true; fi
  # Pin to the image ID we built, not the :latest tag — another image
  # with the same name (registry pull, accidental rebuild of something
  # else) can't be substituted for us.
  local pin_file="$HOME/.config/agy-sandbox/image-id"
  if [ ! -s "$pin_file" ]; then
    echo "Error: no pinned image ID at $pin_file" >&2
    echo "       Run ./install.sh in the agy-sandbox source dir to build + pin." >&2
    return 1
  fi
  local image_id; image_id="$(cat "$pin_file")"
  if ! $engine image inspect "$image_id" &>/dev/null; then
    echo "Error: pinned image $image_id is no longer present in $engine." >&2
    echo "       Run ./install.sh in the agy-sandbox source dir to rebuild + repin." >&2
    return 1
  fi

  # Podman's rootless user namespace maps namespace UID 0 to the real
  # host user, and UID 1000 to a subUID. Keep the project dir on the
  # subUID only for the lifetime of the container run.
  _agy_restore_project() {
    [ "$engine" = "podman" ] || return 0
    podman unshare chown -R 0:0 "$project_dir" 2>/dev/null || true
  }

  if [ "$engine" = "podman" ]; then
    podman unshare chown -R 1000:1000 "$config_dir"
    podman unshare chown -R 1000:1000 "$project_dir"
  fi

  local status
  if $engine run --rm -it --name agy-sandbox "${replace_flag[@]}" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    -e TERM="${TERM:-xterm-256color}" \
    -v "$config_dir":/home/agy:Z \
    -v "$project_dir":/work:Z \
    "$image_id" \
    "$@"
  then
    status=0
  else
    status=$?
  fi
  _agy_restore_project
  return "$status"
}

# Non-interactive prompt — output goes to stdout, pipeable, no project dir mounted.
# Usage:  agy-sandbox-prompt "write a hello world in Go"
#         result=$(agy-sandbox-prompt "summarise this text: ...")
agy-sandbox-prompt() {
  local engine; engine="$(_agy_engine)"
  [ -n "$engine" ] || { echo "Error: neither podman nor docker found." >&2; return 1; }
  [ -z "${*:-}" ] && { echo "usage: agy-sandbox-prompt <prompt>" >&2; return 1; }
  local config_dir="$HOME/.local/share/agy-sandbox"
  mkdir -p "$config_dir"
  [ "$engine" = "podman" ] && podman unshare chown -R 1000:1000 "$config_dir"
  local pin_file="$HOME/.config/agy-sandbox/image-id"
  [ -s "$pin_file" ] || { echo "Error: no pinned image ID at $pin_file (run ./install.sh)." >&2; return 1; }
  local image_id; image_id="$(cat "$pin_file")"
  $engine image inspect "$image_id" &>/dev/null \
    || { echo "Error: pinned image $image_id no longer present (run ./install.sh)." >&2; return 1; }

  local replace_flag=()
  if [ "$engine" = "podman" ]; then replace_flag=(--replace)
  else $engine rm -f agy-sandbox-prompt 2>/dev/null || true; fi
  $engine run --rm --name agy-sandbox-prompt "${replace_flag[@]}" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    -v "$config_dir":/home/agy:Z \
    "$image_id" \
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
{ strip_block "$RC" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba}'; printf '\n%s\n' "$BLOCK"; } > "$RC.tmp"
mv "$RC.tmp" "$RC"

echo "Installed agy-sandbox into $RC"

# Build the image so the shell function works on first call. Skip if it
# already exists (use ./build.sh directly to force a rebuild) or if
# --no-build was passed.
if [ "${2:-${1:-}}" != "--no-build" ] && [ "${1:-}" != "--no-build" ]; then
  if command -v podman &>/dev/null; then build_engine=podman
  elif command -v docker &>/dev/null; then build_engine=docker
  else build_engine=""; fi
  if [ -n "$build_engine" ] && \
     $build_engine image inspect localhost/agy-sandbox:latest &>/dev/null; then
    echo ">> image localhost/agy-sandbox:latest already present — skipping build"
    echo "   (run ./build.sh to rebuild)"
  else
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "$script_dir/build.sh" ]; then
      echo
      echo ">> building image..."
      (cd "$script_dir" && ./build.sh)
    fi
  fi

  # Pin the built image by its SHA-256 ID so the shell function isn't
  # vulnerable to another image later claiming the localhost/agy-sandbox
  # name.
  if [ -n "$build_engine" ]; then
    image_id="$($build_engine image inspect --format '{{.Id}}' \
                 localhost/agy-sandbox:latest 2>/dev/null || true)"
    if [ -n "$image_id" ]; then
      mkdir -p "$HOME/.config/agy-sandbox"
      printf '%s\n' "$image_id" > "$HOME/.config/agy-sandbox/image-id"
      echo ">> pinned image ID: $image_id"
      echo "   ($HOME/.config/agy-sandbox/image-id)"
    else
      echo "Warning: could not read image ID — agy-sandbox will fail until rebuilt." >&2
    fi
  fi
fi

echo
echo "Run:  source $RC"
echo "Then: agy-sandbox"
