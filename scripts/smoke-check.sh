#!/usr/bin/env bash
#
# smoke-check.sh
#
# Basic reachability check for the dotCMS Dev environment. Used both:
#   - before deploying assets, to fail fast if Dev is down/unreachable
#   - after deploying assets, to confirm key pages still resolve
#
# Usage:
#   scripts/smoke-check.sh                # checks DOTCMS_DEV_URL only
#   scripts/smoke-check.sh /path/one /path/two   # also checks these paths
#
# Required environment variables:
#   DOTCMS_DEV_URL - base URL of the Dev environment

set -euo pipefail

if [[ -z "${DOTCMS_DEV_URL:-}" ]]; then
    echo "[smoke-check] ERROR: DOTCMS_DEV_URL is not set" >&2
    exit 1
fi

BASE_URL="${DOTCMS_DEV_URL%/}"
PATHS=("$@")
if [[ ${#PATHS[@]} -eq 0 ]]; then
    PATHS=("/")
fi

FAILED=0

for path in "${PATHS[@]}"; do
    url="${BASE_URL}${path}"
    echo "[smoke-check] Checking ${url}"

    http_status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "${url}" || echo "000")

    if [[ "${http_status}" =~ ^[23][0-9][0-9]$ ]]; then
        echo "[smoke-check] OK: ${url} responded with HTTP ${http_status}"
    else
        echo "[smoke-check] ERROR: ${url} responded with HTTP ${http_status}" >&2
        FAILED=1
    fi
done

if [[ "${FAILED}" -ne 0 ]]; then
    echo "[smoke-check] One or more checks failed" >&2
    exit 1
fi

echo "[smoke-check] All checks passed"
