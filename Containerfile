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
ARG MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
COPY download-agy.sh /tmp/download-agy.sh
RUN MANIFEST_BASE="${MANIFEST_BASE}" bash /tmp/download-agy.sh && rm /tmp/download-agy.sh

# dedicated non-root user
RUN useradd -m -u 1000 -s /bin/bash agy
USER agy

# config, auth tokens, and Electron/Chromium cache all land here —
# mounted from the host at runtime for persistence
WORKDIR /work
ENTRYPOINT ["agy"]
