#!/usr/bin/env bash
#
# deploy-dev.sh
#
# Pushes templates and static/.vtl assets to the dotCMS Dev environment over
# WebDAV using rclone, publishing directly to live.
#
# This script syncs straight to the dotCMS WebDAV "live" path
# (https://dev.dotcms.com/docs/latest/webdav), which saves AND publishes the
# file in the same step. Since this pipeline only runs after a PR has
# already been reviewed and passed Semgrep on main, content should go live
# directly.
#
# Required environment variables (populated from GitHub Actions secrets):
#   DOTCMS_DEV_WEBDAV_URL - WebDAV endpoint for the Dev dotCMS instance
#   DOTCMS_USER           - WebDAV/dotCMS username
#   DOTCMS_PASS           - WebDAV/dotCMS password
#
# Optional environment variables:
#   DOTCMS_LANGUAGE_ID - numeric dotCMS language id to publish into
#                         (defaults to 1, dotCMS's out-of-the-box default
#                         language / en-us). Override if the FHLB Dev
#                         instance uses a different default language id.
#
# This script assumes an rclone remote named "dotcms-dev" has already been
# configured (see .github/workflows/deploy-to-dev.yml).

set -euo pipefail

RCLONE_REMOTE="dotcms-dev"
LANGUAGE_ID="${DOTCMS_LANGUAGE_ID:-1}"

# Local source directory that gets mirrored to Dev.
LOCAL_SOURCE_DIR="./files/live/en-us"

# Remote destination on the dotCMS WebDAV endpoint. Writing here both saves
# and publishes the content.
LIVE_TARGET="${RCLONE_REMOTE}:/live/${LANGUAGE_ID}"

# Common rclone flags:
#   credentials live in the generated rclone.conf, not on the command line,
#   so they never appear in process listings or logs.
RCLONE_FLAGS=(--checksum --progress --stats=15s)

log() {
    printf '[deploy-dev] %s\n' "$1"
}

log "Starting deploy to Dev via rclone/WebDAV"
log "Remote: ${RCLONE_REMOTE} (language id: ${LANGUAGE_ID})"
log "Syncing: ${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET}"

if rclone sync "${LOCAL_SOURCE_DIR}" "${LIVE_TARGET}" "${RCLONE_FLAGS[@]}"; then
    log "Sync succeeded (${LIVE_TARGET}). Content saved and published."
else
    log "ERROR: sync FAILED (${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET})"
    exit 1
fi

log "Deploy complete."
