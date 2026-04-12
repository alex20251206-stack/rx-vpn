# Ruoxue VPN

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

## Control panel

- URL: **`http://<server-ip>:8139/`** (or `https://` if you terminate TLS elsewhere).
- Open the page, paste the **panel token** (same as `/data/panel.token`), then create or manage clients.
- Subscription URL for a client (copy from the UI): uses **`OVPN_REMOTE_HOST`** from your server `.env` as the host (not the browser address bar), e.g.  
  `http://<OVPN_REMOTE_HOST>:8139/api/subscription/<client-id>?token=<panel-token>`.  
  If the panel is behind HTTPS or on a non-default port, set optional **`PANEL_PUBLIC_SCHEME`** and **`PANEL_PUBLIC_PORT`** in `.env` (see `.env.example`).

## Client (Ubuntu 24.04)

### Install from a release package

Download `ovpn-panel-client_*_all.deb` from [Releases](https://github.com/alex20251206-stack/rx-vpn/releases), then:

```bash
sudo apt install ./ovpn-panel-client_*_all.deb
sudo ovpn-panel-client set-url 'http://<OVPN_REMOTE_HOST>:8139/api/subscription/<client-id>?token=<panel-token>'
```

Use the exact URL copied from the panel (it matches **`OVPN_REMOTE_HOST`** and optional **`PANEL_PUBLIC_*`** from `.env`).

### Build and install from source

From the repository root, install the Debian packaging tools, then run the helper script (it builds under `client/ubuntu24/` and installs the resulting `.deb`):

```bash
sudo apt-get update && sudo apt-get install -y dpkg-dev debhelper
bash scripts/dev-install-client.sh
```

### Status and debugging

```bash
ovpn-panel-client status
sudo ovpn-panel-client logs
```

`status` shows the current client state; `logs` tails the combined service logs (requires root).
