#!/usr/bin/env bash
# Build the agy-sandbox image. Re-run to update to the latest agy release.
set -euo pipefail

if command -v podman &>/dev/null; then
  engine=podman
elif command -v docker &>/dev/null; then
  engine=docker
else
  echo "Error: neither podman nor docker found." >&2; exit 1
fi
echo ">> using: $engine"

opts_file="$HOME/.config/agy-sandbox/build-opts"
if [ "${1:-}" = "--raw" ]; then
  INSTALL_CARGO=false
  INSTALL_PIP=false
  INSTALL_NODE=false
  INSTALL_PNPM=false
  INSTALL_POSTGRES=false
  INSTALL_JDK=false
  INSTALL_GRADLE=false
  INSTALL_GO=false
elif [ "${1:-}" = "--auto" ] && [ -f "$opts_file" ]; then
  source "$opts_file"
else
  read -p "Install Cargo (Rust)? [y/N] " prompt_cargo
  read -p "Install Pip & Venv (Python)? [y/N] " prompt_pip
  
  read -p "Install Node? [y/N] " prompt_node
  prompt_pnpm="n"
  case "$prompt_node" in [Yy]*) read -p "  Install PNPM? [y/N] " prompt_pnpm ;; esac
  
  read -p "Install JDK (Java)? [y/N] " prompt_jdk
  prompt_gradle="n"
  case "$prompt_jdk" in [Yy]*) read -p "  Install Gradle? [y/N] " prompt_gradle ;; esac
  
  read -p "Install Go? [y/N] " prompt_go
  read -p "Install PostgreSQL (Local Testing)? [y/N] " prompt_postgres
  
  INSTALL_CARGO=false
  INSTALL_PIP=false
  INSTALL_NODE=false
  INSTALL_PNPM=false
  INSTALL_POSTGRES=false
  INSTALL_JDK=false
  INSTALL_GRADLE=false
  INSTALL_GO=false
  
  case "$prompt_cargo" in [Yy]*) INSTALL_CARGO=true ;; esac
  case "$prompt_pip" in [Yy]*) INSTALL_PIP=true ;; esac
  case "$prompt_node" in [Yy]*) INSTALL_NODE=true ;; esac
  case "$prompt_pnpm" in [Yy]*) INSTALL_PNPM=true ;; esac
  case "$prompt_postgres" in [Yy]*) INSTALL_POSTGRES=true ;; esac
  case "$prompt_jdk" in [Yy]*) INSTALL_JDK=true ;; esac
  case "$prompt_gradle" in [Yy]*) INSTALL_GRADLE=true ;; esac
  case "$prompt_go" in [Yy]*) INSTALL_GO=true ;; esac
  
  mkdir -p "$HOME/.config/agy-sandbox"
  echo "INSTALL_CARGO=$INSTALL_CARGO" > "$opts_file"
  echo "INSTALL_PIP=$INSTALL_PIP" >> "$opts_file"
  echo "INSTALL_NODE=$INSTALL_NODE" >> "$opts_file"
  echo "INSTALL_PNPM=$INSTALL_PNPM" >> "$opts_file"
  echo "INSTALL_POSTGRES=$INSTALL_POSTGRES" >> "$opts_file"
  echo "INSTALL_JDK=$INSTALL_JDK" >> "$opts_file"
  echo "INSTALL_GRADLE=$INSTALL_GRADLE" >> "$opts_file"
  echo "INSTALL_GO=$INSTALL_GO" >> "$opts_file"
fi

echo ">> INSTALL_CARGO=$INSTALL_CARGO, INSTALL_PIP=$INSTALL_PIP, INSTALL_NODE=$INSTALL_NODE, INSTALL_PNPM=$INSTALL_PNPM, INSTALL_POSTGRES=$INSTALL_POSTGRES, INSTALL_JDK=$INSTALL_JDK, INSTALL_GRADLE=$INSTALL_GRADLE, INSTALL_GO=$INSTALL_GO"

$engine build --no-cache \
  --build-arg INSTALL_CARGO="$INSTALL_CARGO" \
  --build-arg INSTALL_PIP="$INSTALL_PIP" \
  --build-arg INSTALL_NODE="$INSTALL_NODE" \
  --build-arg INSTALL_PNPM="$INSTALL_PNPM" \
  --build-arg INSTALL_POSTGRES="$INSTALL_POSTGRES" \
  --build-arg INSTALL_JDK="$INSTALL_JDK" \
  --build-arg INSTALL_GRADLE="$INSTALL_GRADLE" \
  --build-arg INSTALL_GO="$INSTALL_GO" \
  -t localhost/agy-sandbox:latest -f Containerfile .
echo ">> built: localhost/agy-sandbox:latest"
echo ">> run:   agy-sandbox"
