#!/bin/bash
set -e

# Build LGPL-compliant FFmpeg from source
# Excludes all GPL-only components (no libx264, libx265, frei0r)
# All included libraries are LGPL, BSD, MIT, or similarly permissive

FFMPEG_VERSION="7.1.1"
PREFIX="$(pwd)/ffmpeg-lgpl"
BUILD_DIR="$(pwd)/ffmpeg-build"

echo "=== Building LGPL-compliant FFmpeg ${FFMPEG_VERSION} ==="
echo "Install prefix: $PREFIX"

# Detect Homebrew prefix
BREW_PREFIX=$(brew --prefix)
echo "Homebrew prefix: $BREW_PREFIX"

# Install LGPL/BSD/MIT-compatible dependencies via Homebrew
echo ""
echo "=== Installing dependencies ==="
brew install \
    aom \
    dav1d \
    harfbuzz \
    lame \
    opus \
    snappy \
    theora \
    libvorbis \
    libvpx \
    fontconfig \
    freetype \
    libass

# Download FFmpeg source
echo ""
echo "=== Downloading FFmpeg ${FFMPEG_VERSION} ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
    curl -L -O "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

cd "ffmpeg-${FFMPEG_VERSION}"

# Set up pkg-config to find Homebrew libraries
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/libass/lib/pkgconfig:${BREW_PREFIX}/opt/freetype/lib/pkgconfig:${BREW_PREFIX}/opt/fontconfig/lib/pkgconfig:${BREW_PREFIX}/opt/harfbuzz/lib/pkgconfig"
export LDFLAGS="-L${BREW_PREFIX}/lib"
export CFLAGS="-I${BREW_PREFIX}/include"

# Configure FFmpeg — LGPL only (no --enable-gpl, no libx264, no libx265, no frei0r)
echo ""
echo "=== Configuring FFmpeg (LGPL) ==="
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --enable-libaom \
    --enable-libdav1d \
    --enable-libharfbuzz \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libsnappy \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libfontconfig \
    --enable-libfreetype \
    --enable-libass \
    --enable-demuxer=dash \
    --enable-opencl \
    --enable-audiotoolbox \
    --enable-videotoolbox \
    --disable-htmlpages \
    --extra-cflags="-I${BREW_PREFIX}/include" \
    --extra-ldflags="-L${BREW_PREFIX}/lib"

# Build
echo ""
echo "=== Building FFmpeg ==="
make -j$(sysctl -n hw.ncpu)

# Install to prefix
echo ""
echo "=== Installing to $PREFIX ==="
make install

echo ""
echo "=== Build complete ==="
echo "FFmpeg binary: $PREFIX/bin/ffmpeg"
echo ""
echo "Verify LGPL compliance:"
"$PREFIX/bin/ffmpeg" -version 2>&1 | head -5
echo ""
echo "License should say LGPL, not GPL."
echo ""
echo "To use in build_app.sh, set:"
echo "  export FFMPEG_LGPL=$PREFIX/bin/ffmpeg"
