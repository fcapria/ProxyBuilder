#!/bin/bash
set -e

# Build LGPL-compliant FFmpeg as SHARED libraries (.dylib) for App Store distribution
# FFmpeg dylibs link against Homebrew shared libs at build time; the recursive
# bundling of all non-system dylibs into Contents/Frameworks/ is handled by build_app.sh
#
# Output: ffmpeg-dylib/lib/ containing:
#   - libavcodec.*.dylib, libavformat.*.dylib, libavfilter.*.dylib
#   - libswscale.*.dylib, libswresample.*.dylib, libavutil.*.dylib
#   - libfftools.a (statically linked app-specific patched fftools)

FFMPEG_VERSION="7.1.1"
PREFIX="$(pwd)/ffmpeg-dylib"
BUILD_DIR="$(pwd)/ffmpeg-build"

echo "=== Building SHARED LGPL FFmpeg ${FFMPEG_VERSION} ==="
echo "Install prefix: $PREFIX"

# Detect Homebrew prefix
BREW_PREFIX=$(brew --prefix)
echo "Homebrew prefix: $BREW_PREFIX"

# Install dependencies via Homebrew
echo ""
echo "=== Installing dependencies ==="
brew install \
    aom \
    harfbuzz \
    lame \
    opus \
    snappy \
    theora \
    libvorbis \
    fontconfig \
    freetype \
    libass

# =============================================================================
# Download FFmpeg source
# =============================================================================
echo ""
echo "=== Downloading FFmpeg ${FFMPEG_VERSION} ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
    curl -L -O "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

# Always extract fresh for patching
if [ -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    echo "Removing old source directory..."
    rm -rf "ffmpeg-${FFMPEG_VERSION}"
fi
tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"

cd "ffmpeg-${FFMPEG_VERSION}"

# =============================================================================
# Apply library patches (identical to build_ffmpeg_static.sh)
# =============================================================================
echo ""
echo "=== Applying library patches ==="

# 1. Rename main() to ffmpeg_main() in ffmpeg.c
sed -i '' 's/^int main(int argc, char \*\*argv)$/int ffmpeg_main(int argc, char **argv)/' fftools/ffmpeg.c
echo "  Renamed main() -> ffmpeg_main()"

# 2. Add global state reset at top of ffmpeg_main(), after local variable declarations
sed -i '' '/^    BenchmarkTimeStamps ti;$/a\
\
    /* Reset global state from previous invocation (library mode) */\
    nb_input_files = 0;\
    nb_output_files = 0;\
    nb_filtergraphs = 0;\
    nb_decoders = 0;\
    received_sigterm = 0;\
    received_nb_signals = 0;\
    atomic_store(\&transcode_init_done, 0);\
    ffmpeg_exited = 0;\
    copy_ts_first_pts = AV_NOPTS_VALUE;\
    stdin_interaction = 0;  /* No TTY interaction in library mode */
' fftools/ffmpeg.c
echo "  Added global state reset"

# 3. Defang signal handler — remove exit(123), just return
sed -i '' '/received_nb_signals > 3/,/exit(123);/{
    /exit(123);/c\
        /* In library mode, do not exit the host process */\
        return;
}' fftools/ffmpeg.c
# Also remove the write() call and its error check that precede exit
sed -i '' '/Received > 3 system signals, hard exiting/d' fftools/ffmpeg.c
sed -i '' '/if (ret < 0) { \/\* Do nothing \*\/ };/d' fftools/ffmpeg.c
echo "  Defanged signal handler (removed exit(123))"

# 4. Comment out term_init() in ffmpeg_opt.c — don't hijack host app signals/TTY
sed -i '' 's|    term_init();|    /* term_init(); */ /* Disabled in library mode */|' fftools/ffmpeg_opt.c
echo "  Disabled term_init() in ffmpeg_opt.c"

# 5. Reset option globals at top of ffmpeg_parse_options
sed -i '' '/^    memset(\&octx, 0, sizeof(octx));$/a\
\
    /* Reset option globals (library mode) */\
    file_overwrite = 0;\
    no_file_overwrite = 0;\
    ignore_unknown_streams = 0;\
    copy_unknown_streams = 0;\
    recast_media = 0;\
    do_benchmark = 0;\
    do_benchmark_all = 0;\
    do_hex_dump = 0;\
    do_pkt_dump = 0;\
    copy_ts = 0;\
    start_at_zero = 0;\
    copy_tb = -1;\
    debug_ts = 0;\
    exit_on_error = 0;\
    abort_on_flags = 0;\
    print_stats = -1;\
    max_error_rate = 2.0/3;\
    filter_complex_nbthreads = 0;\
    vstats_version = 2;\
    auto_conversion_filters = 1;\
    stats_period = 500000;\
    hide_banner = 0;
' fftools/ffmpeg_opt.c
echo "  Added option globals reset"

# Verify patches applied
echo ""
echo "Verifying patches..."
grep -q "ffmpeg_main" fftools/ffmpeg.c && echo "  OK: ffmpeg_main found" || echo "  FAIL: ffmpeg_main not found"
grep -q "nb_input_files = 0" fftools/ffmpeg.c && echo "  OK: global reset found" || echo "  FAIL: global reset not found"
echo "Patches applied successfully"

# =============================================================================
# Configure FFmpeg — SHARED, LGPL only, no programs, no avdevice
# =============================================================================
echo ""
echo "=== Configuring FFmpeg (SHARED, LGPL) ==="

