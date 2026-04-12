#!/bin/bash
set -euo pipefail
install -d -m 0755 /data/openvpn /data/stunnel /data/panel /logs
# Log files for panel (systemd append), OpenVPN (nobody), stunnel (root)
: >> /logs/panel.log
: >> /logs/openvpn.log
: >> /logs/stunnel.log
: >> /logs/openvpn-status.log
chmod 644 /logs/panel.log /logs/stunnel.log
chmod 664 /logs/openvpn.log /logs/openvpn-status.log
chown root:root /logs/panel.log /logs/stunnel.log
chown nobody:nogroup /logs/openvpn.log /logs/openvpn-status.log
export PYTHONPATH=/opt/panel
if [[ ! -f /data/panel.token ]]; then
  openssl rand -hex 32 > /data/panel.token
  chmod 0600 /data/panel.token
fi
python3 -c "from app.pki import ensure_pki_and_server; ensure_pki_and_server()"
