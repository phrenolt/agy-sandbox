FROM debian:bookworm-slim
LABEL org.opencontainers.image.title="agy-sandbox"

# agy is an Electron/Chromium app running headless (no display).
# GPU, audio, font, and screen libs are not needed — only the Chromium
# core runtime deps that it links even in CLI mode.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates \
      libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
      libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
      libpango-1.0-0 libcairo2 \
 && rm -rf /var/lib/apt/lists/*

# Download, verify, and install the agy binary.
# Version is pinned at image build time — rebuild to update.
# We intentionally do NOT run 'agy install' — that modifies shell rc files,
# which is the host's business, not the container's.
RUN set -euo pipefail; \
    case "$(uname -m)" in \
      x86_64|amd64)  platform="linux_amd64" ;; \
      arm64|aarch64) platform="linux_arm64" ;; \
      *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    manifest=$(curl -fsSL \
      "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${platform}.json"); \
    url=$(echo "$manifest"    | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'); \
    sha512=$(echo "$manifest" | sed -n 's/.*"sha512"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'); \
    version=$(echo "$manifest" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'); \
    [ -n "$url" ] && [ -n "$sha512" ] \
      || { echo "Failed to parse manifest" >&2; exit 1; }; \
    echo ">> downloading agy ${version}..."; \
    curl -fsSL -o /tmp/pkg "$url"; \
    actual=$(sha512sum /tmp/pkg | cut -d' ' -f1); \
    [ "$actual" = "$sha512" ] \
      || { echo "Checksum mismatch — refusing to install" >&2; exit 1; }; \
    echo ">> checksum OK"; \
    case "$url" in \
      *.tar.gz) tar -xzf /tmp/pkg -C /tmp antigravity; \
                mv /tmp/antigravity /usr/local/bin/agy ;; \
      *)        mv /tmp/pkg /usr/local/bin/agy ;; \
    esac; \
    chmod +x /usr/local/bin/agy; \
    rm -f /tmp/pkg; \
    echo ">> installed agy $(/usr/local/bin/agy --version 2>/dev/null)"

# dedicated non-root user
RUN useradd -m -u 1000 -s /bin/bash agy
USER agy

# config, auth tokens, and Electron/Chromium cache all land here —
# mounted from the host at runtime for persistence
WORKDIR /work
