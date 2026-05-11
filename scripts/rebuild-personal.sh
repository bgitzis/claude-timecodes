#!/usr/bin/env bash
# Rebuild the personal integration branch from upstream/main + a list of
# feature branches that haven't been merged upstream yet.
#
# Usage: scripts/rebuild-personal.sh
#
# When upstream merges one of your branches, delete it from BRANCHES below.
# When you start a new local-only branch you want carried into bgitzis/main,
# add it to BRANCHES.

set -euo pipefail

PERSONAL_BRANCH="bgitzis/main"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"

BRANCHES=(
  tools/rebuild-personal
  fix/viewer-full-message-text
  docs/from-source-install
  security/viewer-host-check
  docs/claude-md
)

current=$(git rev-parse --abbrev-ref HEAD)

git fetch "$UPSTREAM_REMOTE"

if git show-ref --verify --quiet "refs/heads/$PERSONAL_BRANCH"; then
  git checkout "$PERSONAL_BRANCH"
  git reset --hard "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
else
  git checkout -b "$PERSONAL_BRANCH" "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
fi

for b in "${BRANCHES[@]}"; do
  git merge --no-ff -m "Merge $b" "$b"
done

if [ "$current" != "$PERSONAL_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$current"; then
  git checkout "$current"
fi
