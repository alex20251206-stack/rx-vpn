# RuoxueX-vpn

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
- Subscription URL for a client: from the UI (copy link), or  
  `http://<server-ip>:8139/api/subscription/<client-id>?token=<panel-token>`.

## Client (Ubuntu 24.04)

Install the `.deb` from [Releases](https://github.com/alex20251206-stack/rx-vpn/releases) (or build under `client/ubuntu24/`), then:

```bash
sudo apt install ./rx-vpn-ubuntu_*_all.deb
sudo rx-vpn-ubuntu set-url 'https://<server-ip>:8139/api/subscription/<client-id>?token=<panel-token>'
```

Check status: `rx-vpn-ubuntu status`. Follow combined logs: `sudo rx-vpn-ubuntu logs`.

---

Build the client package locally: `bash scripts/dev-install-client.sh` (from repo root).
