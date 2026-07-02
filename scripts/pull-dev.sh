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
# Usage:
#   scripts/pull-dev.sh
#     pulls dotcms-dev:/live/{languageId} -> ./files/live/en-us
#
# Required environment variables:
#   DOTCMS_DEV_WEBDAV_URL - WebDAV endpoint for the Dev dotCMS instance
#   DOTCMS_USER           - WebDAV/dotCMS username
#   DOTCMS_PASS           - WebDAV/dotCMS password
#
# Optional environment variables:
#   DOTCMS_LANGUAGE_ID - numeric dotCMS language id to pull from (defaults
#                         to 1, dotCMS's out-of-the-box default language /
#                         en-us). Override if the FHLB Dev instance uses a
#                         different default language id.
#
# This script assumes an rclone remote named "dotcms-dev" has already been
# configured, e.g. via:
#   rclone config create dotcms-dev webdav url "$DOTCMS_DEV_WEBDAV_URL" \
#     vendor other user "$DOTCMS_USER" pass "$(rclone obscure "$DOTCMS_PASS")"

set -euo pipefail

RCLONE_REMOTE="dotcms-dev"
LANGUAGE_ID="${DOTCMS_LANGUAGE_ID:-1}"

# Local destination directory (locale-named folder), unrelated to the
# numeric language id used in the dotCMS WebDAV URL below.
LOCAL_LIVE_DIR="./files/live/en-us"

LIVE_SOURCE="${RCLONE_REMOTE}:/live/${LANGUAGE_ID}"

RCLONE_FLAGS=(--checksum --progress --stats=15s)

log() {
    printf '[pull-dev] %s\n' "$1"
}

log "Starting pull from Dev via rclone/WebDAV"
log "Remote: ${RCLONE_REMOTE} (language id: ${LANGUAGE_ID})"
log "Pulling: ${LIVE_SOURCE} -> ${LOCAL_LIVE_DIR}"

mkdir -p "${LOCAL_LIVE_DIR}"

if rclone sync "${LIVE_SOURCE}" "${LOCAL_LIVE_DIR}" "${RCLONE_FLAGS[@]}"; then
    log "Pull succeeded (${LOCAL_LIVE_DIR})"
else
    log "ERROR: pull FAILED (${LIVE_SOURCE} -> ${LOCAL_LIVE_DIR})"
    exit 1
fi

log "Pull complete. Review 'git status'/'git diff' before committing."
