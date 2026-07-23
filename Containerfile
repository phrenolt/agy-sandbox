FROM debian:trixie-slim
LABEL org.opencontainers.image.title="agy-sandbox"

# agy is an Electron/Chromium app running headless (no display).
# GPU, audio, font, and screen libs are not needed — only the Chromium
# core runtime deps that it links even in CLI mode.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates bubblewrap build-essential \
      libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
      libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
      libpango-1.0-0 libcairo2 \
      python3 git \
 && rm -rf /var/lib/apt/lists/*

# Helper to securely wrap binaries with bwrap while preventing nested bwrap crashes
RUN echo '#!/bin/bash' > /usr/local/bin/wrap-binary && \
    echo 'target="$1"' >> /usr/local/bin/wrap-binary && \
    echo 'if [ ! -f "$target" ]; then exit 0; fi' >> /usr/local/bin/wrap-binary && \
    echo 'mv "$target" "$target.real"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "#!/bin/bash" > "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "if [ \"\$AGY_SANDBOX_BWRAP\" = \"1\" ]; then" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "  exec \"\$0.real\" \"\$@\"" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "else" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "  export AGY_SANDBOX_BWRAP=1" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "  exec bwrap --unshare-user --uid 1000 --gid 1000 --bind / / --tmpfs /home/agy/.gemini \"\$0.real\" \"\$@\"" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'echo "fi" >> "$target"' >> /usr/local/bin/wrap-binary && \
    echo 'chmod +x "$target"' >> /usr/local/bin/wrap-binary && \
    chmod +x /usr/local/bin/wrap-binary

# Wrap base binaries
RUN wrap-binary /usr/bin/python3

ARG INSTALL_PIP=false
RUN if [ "$INSTALL_PIP" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends python3-venv python3-pip && \
      wrap-binary /usr/bin/pip3 && wrap-binary /usr/bin/pip && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_NODE=false
RUN if [ "$INSTALL_NODE" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends nodejs npm && \
      wrap-binary /usr/bin/node && wrap-binary /usr/bin/npm && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_PNPM=false
RUN if [ "$INSTALL_PNPM" = "true" ]; then \
      if ! command -v npm >/dev/null; then echo "Error: PNPM requires Node (INSTALL_NODE=true)" >&2; exit 1; fi && \
      npm install -g pnpm@9 && \
      wrap-binary /usr/local/bin/pnpm && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_JDK=false
RUN if [ "$INSTALL_JDK" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends default-jdk && \
      wrap-binary /usr/bin/java && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_GRADLE=false
RUN if [ "$INSTALL_GRADLE" = "true" ]; then \
      if ! command -v java >/dev/null; then echo "Error: Gradle requires JDK (INSTALL_JDK=true)" >&2; exit 1; fi && \
      apt-get update && apt-get install -y --no-install-recommends gradle && \
      wrap-binary /usr/bin/gradle && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_GO=false
ENV GOPATH=/home/agy/go
ENV PATH=$PATH:$GOPATH/bin
RUN if [ "$INSTALL_GO" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends golang && \
      wrap-binary /usr/bin/go && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

ARG INSTALL_CARGO=false
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN if [ "$INSTALL_CARGO" = "true" ]; then \
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
      chmod -R a+rw /usr/local/cargo /usr/local/rustup && \
      wrap-binary /usr/local/cargo/bin/cargo && \
      curl -LsSf https://github.com/taiki-e/cargo-llvm-cov/releases/download/v0.8.7/cargo-llvm-cov-x86_64-unknown-linux-gnu.tar.gz | tar xzf - -C /usr/local/cargo/bin ; \
    fi

ARG INSTALL_POSTGRES=false
RUN if [ "$INSTALL_POSTGRES" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends gnupg && \
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
      echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/postgresql.list && \
      apt-get update && apt-get install -y --no-install-recommends postgresql-18 && \
      rm -rf /var/lib/apt/lists/* ; \
    fi
ENV PATH=/usr/lib/postgresql/18/bin:$PATH

# Download, verify, and install the agy binary.
# Version is pinned at image build time — rebuild to update.
# We intentionally do NOT run 'agy install' — that modifies shell rc files,
# which is the host's business, not the container's.
ARG MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
COPY download-agy.sh /tmp/download-agy.sh
RUN MANIFEST_BASE="${MANIFEST_BASE}" bash /tmp/download-agy.sh && rm /tmp/download-agy.sh

# Create entrypoint script for DB initialization and routing
RUN printf '#!/bin/bash\n\
if command -v pg_ctl >/dev/null 2>&1; then\n\
  export PGDATA=/home/agy/pgdata\n\
  rm -f "$PGDATA/postmaster.pid"\n\
  if [ ! -d "$PGDATA" ]; then\n\
    echo ">> Initializing PostgreSQL..."\n\
    initdb -D "$PGDATA" --auth-local=trust --auth-host=trust\n\
    pg_ctl -D "$PGDATA" -o "-k /tmp" -l /home/agy/pg.log start\n\
    sleep 2\n\
    createuser -h /tmp -s agy || true\n\
    createdb -h /tmp agy || true\n\
  else\n\
    echo ">> Starting PostgreSQL..."\n\
    pg_ctl -D "$PGDATA" -o "-k /tmp" -l /home/agy/pg.log start\n\
  fi\n\
fi\n\
\n\
if [ $# -eq 0 ]; then\n\
  exec agy\n\
elif [ "$1" = "/bin/bash" ]; then\n\
  exec "$@"\n\
else\n\
  exec agy "$@"\n\
fi\n' > /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# dedicated non-root user
RUN useradd -m -u 1000 -s /bin/bash agy
USER agy

# config, auth tokens, and Electron/Chromium cache all land here —
# mounted from the host at runtime for persistence
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
