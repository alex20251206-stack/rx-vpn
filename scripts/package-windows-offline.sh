#!/usr/bin/env bash
# Build offline Windows installer bundle for GitHub Release:
#   - client/rx-vpn-windows-offline-<version>.zip
#   - client/rx-vpn-windows-offline-<version>.sha256
#
# Bundle contains:
#   scripts/install-windows-client.ps1
#   client/windows/rx-vpn-windows.ps1
#   third_party/windows/*

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag-or-version>" >&2
  echo "example: $0 v0.1.3" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/client"
VER="${1#v}"
ZIP_NAME="rx-vpn-windows-offline-${VER}.zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
SHA_PATH="${OUT_DIR}/rx-vpn-windows-offline-${VER}.sha256"

mkdir -p "${OUT_DIR}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

bundle_root="${tmp_dir}/rx-vpn-windows-offline-${VER}"
mkdir -p "${bundle_root}/scripts" "${bundle_root}/client/windows" "${bundle_root}/third_party/windows"

cp "${ROOT}/scripts/install-windows-client.ps1" "${bundle_root}/scripts/"
cp "${ROOT}/client/windows/rx-vpn-windows.ps1" "${bundle_root}/client/windows/"
cp "${ROOT}/third_party/windows/"* "${bundle_root}/third_party/windows/"

python3 - <<PY
import os, zipfile
bundle_root = r"${bundle_root}"
zip_path = r"${ZIP_PATH}"
base = os.path.dirname(bundle_root)
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(bundle_root):
        for f in files:
            p = os.path.join(root, f)
            arc = os.path.relpath(p, base)
            zf.write(p, arc)
PY

SHA="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf '%s  %s\n' "${SHA}" "${ZIP_NAME}" > "${SHA_PATH}"

echo "Built:"
echo "  ${ZIP_PATH}"
echo "  ${SHA_PATH}"
