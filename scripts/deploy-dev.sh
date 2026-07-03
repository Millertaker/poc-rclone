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
# WHY SUBFOLDERS AND ROOT-LEVEL FILES (e.g. content/robots.txt) ARE
# HANDLED DIFFERENTLY:
# dotCMS's WebDAV MKCOL handler returns 500 (not the expected 405) when
# asked to create the Host/Site folder ("default") when it already exists.
# rclone issues MKCOL against a file's immediate parent before every
# upload -- for a file directly in content/, that parent IS the "default"
# host folder, so rclone always fails on it. Subfolders don't have this
# problem (MKCOL on an existing regular folder works fine), so:
#   - subfolders (content/templates/, content/widgets/, ...) sync via
#     rclone, scoped to their own remote path
#   - files directly in content/ (content/robots.txt, content/sitemap.xml,
#     or anything else) upload via a raw HTTP PUT, which has no MKCOL
#     preflight and works fine against the same, already-existing folder
# See doc/webdav-mkcol-bug.md for the full writeup and evidence.
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

# Local source directory. content/ maps directly to the "default" host
# root on the server -- there is no extra locale or host-named subfolder
# locally.
LOCAL_SOURCE_DIR="./content"

# Common rclone flags:
#   credentials live in the generated rclone.conf, not on the command line,
#   so they never appear in process listings or logs.
#   system/languages holds dotCMS's language property files, which require
#   the CMS Admin/Administrator role over WebDAV
#   (https://dev.dotcms.com/docs/webdav) and aren't part of the
#   template/page content this script deploys, so exclude that path.
#   --transfers 1: dotCMS's WebDAV appears to race when multiple sibling
#   files in the same folder are uploaded concurrently (rclone's default is
#   4 parallel transfers) -- the post-upload size check would come back
#   with another file's size, failing with "corrupted on transfer". Forcing
#   one file at a time avoids that race.
RCLONE_FLAGS=(--checksum --progress --stats=15s --exclude "system/**" --transfers 1)

log() {
    printf '[deploy-dev] %s\n' "$1"
}

log "Starting deploy to Dev via rclone/WebDAV"
log "Remote: ${RCLONE_REMOTE} (host: ${DOTCMS_HOST})"
log "WebDAV URL: ${DOTCMS_DEV_WEBDAV_URL:-<not set>}"

# rclone sync mirrors the destination to match the source exactly, including
# deletions -- an empty local subfolder deletes everything under that
# subfolder on the server. This is intentional: git/PR review is the
# source of truth and the safety net (see doc/deploy-empty-source.md).
# Make sure the directory exists so nothing below errors on a genuinely
# missing path (e.g. nothing has ever been committed here yet).
mkdir -p "${LOCAL_SOURCE_DIR}"

# --- Sync subfolders via rclone --------------------------------------------
for subdir in "${LOCAL_SOURCE_DIR}"/*/; do
    [[ -d "${subdir}" ]] || continue
    subdir_name="$(basename "${subdir}")"
    target="${RCLONE_REMOTE}:${DOTCMS_HOST}/${subdir_name}"

    log "Syncing folder '${subdir_name}': ${subdir} -> ${target}"

    if rclone sync "${subdir}" "${target}" "${RCLONE_FLAGS[@]}"; then
        log "Sync succeeded for '${subdir_name}' (${target})"
    else
        log "ERROR: sync FAILED for '${subdir_name}' (${subdir} -> ${target})"
        exit 1
    fi
done

# --- Upload root-level files via a raw HTTP PUT ----------------------------
#
# No automatic deletion here: this only pushes what currently exists
# locally. If a root file is removed from content/, remove it from Dev
# manually.
for root_file in "${LOCAL_SOURCE_DIR}"/*; do
    [[ -f "${root_file}" ]] || continue
    filename="$(basename "${root_file}")"
    target_url="${DOTCMS_DEV_WEBDAV_URL%/}/${DOTCMS_HOST}/${filename}"

    log "Uploading root file '${filename}' -> ${target_url}"

    if curl -fsS -u "${DOTCMS_USER}:${DOTCMS_PASS}" -T "${root_file}" "${target_url}"; then
        log "Uploaded '${filename}'"
    else
        log "ERROR: failed to upload '${filename}' -> ${target_url}"
        exit 1
    fi
done

log "Deploy complete."
