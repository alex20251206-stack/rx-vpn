#!/usr/bin/env bash
# Fetch built-in Android native deps into app assets.
# Expected output:
#   app/src/main/assets/native/arm64-v8a/openvpn
#   app/src/main/assets/native/arm64-v8a/stunnel
#
# You must provide URLs that point to executable arm64 binaries.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/app/src/main/assets/native/arm64-v8a"

OPENVPN_URL="${OPENVPN_URL:-}"
STUNNEL_URL="${STUNNEL_URL:-}"

if [[ -z "${OPENVPN_URL}" || -z "${STUNNEL_URL}" ]]; then
  echo "usage:" >&2
  echo "  OPENVPN_URL=<url> STUNNEL_URL=<url> bash client/android/scripts/fetch-native-deps.sh" >&2
  exit 1
fi

mkdir -p "${OUT}"
curl -fL -o "${OUT}/openvpn" "${OPENVPN_URL}"
curl -fL -o "${OUT}/stunnel" "${STUNNEL_URL}"
chmod 0755 "${OUT}/openvpn" "${OUT}/stunnel"

echo "fetched:"
ls -lh "${OUT}/openvpn" "${OUT}/stunnel"
