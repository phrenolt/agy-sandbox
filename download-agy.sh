#!/usr/bin/env bash
set -euo pipefail

# Override at build time via Containerfile ARG MANIFEST_BASE=<new-url>
MANIFEST_BASE="${MANIFEST_BASE:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app}"

case "$(uname -m)" in
  x86_64|amd64)  platform="linux_amd64" ;;
  arm64|aarch64) platform="linux_arm64" ;;
  *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

manifest=$(curl -fsSL "${MANIFEST_BASE}/manifests/${platform}.json")

url=$(    echo "$manifest" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
sha512=$( echo "$manifest" | sed -n 's/.*"sha512"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
version=$(echo "$manifest" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

[ -n "$url" ] && [ -n "$sha512" ] || { echo "Failed to parse manifest" >&2; exit 1; }
echo ">> downloading agy ${version}..."

curl -fsSL -o /tmp/pkg "$url"
actual=$(sha512sum /tmp/pkg | cut -d' ' -f1)
[ "$actual" = "$sha512" ] || { echo "Checksum mismatch — refusing to install" >&2; exit 1; }
echo ">> checksum OK"

case "$url" in
  *.tar.gz) tar -xzf /tmp/pkg -C /tmp antigravity
            mv /tmp/antigravity /usr/local/bin/agy ;;
  *)        mv /tmp/pkg /usr/local/bin/agy ;;
esac

chmod +x /usr/local/bin/agy
rm -f /tmp/pkg
echo ">> installed agy $(/usr/local/bin/agy --version 2>/dev/null)"
