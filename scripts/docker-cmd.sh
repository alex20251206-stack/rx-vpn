#!/bin/bash
set -euo pipefail
# Write systemd EnvironmentFile from container env (docker-compose / .env) so services do not
# keep image defaults; matches OVPN_REMOTE_HOST users set on the host.
{
  echo "# Generated at container start from container environment (e.g. docker-compose .env)."
  echo "OVPN_REMOTE_HOST=${OVPN_REMOTE_HOST:-127.0.0.1}"
  _rp="${OVPN_REMOTE_PORT:-443}"
  echo "OVPN_REMOTE_PORT=${_rp}"
  echo "STUNNEL_ACCEPT=${STUNNEL_ACCEPT:-${_rp}}"
  echo "PANEL_PUBLIC_SCHEME=${PANEL_PUBLIC_SCHEME:-http}"
  echo "PANEL_PUBLIC_PORT=${PANEL_PUBLIC_PORT:-8139}"
} > /etc/default/ovpn-panel
exec /lib/systemd/systemd --system
