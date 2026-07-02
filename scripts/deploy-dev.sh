#!/usr/bin/env bash
#
# deploy-dev.sh
#
# Pushes templates and static/.vtl assets to the dotCMS Dev environment over
# WebDAV using rclone, publishing directly to live.
#
# DOTCMS_DEV_WEBDAV_URL is the full WebDAV root to sync to, e.g.
#   https://<server>/webdav/live/<languageId>
# Writing here both saves and publishes the content in the same step. Since
# this pipeline only runs after a PR has already been reviewed and passed
# Semgrep on main, content should go live directly.
#
# Required environment variables (populated from GitHub Actions secrets/vars):
#   DOTCMS_DEV_WEBDAV_URL - full WebDAV live URL for the Dev dotCMS instance
#                           (see above)
#   DOTCMS_USER           - WebDAV/dotCMS username
#   DOTCMS_PASS           - WebDAV/dotCMS password
#
# This script assumes an rclone remote named "dotcms-dev" has already been
# configured (see .github/workflows/deploy-to-dev.yml), with its "url" set
# to DOTCMS_DEV_WEBDAV_URL.

set -euo pipefail

RCLONE_REMOTE="dotcms-dev"

# Local source directory that gets mirrored to Dev.
LOCAL_SOURCE_DIR="./files/live/en-us"

# Remote destination: the bare configured remote, since DOTCMS_DEV_WEBDAV_URL
# already points directly at the live/<languageId> root.
LIVE_TARGET="${RCLONE_REMOTE}:"

# Common rclone flags:
#   credentials live in the generated rclone.conf, not on the command line,
#   so they never appear in process listings or logs.
#   system/languages holds dotCMS's language property files, which require
#   the CMS Admin/Administrator role over WebDAV
#   (https://dev.dotcms.com/docs/webdav) and aren't part of the
#   template/page content this script deploys, so exclude that path.
RCLONE_FLAGS=(--checksum --progress --stats=15s --exclude "system/**")

log() {
    printf '[deploy-dev] %s\n' "$1"
}

log "Starting deploy to Dev via rclone/WebDAV"
log "Remote: ${RCLONE_REMOTE}"
log "WebDAV URL: ${DOTCMS_DEV_WEBDAV_URL:-<not set>}"
log "Syncing: ${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET} (${DOTCMS_DEV_WEBDAV_URL:-<not set>})"

# rclone sync mirrors the destination to match the source exactly, including
# deletions. An empty (or missing) local source would wipe out everything
# live on the server. Refuse to run rather than risk that.
if [[ ! -d "${LOCAL_SOURCE_DIR}" ]] || [[ -z "$(find "${LOCAL_SOURCE_DIR}" -type f -print -quit)" ]]; then
    log "ERROR: ${LOCAL_SOURCE_DIR} does not exist or has no files -- refusing to sync an empty source, which would delete everything on ${LIVE_TARGET}"
    exit 1
fi

if rclone sync "${LOCAL_SOURCE_DIR}" "${LIVE_TARGET}" "${RCLONE_FLAGS[@]}"; then
    log "Sync succeeded (${LIVE_TARGET}). Content saved and published."
else
    log "ERROR: sync FAILED (${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET})"
    exit 1
fi

log "Deploy complete."
