# mirror-sync

Daily heads+tags sync of `ngpestelos-mirrors/*` full-history dests. Schedule lives here so dest default can stay SHA-identical to upstream.

Dest-local `.github/workflows/sync-upstream.yml` is retired. `GITHUB_TOKEN` cannot restore workflow files on public dests.

## Auth

GitHub App `ngpestelos-mirror-sync` installed on org `ngpestelos-mirrors`, **all org repos**. Secrets `MIRROR_APP_ID` + `MIRROR_APP_PRIVATE_KEY`. Installation tokens: username `x-access-token`. Dest not visible to the App is **SKIP** (exit 0), not fail.

`MIRROR_PUSH_TOKEN` is the retired selected-repos PAT fallback. Do not switch that PAT to All repositories.

Disable dest Actions **before** the first App push.

## Add a dest

1. `mirror_one_oss.sh <name> <owner/repo> [branch]` — dest is `ngpestelos-mirrors/<name>` (no dest workflow).
2. Disable dest Actions: `printf '{"enabled":false}\n' | gh api --method PUT repos/ngpestelos-mirrors/<name>/actions/permissions --input -`
3. App all-org-repos sees it. Do not add dests to a PAT.
4. `python3 scripts/harvest.py` (or append `mirrors.yml`) and push.

## Manual

```bash
gh workflow run "Sync mirrors" --repo ngpestelos/mirror-sync -f dest=rails
```

Per dest: default-branch SHA on dest must equal upstream. Fleet is `M/N`, not "run green".
