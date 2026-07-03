# Decision: deploy-dev.sh does not block on an empty local source

## What happens
`scripts/deploy-dev.sh` runs `rclone sync ./content dotcms-dev:default`.
`rclone sync` makes the destination match the source exactly, including
deletions. If `./content` has zero files (nothing has been committed
there, or a PR intentionally deleted the last remaining file), the sync
will delete everything currently live on the server for that host.

## Why there's no guard against this
An earlier version of this script refused to run when the local source was
empty, to prevent an accidental full wipe (this happened once during
development: a local `git stash` silently emptied the working tree, and
running the script against that emptied tree wiped the Dev sandbox).

That guard also blocked **legitimate** cases — e.g. a PR that
intentionally deletes the last piece of test content, leaving the folder
empty on purpose. The guard can't tell the difference between "this is
empty by accident" and "this is empty on purpose", so it blocked both.

The guard was removed. The PR review process (branch protection, required
approval, required status checks — see `doc/github-setup.md`) is the
intended safety net: whatever is merged into `main` is deployed as-is,
including a deploy that empties the site, because that's what was
reviewed and approved.

## What this means in practice
- Never run `deploy-dev.sh` locally against a working tree you haven't
  double-checked with `git status`/`git diff` first — there's no script-level
  safety net anymore for an accidentally-empty local checkout.
- A PR that deletes content and gets merged **will** remove that content
  from Dev on the next deploy. That's expected, not a bug.
- If a future incident shows this trade-off needs revisiting (e.g. someone
  merges an accidental full deletion), consider reintroducing a guard as an
  opt-in check rather than a hard block — e.g. requiring an explicit env
  var like `ALLOW_EMPTY_DEPLOY=1` to proceed when the source is empty,
  so an empty deploy still requires a deliberate, visible signal.
