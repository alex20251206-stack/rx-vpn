"""OpenVPN PKI (easy-rsa) and server bootstrap."""
from __future__ import annotations

import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from app.config import (
    CCD_DIR,
    EASYRSA_BIN,
    EASYRSA_PKI,
    LOG_DIR,
    LOG_FILE_OPENVPN,
    LOG_FILE_STUNNEL,
    OVPN_REMOTE_HOST,
    OVPN_REMOTE_PORT,
    OPENVPN_DIR,
    SERVER_CONF,
    STATUS_LOG,
    STUNNEL_ACCEPT,
    STUNNEL_CONF,
    STUNNEL_DIR,
    STUNNEL_PEM,
    VPN_NETMASK,
    VPN_NETWORK,
)

# ICMP RTT from iputils ping (Ubuntu), e.g. "time=1.23 ms" or "time<0.1 ms"
_PING_MS = re.compile(r"time[<=]([\d.]+)\s*ms", re.IGNORECASE)


def ping_rtt_ms(ip: str) -> float | None:
    """Return ICMP round-trip time in milliseconds, or None if unreachable."""
    try:
        p = subprocess.run(
            ["ping", "-c", "1", "-W", "2", ip],
            capture_output=True,
            text=True,
            timeout=6,
        )
        out = (p.stdout or "") + (p.stderr or "")
        m = _PING_MS.search(out)
        if m:
            return float(m.group(1))
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    return None


def ping_rtt_batch(ips: list[str]) -> dict[str, float | None]:
    """Ping each IP in parallel (deduplicated order preserved for first occurrence)."""
    if not ips:
        return {}
    uniq = list(dict.fromkeys(ips))
    if len(uniq) == 1:
        u = uniq[0]
        return {u: ping_rtt_ms(u)}
    out: dict[str, float | None] = {}
    max_workers = min(16, len(uniq))
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        fut_to_ip = {pool.submit(ping_rtt_ms, ip): ip for ip in uniq}
        for fut in as_completed(fut_to_ip):
            ip = fut_to_ip[fut]
            try:
                out[ip] = fut.result()
            except Exception:
                out[ip] = None
    return out


def _env_base() -> dict[str, str]:
    e = os.environ.copy()
    e["EASYRSA_BATCH"] = "1"
    e["EASYRSA_PKI"] = str(EASYRSA_PKI)
    return e


def _run_easyrsa(*args: str, extra_env: dict[str, str] | None = None) -> str:
    env = _env_base()
    if extra_env:
        env.update(extra_env)
    cmd = [str(EASYRSA_BIN), *args]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip()
        raise RuntimeError(f"easyrsa {' '.join(args)} failed: {msg}")
    return (r.stdout or "").strip()


def _run(cmd: list[str], **kwargs: object) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=False)
    if r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed: {(r.stderr or r.stdout).strip()}")
    return (r.stdout or "").strip()


def ensure_dirs() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    OPENVPN_DIR.mkdir(parents=True, exist_ok=True)
    CCD_DIR.mkdir(parents=True, exist_ok=True)
    STUNNEL_DIR.mkdir(parents=True, exist_ok=True)
    EASYRSA_PKI.parent.mkdir(parents=True, exist_ok=True)
    ipp = OPENVPN_DIR / "ipp.txt"
    if not ipp.is_file():
        ipp.write_text("", encoding="utf-8")


def ensure_pki_and_server() -> None:
    """Idempotent: CA, server cert, DH, ta, server.conf, stunnel, CRL placeholder."""
    ensure_dirs()
    if not (EASYRSA_PKI / "ca.crt").is_file():
        _run_easyrsa("init-pki")
        _run_easyrsa("build-ca", "nopass", extra_env={"EASYRSA_REQ_CN": "OpenVPN-CA"})
    if not (EASYRSA_PKI / "issued" / "server.crt").is_file():
        _run_easyrsa("gen-req", "server", "nopass", extra_env={"EASYRSA_REQ_CN": "server"})
        _run_easyrsa("sign-req", "server", "server")
    if not (EASYRSA_PKI / "dh.pem").is_file():
        _run_easyrsa("gen-dh")
    ta = EASYRSA_PKI / "ta.key"
    if not ta.is_file():
        _run(
            [
                "/usr/sbin/openvpn",
                "--genkey",
                "secret",
                str(ta),
            ]
        )
        os.chmod(ta, 0o600)
    if not (EASYRSA_PKI / "crl.pem").is_file():
        # empty crl may not exist until first revoke — gen-crl after first CA
        _run_easyrsa("gen-crl")
    write_server_conf()
    write_stunnel_pem()
    write_stunnel_conf()


