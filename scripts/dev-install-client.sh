#!/usr/bin/env bash
# Rebuild rx-vpn-ubuntu .deb from client/ubuntu24/ and install it (development loop).
# Usage: from repo root: ./scripts/dev-install-client.sh
#        or: bash scripts/dev-install-client.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${ROOT}/client/ubuntu24"
OUT_DIR="${ROOT}/client"

if [[ ! -d "${PKG_DIR}/debian" ]]; then
  echo "error: missing ${PKG_DIR}/debian" >&2
  exit 1
fi

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
  echo "error: install build tools first:" >&2
  echo "  sudo apt-get update && sudo apt-get install -y dpkg-dev debhelper" >&2
  exit 1
fi

echo "==> dpkg-buildpackage -b (${PKG_DIR})"
(
  cd "${PKG_DIR}"
  dpkg-buildpackage -us -uc -b
)

shopt -s nullglob
debs=( "${OUT_DIR}"/rx-vpn-ubuntu_*_all.deb )
if [[ "${#debs[@]}" -eq 0 ]]; then
  echo "error: no rx-vpn-ubuntu_*_all.deb under ${OUT_DIR}/" >&2
  exit 1
fi
# Pick highest version if several .deb are present
DEB="$(printf '%s\n' "${debs[@]}" | sort -V | tail -n 1)"
echo "==> apt install ${DEB}"
sudo apt install -y "${DEB}"

echo "==> done: $(command -v rx-vpn-ubuntu)"
