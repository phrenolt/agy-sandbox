#!/usr/bin/env bash
set -euo pipefail

# Override at build time via Containerfile ARG MANIFEST_BASE=<new-url>
MANIFEST_BASE="${MANIFEST_BASE:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app}"

case "$(uname -m)" in
  x86_64|amd64)  platform="linux_amd64" ;;
  arm64|aarch64) platform="linux_arm64" ;;
  *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

# Add bounds to prevent DoS via huge payload or hang
manifest=$(curl -fsSL --max-time 10 "${MANIFEST_BASE}/manifests/${platform}.json" | head -c 10240)

url=$(    echo "$manifest" | grep -o '"url"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n 1)
sha512=$( echo "$manifest" | grep -o '"sha512"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n 1)
version=$(echo "$manifest" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n 1)

[ -n "$url" ] && [ -n "$sha512" ] || { echo "Failed to parse manifest" >&2; exit 1; }

# Validate extracted fields against strict regexes
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: Invalid version format in manifest" >&2; exit 1
fi
if ! [[ "$sha512" =~ ^[a-f0-9]{128}$ ]]; then
  echo "Error: Invalid sha512 format in manifest" >&2; exit 1
fi
if ! [[ "$url" =~ ^https://[a-zA-Z0-9.-]+(/.*)?$ ]]; then
  echo "Error: Invalid URL format in manifest (must be HTTPS)" >&2; exit 1
fi

echo ">> downloading agy ${version}..."

curl -fsSL --max-time 300 -o /tmp/pkg "$url"
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
