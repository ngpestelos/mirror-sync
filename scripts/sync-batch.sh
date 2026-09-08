#!/usr/bin/env bash
# Loop scripts/sync-one.sh over ENTRIES_JSON (a JSON array of
# {dest,src,default,timeout}), isolating each entry's working directory —
# sync-one.sh's bare clone `src.git` is never cleaned up by that script,
# so reusing one cwd across entries would break every entry after the
# first. Continues past per-entry failures (fail-fast:false semantics,
# now at entry granularity within a batch instead of at job granularity).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENTRIES_JSON="${ENTRIES_JSON:?}"

total=0
failed=0

while IFS= read -r entry; do
  total=$((total + 1))
  DEST=$(jq -r '.dest' <<<"$entry")
  SRC=$(jq -r '.src' <<<"$entry")
  DEF=$(jq -r '.default' <<<"$entry")
  TIMEOUT=$(jq -r '.timeout' <<<"$entry")
  export DEST SRC DEF

  workdir=$(mktemp -d) || {
    echo "DEST=${DEST} RC=mktemp-failed" >&2
    failed=$((failed + 1))
    continue
  }
  pushd "$workdir" >/dev/null
  if timeout -k 30 "${TIMEOUT}m" bash "$HERE/sync-one.sh"; then
    echo "DEST=${DEST} RC=0"
  else
    rc=$?
    echo "DEST=${DEST} RC=${rc}" >&2
    failed=$((failed + 1))
  fi
  popd >/dev/null
  rm -rf "$workdir"
done < <(jq -c '.[]' <<<"$ENTRIES_JSON")

echo "SUMMARY total=${total} failed=${failed}"
if [[ "$total" -eq 0 ]]; then
  echo "FAIL zero entries processed (empty or malformed ENTRIES_JSON)" >&2
  exit 1
fi
[[ "$failed" -eq 0 ]]
