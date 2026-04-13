# RX VPN

OpenVPN behind stunnel (TLS on port 443) with a small web panel to issue client profiles.

## Quick Navigation

- [Server](#server)
- [Control panel](#control-panel)
- [RX VPN client (Ubuntu 24.04)](#rx-vpn-client-ubuntu-2404)
- [RX VPN client (Android minimal)](#rx-vpn-client-android-minimal)
- [RX VPN client (macOS, headless + system service)](#rx-vpn-client-macos-headless--system-service)
- [RX VPN client (Windows, headless + system service)](#rx-vpn-client-windows-headless--system-service)

## Server

1. Clone this repo on the host.

2. Create your local Compose file and env (not committed — use the examples):

   ```bash
   cp docker-compose.example.yml docker-compose.yml
   cp .env.example .env
   # edit .env: set OVPN_REMOTE_HOST to this machine's public IP or DNS
   ```

3. Start the stack (image from GitHub Container Registry):

   ```bash
   docker compose pull
   docker compose up -d
   ```

4. Read the panel token once:

   ```bash
   docker compose exec rx cat /data/panel.token
   ```

Requires: Docker with Compose, host networking, `privileged` + `/dev/net/tun` (see `docker-compose.example.yml`). Ports **443** (stunnel) and **8139** (panel) bind on the host.

**Develop locally from source:** in `docker-compose.yml`, comment out `image`, uncomment `build: .`, then `docker compose up -d --build`.

**`VERSION` / panel tag:** the UI and API read the root `VERSION` file. To **auto-increase the patch number on each local commit**, run once per clone: `bash scripts/setup-git-hooks.sh` (sets `core.hooksPath` to `scripts/git-hooks`). If you never ran this, `VERSION` stays unchanged. Skip for one commit: `SKIP_VERSION_BUMP=1 git commit ...`.

**README version examples:** on each **`git push`**, the `pre-push` hook updates concrete `vX.Y.Z` / `rx-vpn-*-X.Y.Z` examples in this file to match the **latest local semver tag** `vMAJOR.MINOR.PATCH` (by version sort). If it changes `README.md`, it creates a commit and **aborts the push** — run `git push` again. Skip: `SKIP_README_SYNC=1 git push ...`. Manual: `bash scripts/sync-readme-version-from-latest-tag.sh`.

**Client `.deb` vs git tag:** CI runs `scripts/deb-set-changelog-from-tag.sh` before `dpkg-buildpackage`. Pushing tag **`v1.2.3`** produces **`rx-vpn-ubuntu_1.2.3-1_all.deb`** on the Release. The workflow **`rx-deb`** (tag pattern `rx-v*`) does the same when built from a tag.

## Control panel

- URL: **`http://<server-ip>:8139/`** (or `https://` if you terminate TLS elsewhere).
- Open the page, paste the **panel token** (same as `/data/panel.token`), then create or manage clients.
- Subscription URL for a client (copy from the UI): uses **`OVPN_REMOTE_HOST`** from your server `.env` as the host (not the browser address bar), e.g.  
  `http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>` (six-character `sub-code`, letters and digits; no query string).  
  The older path `/api/subscription/<uuid>` still works.  
  If the panel is behind HTTPS or on a non-default port, set optional **`PANEL_PUBLIC_SCHEME`** and **`PANEL_PUBLIC_PORT`** in `.env` (see `.env.example`).

## RX VPN client (Ubuntu 24.04)

The Linux **RX VPN client** is shipped as the Debian binary package **`rx-vpn-ubuntu`**, which installs the **`rx-vpn-ubuntu`** command (stunnel TLS to the server, OpenVPN to a local port, systemd units).

### Install from a release package

Download `rx-vpn-ubuntu_*_all.deb` from [Releases](https://github.com/alex20251206-stack/rx-vpn/releases), then:

```bash
sudo apt install ./rx-vpn-ubuntu_*_all.deb
sudo rx-vpn-ubuntu set-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'
```

Use the exact URL copied from the panel (it matches **`OVPN_REMOTE_HOST`** and optional **`PANEL_PUBLIC_*`** from `.env`). Check status: `rx-vpn-ubuntu status`. Follow combined logs: `sudo rx-vpn-ubuntu logs`.

### Build and install from source

From the repository root, install the Debian packaging tools, then run the helper script (it builds under `client/ubuntu24/` and installs the resulting `.deb`):

```bash
sudo apt-get update && sudo apt-get install -y dpkg-dev debhelper
bash scripts/dev-install-client.sh
```

### Status and debugging

```bash
rx-vpn-ubuntu status
sudo rx-vpn-ubuntu logs
```

`rx-vpn-ubuntu status` shows the current client state; `rx-vpn-ubuntu logs` tails the combined service logs (requires root).

## RX VPN client (Android minimal)

A minimal Android app is available under `client/android` (reference direction: `ics-openvpn`):
- maintain subscription URLs
- display realtime link speed
- built-in `VpnService` start/stop skeleton (no external app dependency)
- embedded native dependency path for `openvpn` and `stunnel` (`app/src/main/jniLibs/arm64-v8a/`)
- arm64 binaries are bundled in-repo (source package checksums in `third_party/android/`)
- Android code is flattened into `client/android/app` as a standalone module (no vendor/project mapping)

Open `client/android` with Android Studio to build and run.

Tag release (`vX.Y.Z`) also builds and uploads an Android asset:
- `rx-vpn-android-0.1.7-universal.apk` (universal APK, debug-signed in CI for sideload; re-sign for Play if needed)

## RX VPN client (macOS, headless + system service)

The macOS client is a CLI command `rx-vpn-macos` (no GUI), using `launchd` system daemons (`/Library/LaunchDaemons`) to keep stunnel + OpenVPN running in the background.

### Install on macOS (run one installer script)

Run the installer script directly (it installs Homebrew dependencies `openvpn` + `stunnel`, downloads release tarball, verifies SHA256, and installs `rx-vpn-macos`):

```bash
curl -fsSL https://raw.githubusercontent.com/alex20251206-stack/rx-vpn/main/scripts/install-macos-client.sh | bash
sudo rx-vpn-macos set-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/alex20251206-stack/rx-vpn/main/scripts/install-macos-client.sh | bash -s -- --version v0.1.8
```

Install and configure in one step:

```bash
curl -fsSL https://raw.githubusercontent.com/alex20251206-stack/rx-vpn/main/scripts/install-macos-client.sh | \
  bash -s -- --sub-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'
```

Notes:
- `set-url` bootstraps two system services: `com.rxvpn.stunnel` and `com.rxvpn.openvpn`.
- If Homebrew is missing, install it from [brew.sh](https://brew.sh/) first.

### Commands (daily use)

```bash
rx-vpn-macos status
sudo rx-vpn-macos refresh
sudo rx-vpn-macos disable
sudo rx-vpn-macos logs
```

`set-url` / `refresh` run as root because they write service files and bootstrap `launchd` system services.

## RX VPN client (Windows, headless + system service)

The Windows client is a PowerShell CLI (`rx-vpn-windows`) with two NSSM-managed services:
- `RXVPN-Stunnel`
- `RXVPN-OpenVPN`

### Install in one command (Administrator PowerShell)

```powershell
irm https://raw.githubusercontent.com/alex20251206-stack/rx-vpn/main/scripts/install-windows-client.ps1 | iex
rx-vpn-windows set-url "http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>"
```

### Offline install (no external download during install)

1) Download from Release:
- `rx-vpn-windows-offline-0.1.8.zip`
- `rx-vpn-windows-offline-0.1.8.sha256`

2) Verify SHA256 and run installer from extracted bundle (Administrator PowerShell):

```powershell
certutil -hashfile .\rx-vpn-windows-offline-0.1.8.zip SHA256
Expand-Archive .\rx-vpn-windows-offline-0.1.8.zip -DestinationPath .
powershell -ExecutionPolicy Bypass -File .\rx-vpn-windows-offline-0.1.8\scripts\install-windows-client.ps1
rx-vpn-windows set-url "http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>"
```

Install + configure in one run:

```powershell
$tmp = Join-Path $env:TEMP "install-rx-vpn-windows.ps1"
irm https://raw.githubusercontent.com/alex20251206-stack/rx-vpn/main/scripts/install-windows-client.ps1 -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp -SubUrl "http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>"
```

Notes:
- Run PowerShell as Administrator.
- Online mode: installer downloads pinned versions from this repository (`third_party/windows`) and verifies SHA256.
- Offline mode: installer uses bundled files first; no external dependency downloads during install.
- It installs OpenVPN, stunnel, NSSM, and `rx-vpn-windows`.
- Default install paths:
  - `rx-vpn-windows` command files: `C:\Program Files\rx-vpn\`
  - client state/config/log: `C:\ProgramData\rx-vpn\`
    - `subscription.url`, `client.ovpn`, `stunnel.conf`, `stunnel-ca.pem`, `client.log`
  - NSSM: `C:\Program Files\nssm\`
  - OpenVPN (MSI default): `C:\Program Files\OpenVPN\`
  - stunnel (installer default): `C:\Program Files (x86)\stunnel\`
  - Services: `RXVPN-Stunnel` and `RXVPN-OpenVPN`

### Commands

```powershell
rx-vpn-windows status
rx-vpn-windows refresh
rx-vpn-windows disable
rx-vpn-windows logs
```
