#!/usr/bin/env bash
# Run from the VPS Worker checkout. Local changes are kept in a named Git stash.
set -euo pipefail
cd "${1:-/var/www/RobloxWorker/RobloxWorker}"
[[ "$(git branch --show-current)" == main ]] || { echo 'Expected main branch; no update performed.' >&2; exit 1; }
git fetch origin main
saved=''
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  git stash push -m "worker-before-update-$(date -u +%Y%m%dT%H%M%SZ)"
  saved=$(git rev-parse refs/stash)
  printf 'Local changes saved as %s (retained after update).\n' "$saved"
fi
if ! git merge --ff-only origin/main; then
  printf 'Update stopped. Saved local changes: %s\n' "${saved:-none}" >&2
  exit 1
fi
if [[ -n "$saved" ]] && ! git stash apply "$saved"; then
  printf 'Local changes conflict with the update. Nothing deployed. Resolve these files before deploying:\n' >&2
  git diff --name-only --diff-filter=U
  printf 'Your original changes remain in stash %s.\n' "$saved" >&2
  exit 1
fi
./deploy.sh