def write_server_conf() -> None:
    pki = EASYRSA_PKI
    lines = [
        "port 1194",
        "proto tcp-server",
        "dev tun",
        f"log-append {LOG_FILE_OPENVPN}",
        "user nobody",
        "group nogroup",
        "persist-key",
        "persist-tun",
        "keepalive 10 120",
        "topology subnet",
        "client-to-client",
        f"server {VPN_NETWORK} {VPN_NETMASK}",
        f"ca {pki / 'ca.crt'}",
        f"cert {pki / 'issued' / 'server.crt'}",
        f"key {pki / 'private' / 'server.key'}",
        f"dh {pki / 'dh.pem'}",
        f"tls-crypt {pki / 'ta.key'}",
        f"crl-verify {pki / 'crl.pem'}",
        f"client-config-dir {CCD_DIR}",
        f"ifconfig-pool-persist {OPENVPN_DIR / 'ipp.txt'}",
        f"status {STATUS_LOG} 10",
        "status-version 2",
        "verb 3",
    ]
    SERVER_CONF.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(SERVER_CONF, 0o644)


def write_stunnel_pem() -> None:
    """Single PEM: cert chain + private key for stunnel."""
    issued = EASYRSA_PKI / "issued" / "server.crt"
    key = EASYRSA_PKI / "private" / "server.key"
    ca = EASYRSA_PKI / "ca.crt"
    parts = [
        issued.read_text(encoding="utf-8"),
        key.read_text(encoding="utf-8"),
        ca.read_text(encoding="utf-8"),
    ]
    STUNNEL_PEM.write_text("\n".join(parts), encoding="utf-8")
    os.chmod(STUNNEL_PEM, 0o600)


def write_stunnel_conf() -> None:
    txt = f"""foreground = yes
setuid = root
setgid = root
output = {LOG_FILE_STUNNEL}
debug = notice

[openvpn]
accept = {STUNNEL_ACCEPT}
connect = 127.0.0.1:1194
cert = {STUNNEL_PEM}
"""
    STUNNEL_CONF.write_text(txt, encoding="utf-8")
    os.chmod(STUNNEL_CONF, 0o644)


def issue_client_cert(cert_cn: str) -> None:
    """Create and sign client certificate (name = cert_cn)."""
    _run_easyrsa("gen-req", cert_cn, "nopass", extra_env={"EASYRSA_REQ_CN": cert_cn})
    _run_easyrsa("sign-req", "client", cert_cn)


def revoke_client_cert(cert_cn: str) -> None:
    try:
        _run_easyrsa("revoke", cert_cn)
    except RuntimeError:
        # may already be revoked
        pass
    _run_easyrsa("gen-crl")


def write_ccd(cert_cn: str, vpn_ip: str) -> None:
    ccd = CCD_DIR / cert_cn
    ccd.write_text(f"ifconfig-push {vpn_ip} {VPN_NETMASK}\n", encoding="utf-8")
    os.chmod(ccd, 0o644)


def remove_ccd(cert_cn: str) -> None:
    p = CCD_DIR / cert_cn
    if p.is_file():
        p.unlink()


def build_inline_ovpn(cert_cn: str) -> str:
    pki = EASYRSA_PKI
    ca = (pki / "ca.crt").read_text(encoding="utf-8").strip()
    cert = (pki / "issued" / f"{cert_cn}.crt").read_text(encoding="utf-8").strip()
    key = (pki / "private" / f"{cert_cn}.key").read_text(encoding="utf-8").strip()
    tc = (pki / "ta.key").read_text(encoding="utf-8").strip()
    remote_host = OVPN_REMOTE_HOST
    remote_port = OVPN_REMOTE_PORT
    return f"""client
dev tun
proto tcp
remote {remote_host} {remote_port}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3
<ca>
{ca}
</ca>
<cert>
{cert}
</cert>
<key>
{key}
</key>
<tls-crypt>
{tc}
</tls-crypt>
"""


# ---- status.log parsing (OpenVPN status format v2) ----------------------------
# CLIENT_LIST,<CN>,<Real>,<Virt v4>,<Virt v6>,<Bytes Rcvd from client>,<Bytes Sent to client>,...


def parse_client_status() -> dict[str, dict[str, object]]:
    """Map cert CN -> traffic (client perspective: download = sent to client)."""
    if not STATUS_LOG.is_file():
        return {}
    out: dict[str, dict[str, object]] = {}
    try:
        text = STATUS_LOG.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("CLIENT_LIST,"):
            continue
        parts = line.split(",")
        if len(parts) < 7:
            continue
        cn = parts[1]
        virt = parts[3]
        try:
            from_client = int(parts[5])
            to_client = int(parts[6])
        except ValueError:
            continue
        out[cn] = {
            "virtual_ip": virt or "",
            "upload_bytes": from_client,
            "download_bytes": to_client,
        }
    return out


def human_bytes(n: int) -> str:
    if n < 1024:
        return f"{n} B"
    if n < 1024**2:
        return f"{n / 1024:.2f} KB"
    if n < 1024**3:
        return f"{n / 1024**2:.2f} MB"
    return f"{n / 1024**3:.2f} GB"


def reload_openvpn_crl() -> None:
    """Signal OpenVPN to reload CRL after revoke (best-effort)."""
    try:
        subprocess.run(
            [
                "systemctl",
                "kill",
                "--kill-who=main",
                "-s",
                "HUP",
                "openvpn-ovpn.service",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except OSError:
        pass
