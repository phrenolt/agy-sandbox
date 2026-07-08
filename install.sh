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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -r -d '' BLOCK <<'BLOCK_EOF' || true
# >>> agy-sandbox >>>
# Managed by install.sh — edit the script, not this block (re-run to update).

# Detect container engine: prefer podman, fall back to docker.
_agy_engine() {
  if command -v podman &>/dev/null; then echo podman
  elif command -v docker &>/dev/null; then echo docker
  else echo ""; fi
}

_agy_source_dir() {
  printf '%s\n' "__AGY_SANDBOX_SOURCE_DIR__"
}

_agy_pin_image() {
  local engine="$1"
  local image_id
  image_id="$($engine image inspect --format '{{.Id}}' localhost/agy-sandbox:latest 2>/dev/null || true)"
  [ -n "$image_id" ] || { echo "Error: could not read rebuilt image ID." >&2; return 1; }
  mkdir -p "$HOME/.config/agy-sandbox"
  printf '%s\n' "$image_id" > "$HOME/.config/agy-sandbox/image-id"
  echo ">> pinned image ID: $image_id"
  echo "   ($HOME/.config/agy-sandbox/image-id)"
}

# Rebuild agy-sandbox from the installed source directory and repin the
# wrapper to the new image ID.
agy-sandbox-update() {
  local engine; engine="$(_agy_engine)"
  [ -n "$engine" ] || { echo "Error: neither podman nor docker found." >&2; return 1; }

  local source_dir; source_dir="$(_agy_source_dir)"
  if [ ! -f "$source_dir/Containerfile" ] || [ ! -f "$source_dir/download-agy.sh" ]; then
    echo "Error: agy-sandbox source not found at $source_dir" >&2
    echo "       Re-run ./install.sh from the agy-sandbox source directory." >&2
    return 1
  fi

  echo ">> rebuilding localhost/agy-sandbox:latest from $source_dir"
  (cd "$source_dir" && $engine build --no-cache -t localhost/agy-sandbox:latest -f Containerfile .) || return
  _agy_pin_image "$engine"
}

# Check if an update is available for agy without downloading it
agy-sandbox-check-update() {
  local platform="linux_amd64"
  if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    platform="linux_arm64"
  fi
  local manifest_url="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${platform}.json"
  
  local latest_version
  # 1. Limit max download time to prevent hanging
  # 2. Limit byte processing using head to prevent DoS via huge payloads
  # 3. Extract just the version string
  latest_version=$(curl -fsSL --max-time 10 "$manifest_url" 2>/dev/null | head -c 10240 | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n 1)
  
  if [ -z "$latest_version" ]; then
    echo "Error: Could not fetch latest version info." >&2
    return 1
  fi

  # Validate that the version string matches an expected safe format (Semantic Versioning)
  # This prevents malicious payloads or script injections if the URL is hijacked.
  if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Error: Fetched version string has an invalid or unsafe format: $latest_version" >&2
    return 1
  fi

  local current_version
  # We use agy-sandbox-prompt to silently run 'agy --version' inside the container
  current_version=$(agy-sandbox-prompt --version 2>/dev/null | awk '{print $NF}' || echo "unknown")

  echo "Current version: $current_version"
  echo "Latest version:  $latest_version"

  if [ "$current_version" != "$latest_version" ] && [ "$current_version" != "unknown" ]; then
    echo -e "\033[1;32mAn update is available! Run 'agy-sandbox-update' to upgrade.\033[0m"
  else
    echo "You are up to date."
  fi
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
# Update the image later with: agy-sandbox-update
_agy_sandbox_base() {
  local entrypoint="$1"
  local container_name="$2"
  shift 2

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
  else $engine rm -f "$container_name" 2>/dev/null || true; fi
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
  local entrypoint_flag=()
  [ -n "$entrypoint" ] && entrypoint_flag=(--entrypoint "$entrypoint")

  if $engine run --rm -it --name "$container_name" "${replace_flag[@]}" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    "${entrypoint_flag[@]}" \
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

agy-sandbox() {
  _agy_sandbox_base "" "agy-sandbox" "$@"
}

agy-sandbox-sh() {
  _agy_sandbox_base "/bin/bash" "agy-sandbox-sh" "$@"
}

# Non-interactive agy wrapper — output goes to stdout, pipeable, no project dir mounted.
# Usage:  agy-sandbox-prompt "write a hello world in Go"   # legacy prompt shorthand
#         agy-sandbox-prompt --im "write a hello world in Go" # interactive model selection
#         agy-sandbox-prompt --model gemini-3.1-pro --prompt "write a hello world in Go"
#         agy-sandbox-prompt models
#         agy-sandbox-prompt --usage
#         result=$(agy-sandbox-prompt --prompt "summarise this text: ...")
agy-sandbox-prompt() {
  local engine; engine="$(_agy_engine)"
  [ -n "$engine" ] || { echo "Error: neither podman nor docker found." >&2; return 1; }
  [ $# -gt 0 ] || { echo "usage: agy-sandbox-prompt [<agy-args> | <prompt>]" >&2; return 1; }
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

  if [ "${1:-}" = "--im" ]; then
    shift
    [ $# -gt 0 ] || { echo "usage: agy-sandbox-prompt --im <prompt>" >&2; return 1; }

    local prompt="$*"
    local models_output model_list
    models_output="$($engine run --rm --name agy-sandbox-prompt "${replace_flag[@]}" \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      -v "$config_dir":/home/agy:Z \
      "$image_id" \
      models)" || return

    # Preserve model names exactly as `agy models` prints them. Do not split,
    # deduplicate, or infer provider names: multi-word model names are valid.
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
        ''|*[!0-9]*)
          echo "Enter a model number from the list." >&2
          ;;
        *)
          selected_model="$(printf '%s\n' "$model_list" | sed -n "${choice}p")"
          [ -n "$selected_model" ] && break
          echo "Enter a model number from the list." >&2
          ;;
      esac
    done

    $engine run --rm --name agy-sandbox-prompt "${replace_flag[@]}" \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      -v "$config_dir":/home/agy:Z \
      "$image_id" \
      --model "$selected_model" --prompt "$prompt"
    return
  fi

  local agy_args=()
  case "${1:-}" in
    --)
      shift
      [ $# -gt 0 ] || { echo "usage: agy-sandbox-prompt -- <agy-args>" >&2; return 1; }
      agy_args=("$@")
      ;;
    -*|models)
      agy_args=("$@")
      ;;
    *)
      # Backwards-compatible shorthand: plain text becomes `agy --print "<text>"`.
      agy_args=(--print "$*")
      ;;
  esac

  $engine run --rm --name agy-sandbox-prompt "${replace_flag[@]}" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    -v "$config_dir":/home/agy:Z \
    "$image_id" \
    "${agy_args[@]}"
}
# <<< agy-sandbox <<<
BLOCK_EOF
BLOCK="${BLOCK//__AGY_SANDBOX_SOURCE_DIR__/$SCRIPT_DIR}"

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
echo "Then: agy-sandbox (or agy-sandbox-sh to enter the container)"
