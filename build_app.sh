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

# Use LGPL-built ffmpeg (falls back to Homebrew if LGPL build not found)
LGPL_FFMPEG="$(pwd)/ffmpeg-lgpl/bin/ffmpeg"
HOMEBREW_FFMPEG=$(which ffmpeg 2>/dev/null || echo "")

if [ -n "$FFMPEG_LGPL" ] && [ -f "$FFMPEG_LGPL" ]; then
    FFMPEG_SRC="$FFMPEG_LGPL"
    echo "Using ffmpeg from FFMPEG_LGPL env: $FFMPEG_SRC"
elif [ -f "$LGPL_FFMPEG" ]; then
    FFMPEG_SRC="$LGPL_FFMPEG"
    echo "Using LGPL-built ffmpeg: $FFMPEG_SRC"
elif [ -n "$HOMEBREW_FFMPEG" ] && [ -f "$HOMEBREW_FFMPEG" ]; then
    FFMPEG_SRC="$HOMEBREW_FFMPEG"
    echo "WARNING: Using Homebrew ffmpeg (may be GPL). Build LGPL version with: ./build_ffmpeg_lgpl.sh"
else
    echo "ERROR: No ffmpeg found. Build LGPL version with: ./build_ffmpeg_lgpl.sh"
    echo "  Or install Homebrew ffmpeg with: brew install ffmpeg"
    exit 1
fi

if [ -f "$FFMPEG_SRC" ]; then
    cp "$FFMPEG_SRC" MXF2PRXY.app/Contents/MacOS/ffmpeg

    # Clean old frameworks and bundle fresh shared libraries
    LIBS_DIR="MXF2PRXY.app/Contents/Frameworks"
    rm -rf "$LIBS_DIR"
    mkdir -p "$LIBS_DIR"
    FFMPEG_BIN="MXF2PRXY.app/Contents/MacOS/ffmpeg"

    # Copy non-system dylibs and rewrite paths
    copy_and_rewrite_deps() {
        local binary="$1"
        otool -L "$binary" | awk '{print $1}' | tail -n +2 | while read -r lib; do
            # Skip system libraries and self-references
            case "$lib" in
                /System/*|/usr/lib/*|@*) continue ;;
            esac
            local libname
            libname=$(basename "$lib")
            if [ ! -f "$LIBS_DIR/$libname" ]; then
                echo "  Bundling: $libname"
                cp "$lib" "$LIBS_DIR/$libname"
                chmod 755 "$LIBS_DIR/$libname"
                # Recursively handle dependencies of this library
                copy_and_rewrite_deps "$LIBS_DIR/$libname"
            fi
            # Rewrite the reference in the binary
            install_name_tool -change "$lib" "@executable_path/../Frameworks/$libname" "$binary" 2>/dev/null || true
        done
    }

    echo "Bundling ffmpeg shared libraries..."
    copy_and_rewrite_deps "$FFMPEG_BIN"

    # Also rewrite id and deps inside each bundled dylib
    for dylib in "$LIBS_DIR"/*.dylib; do
        libname=$(basename "$dylib")
        install_name_tool -id "@executable_path/../Frameworks/$libname" "$dylib" 2>/dev/null || true
        otool -L "$dylib" | awk '{print $1}' | tail -n +2 | while read -r lib; do
            case "$lib" in
                /System/*|/usr/lib/*|@*) continue ;;
            esac
            local depname
            depname=$(basename "$lib")
            install_name_tool -change "$lib" "@executable_path/../Frameworks/$depname" "$dylib" 2>/dev/null || true
        done
    done
    echo "Bundled $(ls "$LIBS_DIR"/*.dylib 2>/dev/null | wc -l | tr -d ' ') shared libraries"

    # Re-sign all modified binaries (install_name_tool invalidates signatures)
    echo "Re-signing bundled libraries..."
    for dylib in "$LIBS_DIR"/*.dylib; do
        codesign --force --sign - "$dylib"
    done
    codesign --force --sign - "$FFMPEG_BIN"
fi

# Copy icon and resources
cp AppIcon.icns MXF2PRXY.app/Contents/Resources/
cp -f MXF2Prxy-logo.png MXF2PRXY.app/Contents/Resources/ 2>/dev/null || true
cp -f watermark.png MXF2PRXY.app/Contents/Resources/ 2>/dev/null || true

# Auto-increment build number
CURRENT_BUILD=0
if [ -f MXF2PRXY.app/Contents/Info.plist ]; then
    CURRENT_BUILD=$(defaults read "$(pwd)/MXF2PRXY.app/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 0)
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "Build number: $NEW_BUILD"

# Create Info.plist
cat > MXF2PRXY.app/Contents/Info.plist << PLIST
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
	<string>${NEW_BUILD}</string>
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
