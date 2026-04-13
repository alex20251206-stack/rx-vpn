# RX VPN

OpenVPN behind stunnel (TLS on port 443) with a small web panel to issue client profiles.

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

## RX VPN client (macOS, headless + system service)

The macOS client is a CLI command `rx-vpn-macos` (no GUI), using `launchd` system daemons (`/Library/LaunchDaemons`) to keep stunnel + OpenVPN running in the background.

### Install on macOS (Homebrew deps + release tarball)

After a tag release (`vX.Y.Z`) is pushed, CI uploads `rx-vpn-macos-X.Y.Z.tar.gz` and `rx-vpn-macos-X.Y.Z.sha256` to GitHub Releases.

Install dependencies with Homebrew, then install the client command from the release tarball:

```bash
brew install openvpn stunnel
curl -fL -o /tmp/rx-vpn-macos.tar.gz \
  https://github.com/alex20251206-stack/rx-vpn/releases/download/v0.1.3/rx-vpn-macos-0.1.3.tar.gz
tar -xzf /tmp/rx-vpn-macos.tar.gz -C /tmp
sudo install -m 0755 /tmp/rx-vpn-macos /usr/local/bin/rx-vpn-macos
sudo rx-vpn-macos set-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'
```

Notes:
- Replace `v0.1.3` / `0.1.3` with the release version you want.
- `set-url` bootstraps two system services: `com.rxvpn.stunnel` and `com.rxvpn.openvpn`.

### Commands (daily use)

```bash
rx-vpn-macos status
sudo rx-vpn-macos refresh
sudo rx-vpn-macos disable
sudo rx-vpn-macos logs
```

`set-url` / `refresh` run as root because they write service files and bootstrap `launchd` system services.
