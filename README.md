# poc-rclone

## Content layout

All content that gets synced to dotCMS lives in `./content` at the repo
root — it maps 1:1 to the `default` host root on the dotCMS WebDAV server
(`content/templates/foo.vtl` on disk ↔ `default/templates/foo.vtl` on the
server). This project only ever targets that one host, hardcoded as
`default` in `deploy-dev.sh`/`pull-dev.sh` — there is no multi-site
support and none is planned.

Files directly inside `content/` (e.g. `content/robots.txt`,
`content/sitemap.xml`) are allowed and get deployed too — `deploy-dev.sh`
just handles them differently than subfolders (a direct HTTP upload
instead of `rclone sync`), because of a dotCMS WebDAV quirk. See
`doc/webdav-mkcol-bug.md` for why.

## Deploy to Dev

After a PR is merged into `main`, `.github/workflows/deploy-to-dev.yml` runs
automatically and deploys to the dotCMS Dev environment:

1. Checkout the repo.
2. Generate `rclone.conf` at runtime from repository secrets/variables (never committed).
3. Smoke-check `DOTCMS_DEV_URL` before deploying, failing the job if Dev is unreachable.
4. Run `scripts/deploy-dev.sh` to sync assets over WebDAV via `rclone sync`.
5. Smoke-check again after deploying.

Required repository config (repo-level, not org-level), in
`Settings → Secrets and variables → Actions`:

- **Secrets** (sensitive credentials): `DOTCMS_USER`, `DOTCMS_PASS`
- **Variables** (non-sensitive config): `DOTCMS_DEV_WEBDAV_URL`, `DOTCMS_DEV_URL`

`DOTCMS_DEV_WEBDAV_URL` must be the **full** WebDAV live URL, including the
language id, e.g.:

```
https://<server>/webdav/live/1
```

The scripts use this value directly as the rclone remote root — they don't
append `/live/<languageId>` themselves, so the full path has to be in the
variable already.

### Why deploy-dev.sh writes to `live`

dotCMS's WebDAV plugin exposes a `/webdav/live/{languageId}` path per its
[docs](https://dev.dotcms.com/docs/latest/webdav) that saves **and
publishes** the file in one step. Since this pipeline only runs after a PR
has already been reviewed and passed Semgrep on `main`, content should go
live directly. If either the smoke check or the `rclone sync` fails, the
script/workflow exits non-zero and stops.

## Pulling from Dev

`scripts/pull-dev.sh` is the reverse of the deploy script: it pulls the
published (live) files down from the dotCMS Dev environment into the local
repo, for when content was changed directly on the server (e.g. in the
dotCMS admin UI) and needs to be reconciled back into git.

```
scripts/pull-dev.sh
```

Pulls `DOTCMS_DEV_WEBDAV_URL/default` into `./content`.

It uses `rclone sync`, which mirrors the remote exactly (including deleting
local files that no longer exist on the server). This is safe here because
the repo is version-controlled: review `git status`/`git diff` after running
it and before committing, so any unexpected change or deletion is visible
first. Requires the same `DOTCMS_DEV_WEBDAV_URL`, `DOTCMS_USER`, `DOTCMS_PASS`
environment variables as the deploy script, and the same `dotcms-dev` rclone
remote configured locally.

## Running the scripts locally

Copy `.env.example` to `.env` and fill in your Dev credentials (`.env` is
gitignored and must never be committed):

```
cp .env.example .env
# edit .env with your DOTCMS_DEV_WEBDAV_URL / DOTCMS_USER / DOTCMS_PASS / DOTCMS_DEV_URL
```

Then, in the same shell session, load it, configure the local rclone remote,
and run whichever script you need:

```bash
set -a; source .env; set +a
./scripts/configure-rclone.sh

./scripts/pull-dev.sh          # pull published (live) files from Dev
./scripts/deploy-dev.sh        # push local files to Dev (live)
./scripts/smoke-check.sh       # check DOTCMS_DEV_URL responds
```

All three commands (`source`, `configure-rclone.sh`, and whichever script
you run) must happen in the same shell session — `set -a; source .env; set +a`
only exports the variables for that session, so opening a new terminal or
subshell requires repeating it.

`configure-rclone.sh` writes `~/.config/rclone/rclone.conf` with a
`dotcms-dev` remote from those env vars (the same script the GitHub Actions
workflow uses, populated from repository secrets instead).