#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FaceLook"
BUILD_DIR=".build/debug"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."
swift build --build-system native -Xswiftc -module-cache-path -Xswiftc /tmp/module-cache

echo "📦 Assembling ${APP_BUNDLE} bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "unlock_action.sh" "${APP_BUNDLE}/Contents/Resources/unlock_action.sh"
chmod +x "${APP_BUNDLE}/Contents/Resources/unlock_action.sh"

echo "🔏 Signing with camera entitlements..."
codesign -s - --entitlements FaceLook.entitlements --force "${APP_BUNDLE}"

echo "✅ App bundle created: ${APP_BUNDLE}"
echo "   Launch directly via: open ${APP_BUNDLE}"

