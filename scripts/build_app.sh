#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT_DIR}/build/SafeShare.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "==> Building SafeShare in Release configuration..."
cd "${ROOT_DIR}"
swift build -c release --product SafeShare

BIN_PATH="${ROOT_DIR}/.build/release/SafeShare"
if [[ ! -f "${BIN_PATH}" ]]; then
    BIN_PATH=$(swift build -c release --show-bin-path)/SafeShare
fi

echo "==> Packaging into ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/SafeShare"
chmod +x "${MACOS_DIR}/SafeShare"

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleName</key>
    <string>SafeShare</string>
    <key>CFBundleDisplayName</key>
    <string>SafeShare</string>
    <key>CFBundleIdentifier</key>
    <string>com.safeshare.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>SafeShare</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Performing ad-hoc code signature..."
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Successfully created ${APP_DIR}!"
echo "Run via: open ${APP_DIR}"
