"""OpenVPN control panel (port 8139)."""
from __future__ import annotations

import json
import re
import uuid
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import HTMLResponse, PlainTextResponse
from pydantic import BaseModel, Field

from app.config import PANEL_TOKEN_FILE, subscription_public_origin
from app.pki import (
    build_inline_ovpn,
    ensure_pki_and_server,
    human_bytes,
    issue_client_cert,
    parse_client_status,
    ping_rtt_batch,
    ping_rtt_ms,
    reload_openvpn_crl,
    remove_ccd,
    revoke_client_cert,
    write_ccd,
)
from app.state import ClientRecord, ClientState


def _app_version() -> str:
    """Single source: repository root VERSION (also copied into the container)."""
    root = Path(__file__).resolve().parent.parent
    try:
        return (root / "VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        return "0.1.0"


def _read_panel_token() -> str | None:
    if not PANEL_TOKEN_FILE.is_file():
        return None
    return PANEL_TOKEN_FILE.read_text(encoding="utf-8").strip() or None


async def require_panel_token(x_panel_token: str | None = Header(None)) -> None:
    expected = _read_panel_token()
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Panel token file missing; check /data/panel.token",
        )
    if not x_panel_token or x_panel_token != expected:
        raise HTTPException(
            status_code=401,
            detail="Invalid or missing X-Panel-Token header",
        )


state_store = ClientState()

SUB_CODE_RE = re.compile(r"^[a-z0-9]{6}$")


def fresh_cert_cn(client_id: str) -> str:
    return f"c_{client_id.replace('-', '')}_{uuid.uuid4().hex[:8]}"


@asynccontextmanager
async def lifespan(app: FastAPI):
    ensure_pki_and_server()
    yield


app = FastAPI(
    title="Ruoxue VPN Panel",
    version=_app_version(),
    lifespan=lifespan,
    docs_url=None,
    redoc_url=None,
)


class ClientCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=128)


class ClientPatch(BaseModel):
    enabled: bool


class ClientOut(BaseModel):
    id: str
    num: int
    sub_code: str
    name: str
    cert_cn: str
    vpn_ip: str
    enabled: bool
    connected: bool
    latency_ms: float | None = None
    download_total: str
    upload_total: str
    last_seen: str


