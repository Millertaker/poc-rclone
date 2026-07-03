# GitHub setup: Actions secrets/variables, branch protection, and required checks

This documents the one-time GitHub configuration needed for
`.github/workflows/deploy-to-dev.yml` (deploy to Dev on merge to `main`)
and `.github/workflows/pr-checks.yml` (structural checks on every PR) to
work as intended, including a real gotcha we hit while setting this up.

## 1. Repository secrets and variables

Repo-level, not org-level: `Settings → Secrets and variables → Actions`.
This screen has two separate tabs — **Secrets** and **Variables** — pick
the right one per value below. If a value goes in the wrong tab, the
workflow reads it as empty (`secrets.X` and `vars.X` don't fall back to
each other).

| Name | Tab | Value |
|---|---|---|
| `DOTCMS_USER` | Secrets | dotCMS/WebDAV username |
| `DOTCMS_PASS` | Secrets | dotCMS/WebDAV password |
| `DOTCMS_DEV_WEBDAV_URL` | Variables | Full WebDAV **live** URL, including the language id, e.g. `https://<server>/webdav/live/1` |
| `DOTCMS_DEV_URL` | Variables | Public URL of the Dev environment, e.g. `https://<server>/` |

`DOTCMS_USER`/`DOTCMS_PASS` are real credentials, so they're Secrets
(encrypted, masked in logs, never displayed again after saving). The two
URLs aren't sensitive, so they're Variables (plain text, visible in the
UI) — see `README.md` for more on why the split.

**Important**: `DOTCMS_DEV_WEBDAV_URL` must be the **full** URL down to
the language id (`/webdav/live/1`), not just the host or `/webdav` root.
The scripts (`deploy-dev.sh`, `pull-dev.sh`) use this value directly as
the rclone remote root — they don't append `/live/<id>` themselves.

## 2. Actions permissions

`Settings → Actions → General → Workflow permissions`. "Read and write
permissions" is enough (this pipeline doesn't need write access back to
the repo, but it doesn't hurt to have it).

## 3. Branch protection for `main`

`Settings → Branches → Branch protection rules`.

### Gotcha: the branch name pattern must be exactly `main`

When first setting this up here, the existing rule's **Branch name
pattern** field was set to `proserv` — a leftover from another project —
which matched **0 branches** in this repo. Every setting under "Protect
matching branches" was configured correctly, but none of it ever applied
to anything, because the rule didn't match `main`. This is easy to miss:
the checkboxes look fully configured and give no indication the rule
isn't actually attached to a real branch.

**Before touching anything else, confirm**: the rule's "Branch name
pattern" field says `main` (or a pattern that matches it, like `main*`),
and "Applies to N branches" shows at least 1.

### Settings to enable, once the pattern is correct

- ✅ **Require a pull request before merging** — blocks direct pushes to
  `main`; all changes must go through a PR.
  - ✅ **Require approvals** — set to `1` (or more).
- ✅ **Require status checks to pass before merging** — see step 4 below
  for how to actually select a check here; it can't be picked until it
  has run at least once.
- Optional, not currently enabled here: `Dismiss stale approvals`,
  `Require review from Code Owners`, `Require conversation resolution`,
  `Require signed commits`, `Require linear history`,
  `Do not allow bypassing the above settings` (this last one is what
  `enforce_admins` maps to in the GitHub UI — enable it if admins should
  also be blocked by these rules, not just regular contributors).

## 4. Making the PR structural check block merges

`.github/workflows/pr-checks.yml` runs
`scripts/check-content-structure.sh` on every PR targeting `main` (see
`doc/webdav-mkcol-bug.md` for what it checks and why). By default this
check can **fail without blocking the merge button** — "failing" and
"required" are two different things in GitHub. To make a failing check
actually block merging:

1. **The check has to run at least once** before GitHub will offer it as
   an option. GitHub only lists status checks that have posted a result
   in the last week for this repo. Open any PR against `main` (even a
   throwaway one) so `pr-checks.yml` fires once.
2. Go to `Settings → Branches` → edit the rule for `main` (with the
   correct pattern, per step 3).
3. Under **Require status checks to pass before merging**, click into the
   search box and type something (e.g. `loose` or `PR Checks`) — the
   list only populates once you've typed a query, it does not show
   available checks by default.
4. Select:
   ```
   No loose files in host root (see doc/webdav-mkcol-bug.md)
   ```
   This is the job name from `pr-checks.yml`, not the workflow name — if
   the job is renamed later, re-select it here too.
5. Save.

Once this is set, any PR where `check-content-structure.sh` fails will
show a red ❌ and the `Merge pull request` button will be disabled, not
just show a warning.

## 5. Triggering the deploy workflow manually (optional)

`.github/workflows/deploy-to-dev.yml` includes `workflow_dispatch`, so it
can be run on demand from the Actions tab (`Actions → Deploy to Dev → Run
workflow`) without needing a new commit to `main` — useful when
iterating/testing against the sandbox.
