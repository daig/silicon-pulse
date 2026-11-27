#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SiliconPulse"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "Building ${APP_NAME} (release)..."
cd "$ROOT_DIR"

EXTRA_FLAGS=()
if [[ "${SILICONPULSE_SANDBOX_CACHE:-0}" == "1" ]]; then
    export TMPDIR=/tmp
    export CLANG_MODULE_CACHE_PATH=/tmp/sp_clang_cache
    export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sp_swift_cache
    EXTRA_FLAGS=(--disable-sandbox --cache-path /tmp/sp_pm_cache --config-path /tmp/sp_pm_config --security-path /tmp/sp_pm_sec)
fi

swift build -c release "${EXTRA_FLAGS[@]}"
BIN_DIR="$(swift build -c release --show-bin-path "${EXTRA_FLAGS[@]}")"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "Error: expected binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "Bundling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SiliconPulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.SiliconPulse</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SiliconPulse</string>
    <key>CFBundleDisplayName</key>
    <string>SiliconPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"