def _enrich(
    rec: ClientRecord,
    status: dict[str, dict[str, object]] | None = None,
    lat_by_ip: dict[str, float | None] | None = None,
) -> ClientOut:
    if status is None:
        status = parse_client_status()
    connected = rec.cert_cn in status
    # Persistent totals (updated in list_clients via apply_traffic_from_status).
    down = rec.traffic_acc_down
    up = rec.traffic_acc_up
    latency: float | None = None
    if connected:
        if lat_by_ip is not None:
            latency = lat_by_ip.get(rec.vpn_ip)
        else:
            latency = ping_rtt_ms(rec.vpn_ip)
    if not connected:
        seen = "—"
    elif latency is None:
        seen = "—"
    else:
        seen = f"{latency:.1f} ms"
    return ClientOut(
        id=rec.id,
        num=rec.num,
        sub_code=rec.sub_code,
        name=rec.name,
        cert_cn=rec.cert_cn,
        vpn_ip=rec.vpn_ip,
        enabled=rec.enabled,
        connected=connected,
        latency_ms=latency,
        download_total=human_bytes(down),
        upload_total=human_bytes(up),
        last_seen=seen,
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/clients", response_model=list[ClientOut])
def list_clients(_: None = Depends(require_panel_token)) -> list[ClientOut]:
    status = parse_client_status()
    clients = sorted(
        state_store.apply_traffic_from_status(status),
        key=lambda c: c.num,
    )
    online_ips = [c.vpn_ip for c in clients if c.cert_cn in status]
    lat_by_ip = ping_rtt_batch(online_ips) if online_ips else {}
    return [_enrich(c, status, lat_by_ip) for c in clients]


@app.post("/api/clients", response_model=ClientOut)
def create_client(
    body: ClientCreate,
    _: None = Depends(require_panel_token),
) -> ClientOut:
    rec = state_store.add_client(body.name)
    try:
        issue_client_cert(rec.cert_cn)
        write_ccd(rec.cert_cn, rec.vpn_ip)
    except Exception:
        state_store.remove(rec.id)
        raise
    return _enrich(state_store.get(rec.id) or rec, parse_client_status())


@app.patch("/api/clients/{client_id}", response_model=ClientOut)
def patch_client(
    client_id: str,
    body: ClientPatch,
    _: None = Depends(require_panel_token),
) -> ClientOut:
    rec = state_store.get(client_id)
    if not rec:
        raise HTTPException(404, detail="Client not found")

    stmap = parse_client_status()

    if body.enabled == rec.enabled:
        return _enrich(rec, stmap)

    if not body.enabled:
        try:
            revoke_client_cert(rec.cert_cn)
        except Exception:
            pass
        remove_ccd(rec.cert_cn)
        reload_openvpn_crl()
        updated = state_store.update(client_id, enabled=False)
        return _enrich(updated or rec, parse_client_status())

    # enabling: issue fresh cert (previous may be revoked)
    new_cn = fresh_cert_cn(rec.id)
    try:
        issue_client_cert(new_cn)
        write_ccd(new_cn, rec.vpn_ip)
    except Exception:
        raise
    updated = state_store.update(client_id, enabled=True, cert_cn=new_cn)
    return _enrich(updated or rec, parse_client_status())


@app.delete("/api/clients/{client_id}")
def delete_client(
    client_id: str,
    _: None = Depends(require_panel_token),
) -> dict[str, str]:
    rec = state_store.remove(client_id)
    if not rec:
        raise HTTPException(404, detail="Client not found")
    try:
        revoke_client_cert(rec.cert_cn)
    except Exception:
        pass
    remove_ccd(rec.cert_cn)
    reload_openvpn_crl()
    return {"status": "deleted"}


def _subscription_response(rec: ClientRecord) -> PlainTextResponse:
    if not rec.enabled:
        raise HTTPException(403, detail="Client disabled")
    try:
        ovpn = build_inline_ovpn(rec.cert_cn)
    except OSError:
        raise HTTPException(500, detail="Cannot read certificate material")
    return PlainTextResponse(ovpn, media_type="text/plain; charset=utf-8")


@app.get("/api/sub/{sub_code}")
def subscription_by_code(sub_code: str) -> PlainTextResponse:
    code = sub_code.strip().lower()
    if not SUB_CODE_RE.match(code):
        raise HTTPException(404, detail="Invalid subscription code")
    rec = state_store.get_by_sub_code(code)
    if not rec:
        raise HTTPException(404, detail="Client not found")
    return _subscription_response(rec)


@app.get("/api/subscription/{client_id}")
def subscription(client_id: str) -> PlainTextResponse:
    """Legacy: full UUID client id in path. Prefer /api/sub/{6-char}."""
    rec = state_store.get(client_id)
    if not rec:
        raise HTTPException(404, detail="Client not found")
    return _subscription_response(rec)


@app.get("/", response_class=HTMLResponse)
def dashboard() -> HTMLResponse:
    html = DASHBOARD_HTML.replace(
        "__SUBSCRIPTION_ORIGIN_JSON__",
        json.dumps(subscription_public_origin()),
    )
    return HTMLResponse(html)


DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Ruoxue VPN Panel</title>
  <style>
    :root {
      --bg: #121214;
      --surface: #1a1a1f;
      --border: #2d2d35;
      --text: #f4f4f5;
      --muted: #a1a1aa;
      --accent: #dc2626;
      --accent-dim: #991b1b;
      --ok: #22c55e;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 1rem 1.5rem;
      border-bottom: 1px solid var(--border);
      background: var(--surface);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      font-weight: 700;
      font-size: 1.15rem;
      letter-spacing: -0.02em;
      flex-shrink: 0;
      white-space: nowrap;
    }
    .brand svg { width: 28px; height: 28px; }
    .token-row {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      flex-wrap: wrap;
    }
    .token-row label { color: var(--muted); font-size: 0.85rem; }
    input[type="password"], input[type="text"] {
      background: var(--bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 0.45rem 0.65rem;
      border-radius: 6px;
      min-width: 220px;
      font-size: 0.9rem;
    }
    button.btn {
      background: #3f3f46;
      border: 1px solid var(--border);
      color: var(--text);
      padding: 0.45rem 0.85rem;
      border-radius: 6px;
      cursor: pointer;
      font-size: 0.85rem;
    }
    button.btn:hover { filter: brightness(1.1); }
    button.btn-primary {
      background: var(--accent);
      border-color: var(--accent-dim);
    }
    main { padding: 1.25rem 1.5rem 3rem; max-width: 1200px; margin: 0 auto; }
    .section-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 1rem;
    }
    h1 { font-size: 1.5rem; font-weight: 600; margin: 0; }
    .list {
      border: 1px solid var(--border);
      border-radius: 10px;
      overflow: hidden;
      background: var(--surface);
    }
    .row {
      display: grid;
      grid-template-columns: minmax(140px, 1.2fr) 100px 1fr 1fr 200px;
      gap: 0.75rem;
      align-items: center;
      padding: 0.85rem 1rem;
      border-bottom: 1px solid var(--border);
      font-size: 0.88rem;
    }
    .row:last-child { border-bottom: none; }
    .row.head {
      background: #18181c;
      color: var(--muted);
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .mono { font-family: ui-monospace, monospace; font-size: 0.82rem; color: var(--muted); }
    .status-line {
      display: flex;
      align-items: center;
      gap: 0.4rem;
      margin-top: 0.15rem;
    }
    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      flex-shrink: 0;
    }
    .name { font-weight: 600; }
    .traffic { color: var(--muted); font-size: 0.8rem; }
    .actions { display: flex; gap: 0.35rem; flex-wrap: wrap; justify-content: flex-end; }
    .icon-btn {
      width: 34px; height: 34px;
      display: inline-flex; align-items: center; justify-content: center;
      border-radius: 6px;
      border: 1px solid var(--border);
      background: #27272a;
      cursor: pointer;
      color: var(--text);
      padding: 0;
    }
    .icon-btn:hover { background: #3f3f46; }
    .icon-btn.danger { color: #f87171; border-color: #7f1d1d; }
    .switch {
      position: relative;
      width: 44px;
      height: 24px;
      border-radius: 999px;
      background: var(--accent);
      cursor: pointer;
      flex-shrink: 0;
      border: none;
      padding: 0;
    }
    .switch.off { background: #3f3f46; }
    .knob {
      position: absolute;
      top: 3px;
      left: 3px;
      width: 18px;
      height: 18px;
      background: #fff;
      border-radius: 50%;
      transition: transform 0.15s;
    }
    .switch.off .knob { transform: translateX(0); }
    .switch:not(.off) .knob { transform: translateX(20px); }
    .err {
      color: #f87171;
      font-size: 0.85rem;
      margin-top: 0.75rem;
    }
    dialog {
      border: 1px solid var(--border);
      border-radius: 10px;
      background: var(--surface);
      color: var(--text);
      padding: 1.25rem;
      min-width: 320px;
    }
    dialog::backdrop { background: rgba(0,0,0,0.65); }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path d="M12 2L4 6v6c0 5 3.5 9.5 8 11 4.5-1.5 8-6 8-11V6l-8-4z" stroke="currentColor" stroke-width="1.6" fill="none"/>
        <path d="M12 8v5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
        <circle cx="12" cy="16" r="1.2" fill="currentColor"/>
      </svg>
      Ruoxue VPN
    </div>
    <div class="token-row">
      <label for="tok">Panel token</label>
      <input id="tok" type="password" autocomplete="off" placeholder="Paste value from /data/panel.token"/>
      <button type="button" class="btn" id="saveTok">Save in browser</button>
    </div>
  </header>
  <main>
    <div class="section-head">
      <h1>Clients</h1>
      <button type="button" class="btn btn-primary" id="btnNew">+ New client</button>
    </div>
    <p class="mono" id="hint">Header <code>X-Panel-Token</code> must match <code>/data/panel.token</code>. Save the token above first.</p>
    <div id="err" class="err" style="display:none"></div>
    <div class="list">
      <div class="row head">
        <div>Client</div>
        <div>Address</div>
        <div>Download</div>
        <div>Upload</div>
        <div style="text-align:right">Actions</div>
      </div>
      <div id="rows"></div>
    </div>
  </main>
  <dialog id="dlg">
    <form method="dialog" id="formNew">
      <p style="margin-top:0">New client</p>
      <input type="text" id="newName" placeholder="Display name" required style="width:100%"/>
      <div style="margin-top:1rem;display:flex;gap:0.5rem;justify-content:flex-end">
        <button type="button" class="btn" id="dlgCancel">Cancel</button>
        <button type="submit" class="btn btn-primary">Create</button>
      </div>
    </form>
  </dialog>
  <script>
    const SUBSCRIPTION_ORIGIN = __SUBSCRIPTION_ORIGIN_JSON__;
    const LS = 'rx_ruoxue_token';
    const tokInput = document.getElementById('tok');
    const saveTok = document.getElementById('saveTok');
    const rowsEl = document.getElementById('rows');
    const errEl = document.getElementById('err');
    const dlg = document.getElementById('dlg');
    const btnNew = document.getElementById('btnNew');
    const formNew = document.getElementById('formNew');
    const newName = document.getElementById('newName');
    const dlgCancel = document.getElementById('dlgCancel');

    function hdr() {
      const t = localStorage.getItem(LS) || '';
      return { 'X-Panel-Token': t, 'Content-Type': 'application/json' };
    }
    function showErr(m) {
      errEl.style.display = m ? 'block' : 'none';
      errEl.textContent = m || '';
    }
    saveTok.onclick = () => {
      localStorage.setItem(LS, tokInput.value.trim());
      showErr('');
      load();
    };
    tokInput.value = localStorage.getItem(LS) || '';

    async function load() {
      showErr('');
      const t = localStorage.getItem(LS);
      if (!t) { rowsEl.innerHTML = '<div class="row"><div class="mono">Save the token above first.</div></div>'; return; }
      const r = await fetch('/api/clients', { headers: hdr() });
      if (!r.ok) { showErr(await r.text()); rowsEl.innerHTML = ''; return; }
      const data = await r.json();
      if (!data.length) {
        rowsEl.innerHTML = '<div class="row"><div class="mono" style="grid-column:1/-1">No clients yet. Click &quot;New client&quot;.</div></div>';
        return;
      }
      rowsEl.innerHTML = data.map(c => rowHtml(c)).join('');
      data.forEach(bindRow);
    }
    function statusDotStyle(c) {
      if (!c.connected) return 'background:#71717a';
      const ms = c.latency_ms;
      if (ms == null || ms === '') return 'background:#22c55e';
      const n = Number(ms);
      if (Number.isNaN(n)) return 'background:#22c55e';
      const x = Math.min(1, Math.max(0, n / 280));
      const hue = Math.round(120 * (1 - x));
      return 'background:hsl(' + hue + ' 70% 43%)';
    }
    function rowHtml(c) {
      const sw = c.enabled ? '' : ' off';
      const dot = statusDotStyle(c);
      return `<div class="row" data-id="${c.id}">
        <div><div class="name"><span class="mono">#${c.num}</span> ${escapeHtml(c.name)}</div><div class="status-line mono"><span class="status-dot" style="${dot}"></span>${escapeHtml(c.last_seen)}</div></div>
        <div class="mono">${escapeHtml(c.vpn_ip)}</div>
        <div class="traffic">${escapeHtml(c.download_total)}</div>
        <div class="traffic">${escapeHtml(c.upload_total)}</div>
        <div class="actions">
          <button type="button" class="switch${sw}" data-act="toggle" title="Enable / disable"><span class="knob"></span></button>
          <button type="button" class="icon-btn" data-act="sub" title="Copy subscription URL">🔗</button>
          <button type="button" class="icon-btn danger" data-act="del" title="Delete">🗑</button>
        </div>
      </div>`;
    }
    function escapeHtml(s) {
      const d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }
    function bindRow(c) {
      const row = rowsEl.querySelector('[data-id="'+c.id+'"]');
      if (!row) return;
      row.querySelector('[data-act=toggle]').onclick = async () => {
        const r = await fetch('/api/clients/'+c.id, { method:'PATCH', headers: hdr(), body: JSON.stringify({ enabled: !c.enabled }) });
        if (!r.ok) showErr(await r.text()); else load();
      };
      row.querySelector('[data-act=sub]').onclick = async () => {
        const u = SUBSCRIPTION_ORIGIN + '/api/sub/' + c.sub_code;
        try {
          await navigator.clipboard.writeText(u);
          alert('Subscription URL copied.');
        } catch(e) {
          prompt('Copy this URL', u);
        }
      };
      row.querySelector('[data-act=del]').onclick = async () => {
        if (!confirm('Delete this client?')) return;
        const r = await fetch('/api/clients/'+c.id, { method:'DELETE', headers: hdr() });
        if (!r.ok) showErr(await r.text()); else load();
      };
    }
    btnNew.onclick = () => { newName.value = ''; dlg.showModal(); };
    dlgCancel.onclick = () => dlg.close();
    formNew.onsubmit = async (e) => {
      e.preventDefault();
      const r = await fetch('/api/clients', { method:'POST', headers: hdr(), body: JSON.stringify({ name: newName.value }) });
      dlg.close();
      if (!r.ok) showErr(await r.text()); else load();
    };

    let pollBusy = false;
    setInterval(() => {
      if (!localStorage.getItem(LS)) return;
      if (pollBusy) return;
      pollBusy = true;
      Promise.resolve(load()).finally(() => { pollBusy = false; });
    }, 2000);

    load();
  </script>
</body>
</html>
"""
