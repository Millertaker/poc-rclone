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
# ##########################################################################
# # WARNING -- NEVER PLACE FILES DIRECTLY IN content/ ITSELF               #
# #                                                                        #
# # e.g. content/foo.vtl                                <- WILL FAIL      #
# #      content/templates/foo.vtl                      <- OK             #
# #                                                                        #
# # dotCMS's WebDAV MKCOL handler returns 500 (not the expected 405) when #
# # asked to create the Host/Site folder ("default") when it already      #
# # exists. rclone issues MKCOL against a file's immediate parent before  #
# # every upload -- if a file sits directly in content/, its remote      #
# # parent IS the "default" host folder, and the sync hangs retrying,    #
# # then fails. This is checked automatically below via                  #
# # scripts/check-content-structure.sh. See doc/webdav-mkcol-bug.md for  #
# # the full writeup and evidence.                                       #
# ##########################################################################
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

# This project only ever targets a single dotCMS host/site, "default".
DOTCMS_HOST="default"

# Local source directory that gets mirrored to Dev. content/ maps directly
# to the "default" host root on the server -- there is no extra locale or
# host-named subfolder locally.
LOCAL_SOURCE_DIR="./content"

LIVE_TARGET="${RCLONE_REMOTE}:${DOTCMS_HOST}"

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
log "Remote: ${RCLONE_REMOTE} (host: ${DOTCMS_HOST})"
log "WebDAV URL: ${DOTCMS_DEV_WEBDAV_URL:-<not set>}"
log "Syncing: ${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET} (${DOTCMS_DEV_WEBDAV_URL:-<not set>}/${DOTCMS_HOST})"

# rclone sync mirrors the destination to match the source exactly, including
# deletions -- an empty local source deletes everything under this host on
# the server. This is intentional: git/PR review is the source of truth and
# the safety net (see doc/deploy-empty-source.md). Make sure the directory
# exists so rclone doesn't error on a genuinely missing path (e.g. nothing
# has ever been committed here yet).
mkdir -p "${LOCAL_SOURCE_DIR}"

# See the WARNING at the top of this file and doc/webdav-mkcol-bug.md.
if ! ./scripts/check-content-structure.sh "${LOCAL_SOURCE_DIR}"; then
    log "ERROR: refusing to sync -- fix the file placement above and try again"
    exit 1
fi

if rclone sync "${LOCAL_SOURCE_DIR}" "${LIVE_TARGET}" "${RCLONE_FLAGS[@]}"; then
    log "Sync succeeded (${LIVE_TARGET}). Content saved and published."
else
    log "ERROR: sync FAILED (${LOCAL_SOURCE_DIR} -> ${LIVE_TARGET})"
    exit 1
fi

log "Deploy complete."
