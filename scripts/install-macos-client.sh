#!/usr/bin/env bash
# Install RX VPN macOS client from GitHub Releases.
# - Installs Homebrew dependencies: openvpn, stunnel
# - Downloads rx-vpn-macos-<version>.tar.gz + .sha256
# - Verifies SHA256
# - Installs rx-vpn-macos into /usr/local/bin (default)

set -euo pipefail

REPO_SLUG="${REPO_SLUG:-alex20251206-stack/rx-vpn}"
VERSION=""
SUB_URL=""
INSTALL_DIR="/usr/local/bin"

usage() {
  cat <<'EOF'
Usage: install-macos-client.sh [options]

Options:
  --version <vX.Y.Z>     Release tag to install. Default: latest release tag.
  --sub-url <url>        Optional subscription URL; if set, run `sudo rx-vpn-macos set-url <url>`.
  --repo <owner/repo>    GitHub repo slug (default: alex20251206-stack/rx-vpn).
  --install-dir <dir>    Target bin dir (default: /usr/local/bin).
  -h, --help             Show this help.

Examples:
  bash install-macos-client.sh --version v0.1.3
  bash install-macos-client.sh --sub-url 'http://<host>:8139/api/sub/<sub-code>'
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: missing command: ${cmd}" >&2
    exit 1
  fi
}

resolve_latest_tag() {
  local effective
  effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO_SLUG}/releases/latest")"
  VERSION="${effective##*/}"
  if [[ -z "${VERSION}" || "${VERSION}" != v* ]]; then
    echo "error: could not resolve latest release tag from ${effective}" >&2
    exit 1
  fi
}

install_brew_dep() {
  local pkg="$1"
  if brew list --versions "${pkg}" >/dev/null 2>&1; then
    echo "==> dependency already installed: ${pkg}"
    return
  fi
  echo "==> installing dependency: ${pkg}"
  brew install "${pkg}"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="${2:-}"; shift 2 ;;
      --sub-url) SUB_URL="${2:-}"; shift 2 ;;
      --repo) REPO_SLUG="${2:-}"; shift 2 ;;
      --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  require_cmd curl
  require_cmd tar
  require_cmd shasum

  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required. Install from https://brew.sh first." >&2
    exit 1
  fi

  if [[ -z "${VERSION}" ]]; then
    resolve_latest_tag
  fi
  if [[ "${VERSION}" != v* ]]; then
    echo "error: version must look like vX.Y.Z (got: ${VERSION})" >&2
    exit 1
  fi

  local ver="${VERSION#v}"
  local base="https://github.com/${REPO_SLUG}/releases/download/${VERSION}"
  local tar_name="rx-vpn-macos-${ver}.tar.gz"
  local sha_name="rx-vpn-macos-${ver}.sha256"
  local tar_url="${base}/${tar_name}"
  local sha_url="${base}/${sha_name}"

  echo "==> target release: ${VERSION}"
  install_brew_dep openvpn
  install_brew_dep stunnel

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  echo "==> downloading ${tar_name}"
  curl -fL -o "${tmp_dir}/${tar_name}" "${tar_url}"
  echo "==> downloading ${sha_name}"
  curl -fL -o "${tmp_dir}/${sha_name}" "${sha_url}"

  echo "==> verifying SHA256"
  (
    cd "${tmp_dir}"
    shasum -a 256 -c "${sha_name}"
  )

  echo "==> extracting package"
  tar -xzf "${tmp_dir}/${tar_name}" -C "${tmp_dir}"
  if [[ ! -f "${tmp_dir}/rx-vpn-macos" ]]; then
    echo "error: extracted file rx-vpn-macos not found" >&2
    exit 1
  fi

  echo "==> installing binary to ${INSTALL_DIR}"
  sudo mkdir -p "${INSTALL_DIR}"
  sudo install -m 0755 "${tmp_dir}/rx-vpn-macos" "${INSTALL_DIR}/rx-vpn-macos"

  if [[ -d "/opt/homebrew/bin" && "${INSTALL_DIR}" != "/opt/homebrew/bin" ]]; then
    sudo ln -sf "${INSTALL_DIR}/rx-vpn-macos" "/opt/homebrew/bin/rx-vpn-macos"
  fi

  echo "==> installed: $(${INSTALL_DIR}/rx-vpn-macos --help | awk 'NR==1{print $0}')"

  if [[ -n "${SUB_URL}" ]]; then
    echo "==> configuring subscription URL"
    sudo "${INSTALL_DIR}/rx-vpn-macos" set-url "${SUB_URL}"
  else
    echo "==> next step:"
    echo "   sudo rx-vpn-macos set-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'"
  fi
}

main "$@"
