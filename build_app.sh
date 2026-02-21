#!/bin/bash
set -e

DYLIB_SRC="$(pwd)/ffmpeg-dylib/lib"
SIGNING_IDENTITY="3rd Party Mac Developer Application: Francis Capria (G85UV88266)"

# Quit the app if it's running
if pgrep -x "pxf" > /dev/null; then
    echo "Quitting running instance of pxf..."
    killall pxf 2>/dev/null || true
    sleep 0.5
fi

# Build
swift build

# Create app bundle structure
mkdir -p pxf.app/Contents/MacOS
mkdir -p pxf.app/Contents/Resources
mkdir -p pxf.app/Contents/Frameworks

# Copy binary
cp .build/debug/pxf pxf.app/Contents/MacOS/pxf

# =============================================================================
# Bundle all non-system dylibs into Contents/Frameworks/
# Recursively walks the dependency tree starting from the FFmpeg dylibs
# and rewrites all paths to @rpath (resolved via @executable_path/../Frameworks)
# =============================================================================
echo "=== Bundling shared libraries ==="

FRAMEWORKS="pxf.app/Contents/Frameworks"
rm -rf "$FRAMEWORKS"
mkdir -p "$FRAMEWORKS"

# Recursive function: copy a dylib and all its non-system deps into Frameworks/
bundle_dylib() {
    local lib_path="$1"
    local lib_name
    lib_name=$(basename "$lib_path")

    # Skip if already bundled
    [ -f "$FRAMEWORKS/$lib_name" ] && return

    # Skip system libraries and frameworks
    case "$lib_path" in
        /System/*|/usr/lib/*) return ;;
    esac

    # Skip if file doesn't exist
    [ ! -f "$lib_path" ] && echo "  WARNING: $lib_path not found" && return

    echo "  Bundling: $lib_name"
    cp "$lib_path" "$FRAMEWORKS/$lib_name"
    chmod 755 "$FRAMEWORKS/$lib_name"

    # Set install name ID to @rpath-relative
    install_name_tool -id "@rpath/$lib_name" "$FRAMEWORKS/$lib_name"

    # Walk this dylib's dependencies and recursively bundle them
    otool -L "$FRAMEWORKS/$lib_name" | awk '{print $1}' | tail -n +2 | while read -r dep; do
        case "$dep" in
            /System/*|/usr/lib/*) continue ;;          # system — skip
            @rpath/*) continue ;;                       # already @rpath — skip
            @executable_path/*) continue ;;             # already relative — skip
        esac

        local dep_name
        dep_name=$(basename "$dep")

        # Recursively bundle this dependency
        bundle_dylib "$dep"

        # Rewrite the reference in our bundled copy
        install_name_tool -change "$dep" "@rpath/$dep_name" "$FRAMEWORKS/$lib_name"
    done
}

# Start from the FFmpeg dylibs (real files only, not symlinks)
for dylib in "$DYLIB_SRC"/lib*.dylib; do
    [ -L "$dylib" ] && continue
    bundle_dylib "$dylib"
done

# Create SONAME symlinks (e.g., libavutil.59.dylib → libavutil.59.39.100.dylib)
# FFmpeg dylibs reference each other via major-version names, not full-version names
echo ""
echo "=== Creating version symlinks ==="
for dylib in "$FRAMEWORKS"/*.dylib; do
    [ -L "$dylib" ] && continue
    full_name=$(basename "$dylib")
    # Extract all referenced @rpath names that don't exist as files
    otool -L "$dylib" | awk '{print $1}' | grep "^@rpath/" | while read -r ref; do
        ref_name="${ref#@rpath/}"
        if [ ! -f "$FRAMEWORKS/$ref_name" ] && [ ! -L "$FRAMEWORKS/$ref_name" ]; then
            # Find the real file this short name should point to
            # e.g., libavutil.59.dylib → libavutil.59.39.100.dylib
            # Extract the lib prefix and major version
            match=$(ls "$FRAMEWORKS"/${ref_name%.dylib}.*.dylib 2>/dev/null | head -1)
            if [ -n "$match" ]; then
                match_name=$(basename "$match")
                echo "  Symlink: $ref_name → $match_name"
                (cd "$FRAMEWORKS" && ln -sf "$match_name" "$ref_name")
            fi
        fi
    done
done

# Also rewrite any remaining non-@rpath references inside already-bundled dylibs
# (catches deps that were bundled before their parent's reference was rewritten)
echo ""
echo "=== Fixing cross-references ==="
for dylib in "$FRAMEWORKS"/*.dylib; do
    [ -L "$dylib" ] && continue
    otool -L "$dylib" | awk '{print $1}' | tail -n +2 | while read -r dep; do
        case "$dep" in
            /System/*|/usr/lib/*|@rpath/*|@executable_path/*) continue ;;
        esac
        dep_name=$(basename "$dep")
        if [ -f "$FRAMEWORKS/$dep_name" ]; then
            install_name_tool -change "$dep" "@rpath/$dep_name" "$dylib"
            echo "  Fixed: $(basename $dylib) → @rpath/$dep_name"
        fi
    done
done

# Also ensure the main binary's Homebrew references are rewritten to @rpath
echo ""
echo "=== Fixing main binary references ==="
MAIN_BIN="pxf.app/Contents/MacOS/pxf"
otool -L "$MAIN_BIN" | awk '{print $1}' | tail -n +2 | while read -r dep; do
    case "$dep" in
        /System/*|/usr/lib/*|@rpath/*|@executable_path/*) continue ;;
    esac
    dep_name=$(basename "$dep")
    if [ -f "$FRAMEWORKS/$dep_name" ]; then
        install_name_tool -change "$dep" "@rpath/$dep_name" "$MAIN_BIN"
        echo "  Fixed: pxf → @rpath/$dep_name"
    fi
done

# Ensure @rpath is set (SPM usually adds it, but belt-and-suspenders)
if ! otool -l "$MAIN_BIN" | grep -q "@executable_path/../Frameworks"; then
    echo "  Adding @rpath to main binary"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MAIN_BIN"
fi

# =============================================================================
# Code sign (inside-out: dylibs first, then app bundle)
# =============================================================================
echo ""
echo "=== Code signing ==="
for dylib in "$FRAMEWORKS"/*.dylib; do
    [ -L "$dylib" ] && continue
    codesign --force --sign "$SIGNING_IDENTITY" "$dylib"
done
echo "  Signed $(ls "$FRAMEWORKS"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylibs"

# Copy icon and resources
cp AppIcon.icns pxf.app/Contents/Resources/
cp -f pfx_only.png pxf.app/Contents/Resources/ 2>/dev/null || true
cp -f watermark.png pxf.app/Contents/Resources/ 2>/dev/null || true

# Embed provisioning profile
cp pxf_App_Store.provisionprofile pxf.app/Contents/embedded.provisionprofile

# Bundle LGPL source materials (build script + patches for reproducible FFmpeg build)
LGPL_DIR="pxf.app/Contents/Resources/LGPL-Sources"
mkdir -p "$LGPL_DIR"
cp build_ffmpeg_dylib.sh "$LGPL_DIR/"
cp -R patches/ "$LGPL_DIR/patches/" 2>/dev/null || true
cp RELINKING.txt "$LGPL_DIR/"
echo "  Bundled LGPL source materials in Resources/LGPL-Sources/"

# Auto-increment build number
CURRENT_BUILD=0
if [ -f pxf.app/Contents/Info.plist ]; then
    CURRENT_BUILD=$(defaults read "$(pwd)/pxf.app/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 0)
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "Build number: $NEW_BUILD"

# Create Info.plist
cat > pxf.app/Contents/Info.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>pxf</string>
	<key>CFBundleIdentifier</key>
	<string>com.frankcapria.pxf</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>pxf</string>
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

# Sign the app bundle with sandbox entitlements (after dylibs are already signed)
codesign --force --sign "$SIGNING_IDENTITY" --entitlements pxf.entitlements pxf.app

# Update icon cache
touch pxf.app

# =============================================================================
# Verification
# =============================================================================
echo ""
echo "=== Verification ==="

echo ""
echo "--- Main binary @rpath references ---"
otool -L "$MAIN_BIN" | grep "@rpath"

echo ""
echo "--- Checking for remaining Homebrew paths ---"
FAIL=0
for f in "$MAIN_BIN" "$FRAMEWORKS"/*.dylib; do
    [ -L "$f" ] && continue
    bad=$(otool -L "$f" | grep "/opt/homebrew" || true)
    if [ -n "$bad" ]; then
        echo "WARN: $(basename $f) still has Homebrew refs:"
        echo "$bad"
        FAIL=1
    fi
done
[ $FAIL -eq 0 ] && echo "PASS: No Homebrew paths in any binary"

echo ""
echo "--- Frameworks contents ---"
ls -lh "$FRAMEWORKS"/*.dylib | awk '{print $5, $NF}'

echo ""
echo "--- Code signature ---"
codesign -vvv pxf.app 2>&1 | head -5

echo ""
echo "App built successfully"

# Launch the app
echo "Launching pxf..."
open pxf.app
