#!/usr/bin/env bash
# Build release assets for macOS client:
#   - client/rx-vpn-macos-<version>.tar.gz
#   - client/rx-vpn-macos-<version>.sha256
#   - client/rx-vpn-macos.rb (formula with pinned url/sha)

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
FORMULA_PATH="${OUT_DIR}/rx-vpn-macos.rb"
REPO_SLUG="$(git -C "${ROOT}" config --get remote.origin.url | sed -E 's#^.*github.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"

if [[ ! -f "${SRC}" ]]; then
  echo "error: missing ${SRC}" >&2
  exit 1
fi
if [[ -z "${REPO_SLUG}" ]]; then
  echo "error: cannot infer GitHub repo slug from origin URL" >&2
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

cat > "${FORMULA_PATH}" <<EOF
class RxVpnMacos < Formula
  desc "RX VPN CLI client for macOS (OpenVPN + stunnel + launchd)"
  homepage "https://github.com/${REPO_SLUG}"
  url "https://github.com/${REPO_SLUG}/releases/download/v${VER}/${TARBALL}"
  sha256 "${SHA}"
  license "MIT"

  depends_on "openvpn"
  depends_on "stunnel"

  def install
    bin.install "rx-vpn-macos"
  end

  test do
    assert_match "Usage: rx-vpn-macos", shell_output("#{bin}/rx-vpn-macos --help")
  end
end
EOF

echo "Built:"
echo "  ${TARBALL_PATH}"
echo "  ${SHA_PATH}"
echo "  ${FORMULA_PATH}"
