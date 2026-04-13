#!/usr/bin/env bash
# Set README example versions to the newest local semver tag matching vX.Y.Z.
# No-op if there are no such tags. Run manually or from git pre-push.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

latest_tag=""
if git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  latest_tag="$(
    git -C "${ROOT}" for-each-ref --sort=-version:refname --format '%(refname:short)' 'refs/tags/v*' 2>/dev/null \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
  )"
fi

if [[ -z "${latest_tag}" ]]; then
  echo "sync-readme-version-from-latest-tag: no vMAJOR.MINOR.PATCH tags; leaving README unchanged" >&2
  exit 0
fi

ver="${latest_tag#v}"
exec bash "${SCRIPT_DIR}/sync-readme-version.sh" "${ver}"
