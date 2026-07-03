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
#     content-root defaults to ./files/live/en-us

set -euo pipefail

CONTENT_ROOT="${1:-./files/live/en-us}"

log() {
    printf '[check-content-structure] %s\n' "$1"
}

if [[ ! -d "${CONTENT_ROOT}" ]]; then
    log "${CONTENT_ROOT} does not exist, nothing to check"
    exit 0
fi

FAILED=0

# --- Check: no files directly in a host/site root folder ------------------
#
# e.g. files/live/en-us/default/foo.vtl               <- not allowed
#      files/live/en-us/default/templates/foo.vtl     <- fine
#
# dotCMS's WebDAV MKCOL handler returns 500 (instead of the expected 405)
# when asked to create a Host/Site folder that already exists. rclone
# issues MKCOL against a file's immediate parent directory before every
# upload -- if a file sits directly inside the host folder, that parent
# IS the host folder, and the upload fails (hangs retrying, then errors
# out). Files placed one level deeper never trigger this, since rclone
# never needs to MKCOL the host itself. See doc/webdav-mkcol-bug.md for
# the full writeup and evidence.
for host_dir in "${CONTENT_ROOT}"/*/; do
    [[ -d "${host_dir}" ]] || continue
    host_name="$(basename "${host_dir}")"
    loose_files="$(find "${host_dir}" -maxdepth 1 -type f)"
    if [[ -n "${loose_files}" ]]; then
        log "ERROR: file(s) found directly in host root '${host_name}/' (must live in a subfolder):"
        echo "${loose_files}" | sed 's/^/    /'
        log "dotCMS's WebDAV has a bug: syncing a file directly into a host root"
        log "folder fails (MKCOL on an existing Host returns 500 instead of 405)."
        log "Move these files into a real subfolder (e.g. <host>/templates/file.vtl"
        log "instead of <host>/file.vtl). See doc/webdav-mkcol-bug.md for details."
        FAILED=1
    fi
done

if [[ "${FAILED}" -ne 0 ]]; then
    exit 1
fi

log "OK: all checks passed"
