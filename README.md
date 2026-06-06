# agy-sandbox

Runs the Google Antigravity CLI (`agy`) inside a Podman container — no host modifications, no silent self-updates, no Electron runtime scattered across your home directory.

```bash
agy-sandbox              # launch interactive session
agy-sandbox --print "write a hello world in Go"   # non-interactive
```

## Why containerise it

`agy` is an Electron app (full Chromium runtime) that:
- writes Mesa shader caches, fontconfig, gvfs metadata, and Firefox profile files across your `$HOME` on every run
- requests `cloud-platform` OAuth scope (full Google Cloud access)
- self-updates silently on every invocation

Containerised, all of that is isolated. Auth tokens and config survive between sessions via a bind mount owned by an isolated subUID — not your real user.

## Setup

```bash
# 1. build the image (downloads and verifies agy at build time)
./build.sh

# 2. install the shell function
./install.sh
source ~/.bashrc

# 3. run
agy-sandbox
```

`./install.sh --print` shows the shell block without installing.
`./install.sh --uninstall` removes it (backup saved).

## Updating agy

The version is pinned at image build time. To update:

```bash
cd ~/Projects/agy-sandbox
./build.sh   # pulls latest manifest, re-verifies checksum, rebuilds
```

No silent background updates ever touch your host.

## Auth

On first run `agy` will prompt for Google authentication via browser. The token is stored in `~/.local/share/agy-sandbox/` and reused on subsequent runs.

## How the config persistence works

Config, auth tokens, and Chromium state land in `~/.local/share/agy-sandbox/` on the host, mounted into the container at `/home/agy`. Ownership is set with `podman unshare chown 1000:1000` — inside Podman's user namespace UID 1000 maps to a subUID on the host (e.g. UID 525287), not your real user. If anything escaped the container it would be confined to that subUID and could only touch the config directory.

## Image

Built from `debian:bookworm-slim` with only the Chromium headless runtime deps (no GPU, audio, or font libs — those are only needed when rendering a display). The binary is downloaded from Google's official CDN, SHA512-verified at build time, and not executed during the build (`agy install` is intentionally skipped — shell config is the host's business).

## Requirements

- Podman (rootless)
- A shell (`bash` or `zsh`)
