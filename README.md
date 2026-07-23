# agy-sandbox

Runs the Google Antigravity CLI (`agy`) inside a Podman container — no host modifications, no silent self-updates, no Electron runtime scattered across your home directory.

```bash
agy-sandbox              # launch interactive session (preserves file permissions via --userns=keep-id)
agy-sandbox --strict     # launch strict session (files owned by subUID, maximum isolation)
agy-sandbox-sh           # drop into a bash shell inside the container
agy-sandbox-prompt "write a hello world in Go"   # non-interactive
agy-sandbox-prompt --im "Write a python script to calculate the fibonacci sequence" # allows selecting the model for the prompt interactively
agy-sandbox-prompt --model "Gemini 3.1 Pro (High)" --prompt "Tell what model you are" # note the model is case sensitive! use models below or --im above to call correct model.
agy-sandbox-prompt models    # list available models
agy-sandbox-prompt --usage   # show agy usage
```

## Why containerise it

`agy` is an Electron app (full Chromium runtime) that:
- writes Mesa shader caches, fontconfig, gvfs metadata, and Firefox profile files across your `$HOME` on every run
- requests `cloud-platform` OAuth scope (full Google Cloud access)
- self-updates silently on every invocation

Containerised, all of that is isolated. Auth tokens and config survive between sessions via a bind mount owned by an isolated subUID — not your real user.

## Setup

```bash
# 1. build the image (prompts for optional tools like Cargo, Node, PNPM, Go, Java, Python tools, and PostgreSQL)
./build.sh

# Want a completely barebones container with only Python 3 and no prompts?
./build.sh --raw

# 2. install the shell function
./install.sh
source ~/.bashrc

# 3. run
agy-sandbox
```

`./install.sh --print` shows the shell block without installing.
`./install.sh --uninstall` removes it (backup saved).

## Workspace Permissions & Isolation

By default, `agy-sandbox` uses `--userns=keep-id`. This fluid developer experience maps the container's UID 1000 directly to your host's UID 1000, allowing you to edit the same files in the container and in your host IDE simultaneously without friction or "Permission Denied" errors.

If you want maximum security and lockdown for a session, pass the `--strict` flag:
```bash
agy-sandbox --strict .
```
This forces `podman unshare chown` to take over the project files, locking down ownership to an isolated host subUID exclusively for the lifetime of the container.

## Local Development Database (PostgreSQL)

During `./build.sh`, you can opt to install PostgreSQL 18. If installed, the container automatically initializes and starts a background `postgres` server every time you boot `agy-sandbox`.

- **Persistent**: The database data is stored in `~/.local/share/agy-sandbox/pgdata` on your host. Your data and schemas survive container restarts and rebuilds.
- **Ready to Go**: A default `agy` user and `agy` database are automatically created.

## Updating agy

The version is pinned at image build time. To check if an update is available without downloading:

```bash
agy-sandbox-check-update
```

To update:

```bash
agy-sandbox-update   # pulls latest manifest, re-verifies checksum, rebuilds, repins
```

No silent background updates ever touch your host.

## Image Details

Built from **`debian:trixie-slim`** (Debian 13) with native Python 3 and only the Chromium headless runtime deps (no GPU, audio, or font libs — those are only needed when rendering a display). The binary is downloaded from Google's official CDN, SHA512-verified at build time, and not executed during the build (`agy install` is intentionally skipped — shell config is the host's business).

## Internal Security & Bubblewrap

The only sensitive directory mounted into the container is `~/.gemini` (containing the agent's authentication tokens and instructions). To protect against supply-chain attacks, **all** injected development tools that execute third-party code (Python, Pip, Node, NPM, PNPM, Java, Gradle, Go, and Cargo) are surgically wrapped with `bwrap`.

Whenever you (or a script) run one of these tools, it executes inside a nested Mount Namespace where `~/.gemini` is dynamically replaced with an empty `tmpfs` (RAM disk). Thanks to Linux namespace inheritance, even if a malicious `postinstall` package executes and spawns an infinite tree of nested child processes, the entire execution tree is permanently blinded to your Gemini credentials.

You can optionally inject development environments via the `./build.sh` prompts:
- **Rust:** Cargo (via rustup)
- **Node.js:** Node 20.x, NPM, and PNPM
- **Java:** OpenJDK and Gradle
- **Go:** Golang
- **Python:** Pip and Virtual Environments (`python3-venv`)
- **Database:** PostgreSQL 18
