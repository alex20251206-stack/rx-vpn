#!/usr/bin/env bash
# Replace concrete semver examples in README.md with the given X.Y.Z (no "v" prefix).
# Usually invoked via scripts/sync-readme-version-from-latest-tag.sh (git pre-push).
# Manual: bash scripts/sync-readme-version.sh 0.2.7
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <X.Y.Z>" >&2
  exit 1
fi

NEW_VER="$1"
if [[ ! "${NEW_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH (got: ${NEW_VER})" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
README="${ROOT}/README.md"
if [[ ! -f "${README}" ]]; then
  echo "error: missing ${README}" >&2
  exit 1
fi

export RV="${NEW_VER}"
perl -pi -e '
  my $v = $ENV{RV};
  s/(bash -s -- --version v)\d+\.\d+\.\d+/${1}$v/g;
  s/rx-vpn-android-X\.Y\.Z/rx-vpn-android-$v/g;
  s/rx-vpn-windows-offline-X\.Y\.Z/rx-vpn-windows-offline-$v/g;
  s/rx-vpn-windows-offline-\d+\.\d+\.\d+/rx-vpn-windows-offline-$v/g;
' "${README}"

echo "README.md: synced example versions to ${NEW_VER}"
