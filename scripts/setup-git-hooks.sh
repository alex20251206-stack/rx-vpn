#!/bin/bash
# Run once per clone: use version-bumping hooks from scripts/git-hooks/
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath scripts/git-hooks
echo "core.hooksPath=scripts/git-hooks (patch bump on each commit; SKIP_VERSION_BUMP=1 to skip)"
