#!/usr/bin/env bash
# Run from the VPS Worker checkout. Local changes are kept in a named Git stash.
set -euo pipefail
cd "${1:-/var/www/RobloxWorker/RobloxWorker}"
[[ "$(git branch --show-current)" == main ]] || { echo 'Expected main branch; no update performed.' >&2; exit 1; }
git fetch origin main
# Back up only untracked files that the incoming commit would start tracking.
# Keep .env and unrelated untracked files out of Git objects and untouched.
backup=''
while IFS= read -r -d '' path; do
  if git cat-file -e "origin/main:$path" 2>/dev/null; then
    if [[ -z "$backup" ]]; then
      backup="$(git rev-parse --absolute-git-dir)/worker-update-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
      (umask 077; mkdir -p "$backup/files")
    fi
    (umask 077; mkdir -p "$backup/files/$(dirname "$path")")
    mv -- "$path" "$backup/files/$path"
    printf '%s\0' "$path" >> "$backup/paths"
  fi
done < <(git ls-files --others --exclude-standard -z)
if [[ -n "$backup" ]]; then printf 'Untracked originals backed up under %s/files.\n' "$backup"; fi
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
if [[ -n "$backup" ]]; then
  different=false
  while IFS= read -r -d '' path; do
    if ! cmp -s -- "$backup/files/$path" "$path"; then
      printf 'Incoming file differs from your saved original: %s\n' "$path" >&2
      different=true
    fi
  done < "$backup/paths"
  if [[ "$different" == true ]]; then
    printf 'Nothing deployed. Compare your originals in %s/files with the updated files first.\n' "$backup" >&2
    exit 1
  fi
fi
./deploy.sh
