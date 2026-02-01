#!/bin/bash
set -e

# Quit the app if it's running
if pgrep -x "MXF2PRXY" > /dev/null; then
    echo "Quitting running instance of MXF2PRXY..."
    killall MXF2PRXY 2>/dev/null || true
    sleep 0.5
fi

# Build
swift build

# Create app bundle structure
mkdir -p MXF2PRXY.app/Contents/MacOS
mkdir -p MXF2PRXY.app/Contents/Resources

# Copy binary
cp .build/debug/MXFToQuickTime MXF2PRXY.app/Contents/MacOS/MXF2PRXY

# Download static ffmpeg if not already present
if [ ! -f /tmp/ffmpeg-static-cached ]; then
    echo "Downloading static ffmpeg..."
    curl -sL https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip -o /tmp/ffmpeg-static.zip
    unzip -o /tmp/ffmpeg-static.zip -d /tmp/ > /dev/null
    mv /tmp/ffmpeg /tmp/ffmpeg-static-cached
    chmod +x /tmp/ffmpeg-static-cached
fi
cp /tmp/ffmpeg-static-cached MXF2PRXY.app/Contents/MacOS/ffmpeg

# Copy icon and resources
cp AppIcon.icns MXF2PRXY.app/Contents/Resources/
cp -f MXF2Prxy-logo.png MXF2PRXY.app/Contents/Resources/ 2>/dev/null || true
cp -f watermark.png MXF2PRXY.app/Contents/Resources/ 2>/dev/null || true

# Create Info.plist
cat > MXF2PRXY.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>MXF2PRXY</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.mxf2prxy</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>MXF2PRXY</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
</dict>
</plist>
PLIST

# Sign the app (ignore if already signed)
codesign -s - MXF2PRXY.app || true

# Update icon cache
touch MXF2PRXY.app

echo "App built successfully"

# Launch the app
echo "Launching MXF2PRXY..."
open MXF2PRXY.app
