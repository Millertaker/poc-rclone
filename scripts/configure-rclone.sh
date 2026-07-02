#!/usr/bin/env bash
#
# configure-rclone.sh
#
# Generates rclone.conf at runtime from environment variables so credentials
# are never committed to the repo. Used both by
# .github/workflows/deploy-to-dev.yml (populated from GitHub secrets) and
# locally (populated from .env, which is gitignored -- see .env.example).
#
# Required environment variables:
#   DOTCMS_DEV_WEBDAV_URL - WebDAV endpoint for the Dev dotCMS instance
#   DOTCMS_USER           - WebDAV/dotCMS username
#   DOTCMS_PASS           - WebDAV/dotCMS password
#
# Usage (local):
#   set -a; source .env; set +a
#   ./scripts/configure-rclone.sh
#   ./scripts/deploy-dev.sh

set -euo pipefail

: "${DOTCMS_DEV_WEBDAV_URL:?DOTCMS_DEV_WEBDAV_URL is not set}"
: "${DOTCMS_USER:?DOTCMS_USER is not set}"
: "${DOTCMS_PASS:?DOTCMS_PASS is not set}"

RCLONE_CONFIG_DIR="${RCLONE_CONFIG_DIR:-$HOME/.config/rclone}"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_DIR}/rclone.conf"

mkdir -p "${RCLONE_CONFIG_DIR}"

cat > "${RCLONE_CONFIG_FILE}" <<EOF
[dotcms-dev]
type = webdav
url = ${DOTCMS_DEV_WEBDAV_URL}
vendor = other
user = ${DOTCMS_USER}
pass = $(rclone obscure "${DOTCMS_PASS}")
EOF

chmod 600 "${RCLONE_CONFIG_FILE}"

echo "[configure-rclone] Wrote ${RCLONE_CONFIG_FILE} (remote: dotcms-dev)"
