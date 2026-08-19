# mirror-sync

Daily heads+tags sync of `ngpestelos/*` full-history mirrors. Schedule lives here so dest default can stay SHA-identical to upstream.

Dest-local `.github/workflows/sync-upstream.yml` is retired. `GITHUB_TOKEN` cannot restore workflow files on public dests.

## Auth

Repo secret `MIRROR_PUSH_TOKEN`: fine-grained PAT, **selected dests**, Contents read/write **and** Workflows write. Not All repositories.

Disable Actions on each dest **before** the first PAT push. PAT pushes trigger dest `on: push` CI; `GITHUB_TOKEN` did not.

## Add a dest

1. `mirror_one_oss.sh <name> <owner/repo> [branch]` (no dest workflow).
2. Disable dest Actions: `gh api -X PUT repos/ngpestelos/<name>/actions/permissions -f enabled=false`
3. Add dest to the PAT selected-repos list.
4. `python3 scripts/harvest.py` (or append `mirrors.yml`) and push.

## Manual

```bash
gh workflow run "Sync mirrors" --repo ngpestelos/mirror-sync -f dest=rails
```

Per dest: default-branch SHA on dest must equal upstream. Fleet is `M/N`, not "run green".
