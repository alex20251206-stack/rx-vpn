"""Paths and environment for the panel."""
from __future__ import annotations

import os
from pathlib import Path

DATA = Path(os.environ.get("PANEL_DATA", "/data"))
LOG_DIR = Path(os.environ.get("LOG_DIR", "/logs"))
PANEL_TOKEN_FILE = Path(os.environ.get("PANEL_TOKEN_FILE", str(DATA / "panel.token")))
CLIENTS_FILE = Path(os.environ.get("CLIENTS_FILE", str(DATA / "panel" / "clients.json")))

# Host-mounted log dir (see docker-compose logs volume)
LOG_FILE_PANEL = LOG_DIR / "panel.log"
LOG_FILE_OPENVPN = LOG_DIR / "openvpn.log"
LOG_FILE_STUNNEL = LOG_DIR / "stunnel.log"
STATUS_LOG = LOG_DIR / "openvpn-status.log"

OPENVPN_DIR = Path(os.environ.get("OPENVPN_DIR", str(DATA / "openvpn")))
CCD_DIR = OPENVPN_DIR / "ccd"
EASYRSA_PKI = Path(os.environ.get("EASYRSA_PKI", str(OPENVPN_DIR / "easy-rsa" / "pki")))
EASYRSA_BIN = Path(os.environ.get("EASYRSA_BIN", "/usr/share/easy-rsa/easyrsa"))
SERVER_CONF = OPENVPN_DIR / "server.conf"
STUNNEL_DIR = Path(os.environ.get("STUNNEL_DIR", str(DATA / "stunnel")))
STUNNEL_CONF = STUNNEL_DIR / "stunnel.conf"
STUNNEL_PEM = STUNNEL_DIR / "stunnel.pem"

OVPN_REMOTE_HOST = os.environ.get("OVPN_REMOTE_HOST", "127.0.0.1")
OVPN_REMOTE_PORT = os.environ.get("OVPN_REMOTE_PORT", "443")
STUNNEL_ACCEPT = os.environ.get("STUNNEL_ACCEPT", OVPN_REMOTE_PORT)

# VPN subnet (topology subnet)
VPN_NETWORK = os.environ.get("VPN_NETWORK", "10.8.0.0")
VPN_NETMASK = os.environ.get("VPN_NETMASK", "255.255.255.0")
# Server takes .1, clients .2+
VPN_POOL_START = int(os.environ.get("VPN_POOL_START", "2"))
