#!/usr/bin/env bash
# CI: set the first debian/changelog stanza from git tag so the .deb matches (e.g. v0.1.3 → 0.1.3-1).
# Tags: v1.2.3 or rx-v1.2.3 → upstream 1.2.3, Debian revision -1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CL="${ROOT}/client/ubuntu24/debian/changelog"
TAG="${1:-${GITHUB_REF_NAME:-}}"

if [[ -z "${TAG}" ]]; then
  echo "usage: $0 <tag>   (e.g. v0.1.3 or rx-v0.1.3)" >&2
  exit 1
fi

VER="${TAG}"
if [[ "${VER}" == rx-v* ]]; then
  VER="${VER#rx-v}"
elif [[ "${VER}" == v* ]]; then
  VER="${VER#v}"
fi

if [[ ! "${VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: tag must look like v1.2.3 or rx-v1.2.3 (got: ${TAG} → ${VER})" >&2
  exit 1
fi

if [[ ! -f "${CL}" ]]; then
  echo "error: missing ${CL}" >&2
  exit 1
fi

DEB_VER="${VER}-1"
DATE="$(date -R)"

# Line where the second changelog entry starts (keep older history below).
second_line="$(awk '/^rx-vpn-ubuntu \(/{c++} c==2{print NR; exit}' "${CL}")"

tmp="$(mktemp)"
{
  echo "rx-vpn-ubuntu (${DEB_VER}) unstable; urgency=medium"
  echo ""
  echo "  * Release ${TAG}."
  echo ""
  echo " -- github-actions <github-actions@users.noreply.github.com>  ${DATE}"
  echo ""
  if [[ -n "${second_line:-}" ]]; then
    tail -n "+${second_line}" "${CL}"
  fi
} > "${tmp}"
mv "${tmp}" "${CL}"

echo "deb changelog: first stanza set to ${DEB_VER} (from tag ${TAG})"
