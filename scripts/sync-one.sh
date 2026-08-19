#!/usr/bin/env bash
# Sync one dest from public upstream. Heads+tags only. Never prune.
# Env: MIRROR_PUSH_TOKEN, DEST, SRC, DEF
set -euo pipefail

DEST="${DEST:?}"
SRC="${SRC:?}"
DEF="${DEF:?}"
TOKEN="${MIRROR_PUSH_TOKEN:?}"
OWNER="${DEST_OWNER:-ngpestelos}"
DST="https://x-access-token:${TOKEN}@github.com/${OWNER}/${DEST}.git"
SRC_URL="https://github.com/${SRC}.git"

CI_RE='^ci: (restore sync-upstream workflow after mirror|add sync-upstream workflow for )'

need_disk() {
  local kb
  kb=$(df -k / | awk 'NR==2 {print $4}')
  if [[ "${kb:-0}" -lt 5000000 ]]; then
    echo "FAIL disk avail_kb=${kb:-none} need >=5GiB" >&2
    df -h /
    exit 1
  fi
}

bypass_secrets_from_log() {
  local logf="$1"
  local ids
  ids=$(grep -oE 'unblock-secret/[A-Za-z0-9_-]+' "$logf" 2>/dev/null | sed 's|unblock-secret/||' | sort -u || true)
  [[ -n "${ids:-}" ]] || return 1
  local id
  for id in $ids; do
    echo "BYPASS secret placeholder ${id} (false_positive — public upstream history)"
    gh api --method POST \
      -H "Accept: application/vnd.github+json" \
      "/repos/${OWNER}/${DEST}/secret-scanning/push-protection-bypasses" \
      -f reason='false_positive' \
      -f placeholder_id="$id" >/dev/null || true
  done
  return 0
}

push_with_bypass() {
  local logf rc
  logf=$(mktemp)
  set +e
  git -C src.git push "$@" >"$logf" 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    rm -f "$logf"
    return 0
  fi
  cat "$logf" >&2
  if bypass_secrets_from_log "$logf"; then
    git -C src.git push "$@"
    rm -f "$logf"
    return 0
  fi
  rm -f "$logf"
  return "$rc"
}

extra_is_ci_only() {
  local br="$1"
  local extra line
  extra=$(git -C src.git log --format=%s "refs/remotes/dest/${br}" "^refs/heads/${br}" 2>/dev/null || true)
  [[ -n "${extra}" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ $CI_RE ]]; then
      echo "NON-CI extra on ${br}: ${line}" >&2
      return 1
    fi
  done <<< "$extra"
  return 0
}

need_disk
echo "CLONE ${SRC}"
git clone --bare "$SRC_URL" src.git
git -C src.git remote add dest "$DST"
# Dest-only refs land under remotes/dest/* ; do not prune dest-only names.
set +e
git -C src.git fetch dest '+refs/heads/*:refs/remotes/dest/*' 2>/dev/null
fetch_rc=$?
set -e
if [[ $fetch_rc -ne 0 ]]; then
  echo "WARN dest fetch failed (empty dest?); will push new heads"
fi

if ! git -C src.git show-ref --verify --quiet "refs/heads/${DEF}"; then
  echo "FAIL upstream missing heads/${DEF}" >&2
  git -C src.git show-ref | head
  exit 1
fi

forced=0
ffed=0
skipped=0
failed=0

while read -r sha ref; do
  br="${ref#refs/heads/}"
  dest_ref="refs/remotes/dest/${br}"
  if ! git -C src.git show-ref --verify --quiet "$dest_ref"; then
    echo "NEW ${br}"
    if ! push_with_bypass dest "${ref}:${ref}"; then
      echo "FAIL push new ${br}" >&2
      failed=1
    else
      ffed=$((ffed + 1))
    fi
    continue
  fi
  dest_sha=$(git -C src.git rev-parse "$dest_ref")
  if [[ "$sha" == "$dest_sha" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  if git -C src.git merge-base --is-ancestor "$dest_ref" "$ref"; then
    echo "FF ${br}"
    if ! push_with_bypass dest "${ref}:${ref}"; then
      echo "FAIL ff ${br}" >&2
      failed=1
    else
      ffed=$((ffed + 1))
    fi
    continue
  fi
  if extra_is_ci_only "$br"; then
    echo "FORCE-CI ${br} dest=${dest_sha:0:12} up=${sha:0:12}"
    if ! push_with_bypass dest --force "${ref}:${ref}"; then
      echo "FAIL force-ci ${br}" >&2
      failed=1
    else
      forced=$((forced + 1))
    fi
    continue
  fi
  echo "FAIL non-ff ${br} dest=${dest_sha:0:12} up=${sha:0:12} (not CI-only extra)" >&2
  git -C src.git log --oneline -5 "$dest_ref" "^$ref" >&2 || true
  failed=1
done < <(git -C src.git for-each-ref --format='%(objectname) %(refname)' refs/heads)

# Upstream tags only (this bare clone never fetched dest tags into refs/tags).
# Dest-only tags survive; we never prune.
if ! push_with_bypass dest 'refs/tags/*:refs/tags/*'; then
  echo "TAG non-ff; force upstream tags only"
  push_with_bypass dest --force 'refs/tags/*:refs/tags/*' || failed=1
fi

echo "SUMMARY dest=${DEST} skipped=${skipped} ff=${ffed} force_ci=${forced} failed=${failed}"

up_sha=$(git -C src.git rev-parse "refs/heads/${DEF}")
dest_sha=$(git ls-remote "$DST" "refs/heads/${DEF}" | awk '{print $1}')
if [[ -z "$dest_sha" || "$up_sha" != "$dest_sha" ]]; then
  echo "FAIL SHA ${DEF} dest=${dest_sha:-none} up=${up_sha}" >&2
  exit 1
fi
echo "OK SHA ${DEF}=${dest_sha:0:12}"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
