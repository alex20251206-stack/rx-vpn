"""Persistent client list with file locking."""
from __future__ import annotations

import fcntl
import json
import secrets
import string
import uuid
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterator

from app.config import CLIENTS_FILE, VPN_POOL_START

_SUB_ALPHABET = string.ascii_lowercase + string.digits


def _random_sub_code() -> str:
    return "".join(secrets.choice(_SUB_ALPHABET) for _ in range(6))


@dataclass
class ClientRecord:
    id: str
    name: str
    cert_cn: str
    vpn_ip: str
    enabled: bool = True
    num: int = 0
    sub_code: str = ""

    def to_json(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_json(d: dict[str, Any]) -> ClientRecord:
        return ClientRecord(
            id=d["id"],
            name=d["name"],
            cert_cn=d["cert_cn"],
            vpn_ip=d["vpn_ip"],
            enabled=d.get("enabled", True),
            num=int(d["num"]) if d.get("num") is not None else 0,
            sub_code=str(d.get("sub_code") or ""),
        )


class ClientState:
    def __init__(self, path: Path = CLIENTS_FILE) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def locked(self) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "a+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                yield
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def _read_unlocked(self) -> tuple[list[ClientRecord], int]:
        if not self.path.is_file():
            return [], VPN_POOL_START
        raw = self.path.read_text(encoding="utf-8").strip()
        if not raw:
            return [], VPN_POOL_START
        data = json.loads(raw)
        clients = [ClientRecord.from_json(c) for c in data.get("clients", [])]
        next_seq = int(data.get("next_seq", VPN_POOL_START))
        return clients, next_seq

    def _read_migrated_unlocked(self) -> tuple[list[ClientRecord], int]:
        """Load clients and persist num/sub_code backfill if needed."""
        clients, next_seq = self._read_unlocked()
        if self._migrate_short_codes(clients):
            self.write(clients, next_seq)
        return clients, next_seq

    def read(self) -> tuple[list[ClientRecord], int]:
        with self.locked():
            return self._read_migrated_unlocked()

    def write(self, clients: list[ClientRecord], next_seq: int) -> None:
        payload = {
            "clients": [c.to_json() for c in clients],
            "next_seq": next_seq,
        }
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(self.path)

    def _migrate_short_codes(self, clients: list[ClientRecord]) -> bool:
        """Assign num and sub_code to legacy rows; return True if mutated."""
        changed = False
        used_codes = {c.sub_code for c in clients if c.sub_code}
        max_num = max((c.num for c in clients if c.num > 0), default=0)
        for c in clients:
            if not c.sub_code:
                while True:
                    code = _random_sub_code()
                    if code not in used_codes:
                        c.sub_code = code
                        used_codes.add(code)
                        changed = True
                        break
            if c.num <= 0:
                max_num += 1
                c.num = max_num
                changed = True
        return changed

    def add_client(self, name: str) -> ClientRecord:
        cid = str(uuid.uuid4())
        cert_cn = f"c_{cid.replace('-', '')}"
        with self.locked():
            clients, next_seq = self._read_migrated_unlocked()
            octet = next_seq
            if octet > 254:
                raise ValueError("VPN address pool exhausted")
            vpn_ip = f"10.8.0.{octet}"
            max_num = max((c.num for c in clients if c.num > 0), default=0)
            used_codes = {c.sub_code for c in clients if c.sub_code}
            while True:
                sc = _random_sub_code()
                if sc not in used_codes:
                    break
            rec = ClientRecord(
                id=cid,
                name=name.strip() or "client",
                cert_cn=cert_cn,
                vpn_ip=vpn_ip,
                enabled=True,
                num=max_num + 1,
                sub_code=sc,
            )
            clients.append(rec)
            self.write(clients, next_seq + 1)
            return rec

    def update(self, client_id: str, **kwargs: Any) -> ClientRecord | None:
        with self.locked():
            clients, next_seq = self._read_migrated_unlocked()
            for i, c in enumerate(clients):
                if c.id == client_id:
                    d = c.to_json()
                    for k, v in kwargs.items():
                        if k in d:
                            d[k] = v
                    clients[i] = ClientRecord.from_json(d)
                    self.write(clients, next_seq)
                    return clients[i]
            return None

    def remove(self, client_id: str) -> ClientRecord | None:
        with self.locked():
            clients, next_seq = self._read_migrated_unlocked()
            for i, c in enumerate(clients):
                if c.id == client_id:
                    removed = clients.pop(i)
                    self.write(clients, next_seq)
                    return removed
            return None

    def get(self, client_id: str) -> ClientRecord | None:
        clients, _ = self.read()
        for c in clients:
            if c.id == client_id:
                return c
        return None

    def get_by_sub_code(self, sub_code: str) -> ClientRecord | None:
        sub_code = sub_code.strip().lower()
        clients, _ = self.read()
        for c in clients:
            if c.sub_code == sub_code:
                return c
        return None
