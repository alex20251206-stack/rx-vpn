# RuoxueX-vpn

OpenVPN behind stunnel (TLS on port 443) with a small web panel to issue client profiles.

## Server

1. Clone this repo on the host (or copy `docker-compose.yml` and `.env.example`).
2. Copy env and set your **public IP or DNS** (what clients use to reach this machine):

   ```bash
   cp .env.example .env
   # edit OVPN_REMOTE_HOST
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

Requires: Docker with Compose, host networking, `privileged` + `/dev/net/tun` (see `docker-compose.yml`). Ports **443** (stunnel) and **8139** (panel) bind on the host.

## Control panel

- URL: **`http://<server-ip>:8139/`** (or `https://` if you terminate TLS elsewhere).
- Open the page, paste the **panel token** (same as `/data/panel.token`), then create or manage clients.
- Subscription URL for a client: from the UI (copy link), or  
  `http://<server-ip>:8139/api/subscription/<client-id>?token=<panel-token>`.

## Client (Ubuntu 24.04)

Install the `.deb` from [Releases](https://github.com/alex20251206-stack/rx-vpn/releases) (or build under `client/ubuntu24/`), then:

```bash
sudo apt install ./ovpn-panel-client_*_all.deb
sudo ovpn-panel-client set-url 'https://<server-ip>:8139/api/subscription/<client-id>?token=<panel-token>'
```

Check status: `ovpn-panel-client status`. Follow combined logs: `sudo ovpn-panel-client logs`.

---

Build the client package locally: `bash scripts/dev-install-client.sh` (from repo root).
