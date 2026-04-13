#!/usr/bin/env bash
# Build release assets for macOS client:
#   - client/rx-vpn-macos-<version>.tar.gz
#   - client/rx-vpn-macos-<version>.sha256

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag-or-version>" >&2
  echo "example: $0 v0.1.2" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/client"
SRC="${ROOT}/client/macos/rx-vpn-macos"
VER="${1#v}"
TARBALL="rx-vpn-macos-${VER}.tar.gz"
TARBALL_PATH="${OUT_DIR}/${TARBALL}"
SHA_PATH="${OUT_DIR}/rx-vpn-macos-${VER}.sha256"

if [[ ! -f "${SRC}" ]]; then
  echo "error: missing ${SRC}" >&2
  exit 1
fi
mkdir -p "${OUT_DIR}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${SRC}" "${tmp_dir}/rx-vpn-macos"
chmod 0755 "${tmp_dir}/rx-vpn-macos"
(cd "${tmp_dir}" && tar -czf "${TARBALL_PATH}" rx-vpn-macos)

SHA="$(shasum -a 256 "${TARBALL_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "${TARBALL}" > "${SHA_PATH}"

echo "Built:"
echo "  ${TARBALL_PATH}"
echo "  ${SHA_PATH}"
