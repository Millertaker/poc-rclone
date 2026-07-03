#!/usr/bin/env bash
#
# check-content-structure.sh
#
# Structural checks on the local content tree before it's synced to Dev.
# Add more checks here as they come up; each should log a clear reason and
# set FAILED=1 rather than exiting immediately, so a single run reports
# every problem instead of just the first one.
#
# Usage:
#   scripts/check-content-structure.sh [content-root]
#     content-root defaults to ./content

set -euo pipefail

CONTENT_ROOT="${1:-./content}"

log() {
    printf '[check-content-structure] %s\n' "$1"
}

if [[ ! -d "${CONTENT_ROOT}" ]]; then
    log "${CONTENT_ROOT} does not exist, nothing to check"
    exit 0
fi

FAILED=0

# --- Check: no files directly in content/ itself ---------------------------
#
# e.g. content/foo.vtl               <- not allowed
#      content/templates/foo.vtl     <- fine
#
# content/ maps directly to the "default" host root on the dotCMS WebDAV
# server (see scripts/deploy-dev.sh). dotCMS's WebDAV MKCOL handler returns
# 500 (instead of the expected 405) when asked to create that Host/Site
# folder when it already exists. rclone issues MKCOL against a file's
# immediate parent directory before every upload -- if a file sits
# directly inside content/, its remote parent IS the host folder, and the
# upload fails (hangs retrying, then errors out). Files placed one level
# deeper never trigger this, since rclone never needs to MKCOL the host
# itself. See doc/webdav-mkcol-bug.md for the full writeup and evidence.
loose_files="$(find "${CONTENT_ROOT}" -maxdepth 1 -type f)"
if [[ -n "${loose_files}" ]]; then
    log "ERROR: file(s) found directly in ${CONTENT_ROOT} (must live in a subfolder):"
    echo "${loose_files}" | sed 's/^/    /'
    log "dotCMS's WebDAV has a bug: syncing a file directly into the host root"
    log "folder fails (MKCOL on an existing Host returns 500 instead of 405)."
    log "Move these files into a real subfolder (e.g. templates/file.vtl"
    log "instead of file.vtl). See doc/webdav-mkcol-bug.md for details."
    FAILED=1
fi

if [[ "${FAILED}" -ne 0 ]]; then
    exit 1
fi

log "OK: all checks passed"