# Set up pkg-config to find Homebrew libraries
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/libass/lib/pkgconfig:${BREW_PREFIX}/opt/freetype/lib/pkgconfig:${BREW_PREFIX}/opt/fontconfig/lib/pkgconfig:${BREW_PREFIX}/opt/harfbuzz/lib/pkgconfig"
export LDFLAGS="-L${BREW_PREFIX}/lib"
export CFLAGS="-I${BREW_PREFIX}/include"

./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-avdevice \
    --enable-libaom \
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
    --disable-xlib \
    --extra-cflags="-I${BREW_PREFIX}/include" \
    --extra-ldflags="-L${BREW_PREFIX}/lib"

# =============================================================================
# Build shared libraries
# =============================================================================
echo ""
echo "=== Building FFmpeg shared libraries ==="
make -j$(sysctl -n hw.ncpu)

# Install to prefix
echo ""
echo "=== Installing to $PREFIX ==="
make install

# =============================================================================
# Fix install names: absolute paths → @rpath
# FFmpeg dylibs reference each other via absolute $PREFIX paths; rewrite to @rpath
# Homebrew dylib references are left as-is — build_app.sh handles bundling those
# =============================================================================
echo ""
echo "=== Fixing FFmpeg dylib install names ==="

for dylib in "$PREFIX"/lib/lib*.dylib; do
    # Skip symlinks — only process real files
    [ -L "$dylib" ] && continue

    basename_full=$(basename "$dylib")
    echo "  Processing: $basename_full"

    # Change install name ID to @rpath-relative
    install_name_tool -id "@rpath/$basename_full" "$dylib"

    # Change references to sibling FFmpeg dylibs to @rpath-relative
    otool -L "$dylib" | awk '{print $1}' | tail -n +2 | while read -r dep; do
        case "$dep" in
            "$PREFIX"/lib/*)
                dep_basename=$(basename "$dep")
                install_name_tool -change "$dep" "@rpath/$dep_basename" "$dylib"
                echo "    Rewrote: $dep → @rpath/$dep_basename"
                ;;
        esac
    done
done

# =============================================================================
# Build libfftools.a (identical to static build)
# =============================================================================
echo ""
echo "=== Building libfftools.a ==="

FFTOOLS_SRCS="fftools/ffmpeg.c fftools/ffmpeg_dec.c fftools/ffmpeg_demux.c \
    fftools/ffmpeg_enc.c fftools/ffmpeg_filter.c fftools/ffmpeg_hw.c \
    fftools/ffmpeg_mux.c fftools/ffmpeg_mux_init.c fftools/ffmpeg_opt.c \
    fftools/ffmpeg_sched.c fftools/objpool.c fftools/sync_queue.c \
    fftools/thread_queue.c fftools/cmdutils.c fftools/opt_common.c"

FFTOOLS_SRC_PATH="$(pwd)"

mkdir -p fftools_objs
for src in $FFTOOLS_SRCS; do
    obj="fftools_objs/$(basename ${src%.c}.o)"
    echo "  Compiling: $src"
    cc -c \
        -D_ISOC11_SOURCE -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DPIC -DZLIB_CONST \
        -I"$FFTOOLS_SRC_PATH/compat/dispatch_semaphore" \
        -I"$FFTOOLS_SRC_PATH/compat/stdbit" \
        -I. -Ifftools -I"$PREFIX/include" \
        -I"${BREW_PREFIX}/include" \
        -std=c17 -O3 -pthread \
        "$src" -o "$obj"
done

# Bundle into static library
ar rcs "$PREFIX/lib/libfftools.a" fftools_objs/*.o
echo "  Created libfftools.a"

# Copy fftools headers needed by the wrapper
mkdir -p "$PREFIX/include/fftools"
cp fftools/ffmpeg.h "$PREFIX/include/fftools/"
cp fftools/ffmpeg_sched.h "$PREFIX/include/fftools/"
cp fftools/cmdutils.h "$PREFIX/include/fftools/"

# =============================================================================
# Verification
# =============================================================================
echo ""
echo "=== Verification ==="

echo ""
echo "--- Checking install name IDs use @rpath ---"
FAIL=0
for f in "$PREFIX"/lib/lib*.dylib; do
    [ -L "$f" ] && continue
    id=$(otool -D "$f" | tail -1)
    if echo "$id" | grep -q "@rpath"; then
        echo "PASS: $(basename $f) → $id"
    else
        echo "FAIL: $(basename $f) → $id (expected @rpath/...)"
        FAIL=1
    fi
done

echo ""
echo "--- Checking libavdevice is NOT present ---"
if ls "$PREFIX"/lib/libavdevice* 2>/dev/null; then
    echo "FAIL: libavdevice should not exist"
    FAIL=1
else
    echo "PASS: no libavdevice"
fi

echo ""
echo "--- Checking libfftools.a ---"
if [ -f "$PREFIX/lib/libfftools.a" ]; then
    echo "PASS: libfftools.a exists ($(wc -c < "$PREFIX/lib/libfftools.a" | tr -d ' ') bytes)"
else
    echo "FAIL: libfftools.a not found"
    FAIL=1
fi

echo ""
echo "--- Full dylib dependency listing ---"
echo "(Homebrew paths here are expected — build_app.sh will bundle them)"
for f in "$PREFIX"/lib/lib*.dylib; do
    [ -L "$f" ] && continue
    echo ""
    echo "$(basename $f):"
    otool -L "$f" | tail -n +2
done

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "=== BUILD SUCCESSFUL ==="
else
    echo ""
    echo "=== BUILD COMPLETED WITH WARNINGS — Review above ==="
fi

echo ""
echo "Dylibs installed to: $PREFIX/lib/"
ls -lh "$PREFIX"/lib/lib*.dylib | grep -v "^l"
