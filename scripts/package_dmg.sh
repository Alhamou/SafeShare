#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_PATH="${BUILD_DIR}/SafeShare.app"
DMG_NAME="SafeShare-1.1.0.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
STAGING_DIR="${BUILD_DIR}/dmg_staging"

# 1. Ensure the app is built
if [[ ! -d "${APP_PATH}" ]]; then
    echo "==> App not found at ${APP_PATH}. Running build_app.sh first..."
    "${SCRIPT_DIR}/build_app.sh"
fi

echo "==> Preparing DMG staging environment..."
rm -rf "${STAGING_DIR}"
rm -f "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

# 2. Copy application into staging
echo "==> Copying SafeShare.app to staging..."
cp -R "${APP_PATH}" "${STAGING_DIR}/SafeShare.app"

# 3. Create Applications symlink
echo "==> Creating /Applications symlink..."
ln -s /Applications "${STAGING_DIR}/Applications"

# 4. Generate compressed read-only DMG with hdiutil
echo "==> Generating compressed DMG: ${DMG_PATH}..."
hdiutil create \
    -volname "SafeShare" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# 5. Clean up staging directory
rm -rf "${STAGING_DIR}"

echo "==> Successfully created ${DMG_PATH}!"
echo "Size: $(du -sh "${DMG_PATH}" | cut -f1)"
