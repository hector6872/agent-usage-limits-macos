#!/usr/bin/env bash
set -e

APP_NAME="AgentUsageLimits"
BUNDLE_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} in Release mode..."
swift build -c release

echo "==> Generating App Icons..."
swift scripts/generate_icon.swift
if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns resources/AppIcon.iconset -o resources/AppIcon.icns
fi

echo "==> Packaging into ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy icons if available
if [ -f "resources/AppIcon.icns" ]; then
    cp "resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Generate Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage Limits</string>
    <key>CFBundleIdentifier</key>
    <string>com.hector.agentusagelimits</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Bundle created successfully at ${BUNDLE_DIR}"
echo "    You can run it with: open ${BUNDLE_DIR}"
