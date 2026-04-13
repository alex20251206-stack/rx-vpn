#!/bin/bash
# Run once per clone: use version-bumping hooks from scripts/git-hooks/
# Without this, Git uses .git/hooks/ only — our pre-commit (VERSION patch bump) never runs.
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x scripts/git-hooks/* 2>/dev/null || true
git config core.hooksPath scripts/git-hooks
echo "Set core.hooksPath=scripts/git-hooks"
echo "  • Each commit bumps the patch in VERSION (e.g. 0.1.0 -> 0.1.1)."
echo "  • Skip once: SKIP_VERSION_BUMP=1 git commit ..."
echo "  • Each push: README example versions sync to latest local vX.Y.Z tag (pre-push); if README"
echo "    changes, a commit is created and the push is aborted — run git push again."
echo "  • Skip README sync: SKIP_README_SYNC=1 git push ..."
echo "Check: git config --get core.hooksPath"
