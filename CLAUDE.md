# Claude notes — agy-sandbox

## How the manifest URL was found

The user pasted the official Antigravity install script (sourced from `https://antigravity.google/download#antigravity-cli`). At the top of that script, the URL is declared as a constant:

```bash
DOWNLOAD_BASE_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
```

To re-extract it if the URL ever changes: fetch the install script and grep for that variable.

```bash
curl -fsSL https://antigravity.google/install | grep 'DOWNLOAD_BASE_URL='
```

The manifest for a given platform is then at:

```
$DOWNLOAD_BASE_URL/manifests/<platform>.json
```

where `<platform>` is one of: `linux_amd64`, `linux_arm64`, `linux_amd64_musl`, `linux_arm64_musl`, `darwin_amd64`, `darwin_arm64`.

The manifest JSON contains `version`, `url` (tarball on GCS), and `sha512`.

## Key facts about the binary

- `agy` is an **Electron app** (Chromium embedded), not a native CLI — confirmed by Mesa shader cache, fontconfig, gvfs-metadata, and Firefox profile files written to `$HOME` on first run
- The binary is a glibc-linked ELF (`interpreter /lib64/ld-linux-x86-64.so.2`) — Alpine/musl won't work for the amd64 build; use `debian:bookworm-slim`
- Config lands in `~/.gemini/` inside the container (same path as Gemini CLI)
- OAuth scopes include `cloud-platform` (broad Google Cloud access) — token is stored in `/home/agy/.gemini/` which maps to `~/.local/share/agy-sandbox/` on the host
- `agy install` modifies shell rc files — intentionally skipped in the Containerfile

## Ownership / UID

Container runs as `agy` (UID 1000). Config dir ownership is set with `podman unshare chown -R 1000:1000` which maps to host subUID ~525287 (not the real user), verified with `stat -c "%u" ~/.local/share/agy-sandbox`.
