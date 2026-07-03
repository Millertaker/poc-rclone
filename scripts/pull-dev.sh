#!/usr/bin/env bash
#
# pull-dev.sh
#
# Pulls the published (live) files from the dotCMS Dev environment down to
# this local repo over WebDAV using rclone. This is the reverse of
# scripts/deploy-dev.sh: it is meant to reconcile local files with content
# that was changed directly on the server (e.g. in the dotCMS admin UI) so
# the repo stays the source of truth.
#
# Since local files are tracked in git, `rclone sync` (an exact mirror, incl.
# deleting local files that no longer exist on the server) is safe to use
# here: any unexpected change or deletion shows up in `git diff`/`git status`
# before it is committed, so nothing is silently lost.
#
# DOTCMS_DEV_WEBDAV_URL is the full WebDAV root to pull from, e.g.
#   https://<server>/webdav/live/<languageId>
#
# Usage:
#   scripts/pull-dev.sh
#     pulls DOTCMS_DEV_WEBDAV_URL/default -> ./content
#
# Required environment variables:
#   DOTCMS_DEV_WEBDAV_URL - full WebDAV live URL for the Dev dotCMS instance
#                           (see above)
#   DOTCMS_USER           - WebDAV/dotCMS username
#   DOTCMS_PASS           - WebDAV/dotCMS password
#
# This script assumes an rclone remote named "dotcms-dev" has already been
# configured, e.g. via:
#   rclone config create dotcms-dev webdav url "$DOTCMS_DEV_WEBDAV_URL" \
#     vendor other user "$DOTCMS_USER" pass "$(rclone obscure "$DOTCMS_PASS")"

set -euo pipefail

RCLONE_REMOTE="dotcms-dev"

# This project only ever targets a single dotCMS host/site, "default".
DOTCMS_HOST="default"

# Local destination directory. content/ maps directly to the "default"
# host root on the server -- there is no extra locale or host-named
# subfolder locally.
LOCAL_LIVE_DIR="./content"

LIVE_SOURCE="${RCLONE_REMOTE}:${DOTCMS_HOST}"

# system/languages holds dotCMS's language property files, which require the
# CMS Admin/Administrator role to read over WebDAV
# (https://dev.dotcms.com/docs/webdav). dotCMS still lists this folder to
# every user, but it lives outside the "default" host anyway, so it's
# never touched by this pull. --exclude kept here in case a future host
# path ever surfaces something similar.
RCLONE_FLAGS=(--checksum --progress --stats=15s --exclude "system/**" --exclude ".DS_Store")

log() {
    printf '[pull-dev] %s\n' "$1"
}

log "Starting pull from Dev via rclone/WebDAV"
log "Remote: ${RCLONE_REMOTE} (host: ${DOTCMS_HOST})"
log "WebDAV URL: ${DOTCMS_DEV_WEBDAV_URL:-<not set>}"
log "Pulling: ${LIVE_SOURCE} (${DOTCMS_DEV_WEBDAV_URL:-<not set>}/${DOTCMS_HOST}) -> ${LOCAL_LIVE_DIR}"

mkdir -p "${LOCAL_LIVE_DIR}"

if rclone sync "${LIVE_SOURCE}" "${LOCAL_LIVE_DIR}" "${RCLONE_FLAGS[@]}"; then
    log "Pull succeeded (${LOCAL_LIVE_DIR})"
else
    log "ERROR: pull FAILED (${LIVE_SOURCE} -> ${LOCAL_LIVE_DIR})"
    exit 1
fi

log "Pull complete. Review 'git status'/'git diff' before committing."
