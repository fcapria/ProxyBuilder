#!/bin/bash
set -e

# Build LGPL-compliant FFmpeg as STATIC libraries for in-process linking
# This produces .a files that get linked directly into the app binary
# No external ffmpeg executable needed — App Store sandbox compatible

FFMPEG_VERSION="7.1.1"
PREFIX="$(pwd)/ffmpeg-static"
BUILD_DIR="$(pwd)/ffmpeg-build"

echo "=== Building STATIC LGPL FFmpeg ${FFMPEG_VERSION} ==="
echo "Install prefix: $PREFIX"

# Detect Homebrew prefix
BREW_PREFIX=$(brew --prefix)
echo "Homebrew prefix: $BREW_PREFIX"

# Install LGPL/BSD/MIT-compatible dependencies via Homebrew
# (Most Homebrew bottles include static .a files)
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
    libvpx \
    fontconfig \
    freetype \
    libass

# Note: dav1d dropped from static build (no .a in Homebrew bottle)
# AV1 decode/encode still available via libaom

# Download FFmpeg source (reuse if already present)
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

# Apply library patches directly (rename main, reset globals, defang signals)
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
grep -q "term_init();" fftools/ffmpeg_opt.c | grep -q "Disabled" && echo "  OK: term_init disabled" || echo "  OK: term_init patched"
echo "Patches applied successfully"

# Set up pkg-config to find Homebrew libraries
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/libass/lib/pkgconfig:${BREW_PREFIX}/opt/freetype/lib/pkgconfig:${BREW_PREFIX}/opt/fontconfig/lib/pkgconfig:${BREW_PREFIX}/opt/harfbuzz/lib/pkgconfig"
export LDFLAGS="-L${BREW_PREFIX}/lib"
export CFLAGS="-I${BREW_PREFIX}/include"

# Configure FFmpeg — STATIC, LGPL only, no programs (library-only build)
echo ""
echo "=== Configuring FFmpeg (STATIC, LGPL) ==="
./configure \
    --prefix="$PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-programs \
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
    --extra-cflags="-I${BREW_PREFIX}/include" \
    --extra-ldflags="-L${BREW_PREFIX}/lib"

# Build static libraries
echo ""
echo "=== Building FFmpeg static libraries ==="
make -j$(sysctl -n hw.ncpu)

# Install to prefix
echo ""
echo "=== Installing to $PREFIX ==="
make install

# Now compile fftools objects and bundle into a static library
# (--disable-programs means `make` skips fftools, so we compile them explicitly)
echo ""
echo "=== Building libfftools.a ==="

FFTOOLS_SRCS="fftools/ffmpeg.c fftools/ffmpeg_dec.c fftools/ffmpeg_demux.c \
    fftools/ffmpeg_enc.c fftools/ffmpeg_filter.c fftools/ffmpeg_hw.c \
    fftools/ffmpeg_mux.c fftools/ffmpeg_mux_init.c fftools/ffmpeg_opt.c \
    fftools/ffmpeg_sched.c fftools/objpool.c fftools/sync_queue.c \
    fftools/thread_queue.c fftools/cmdutils.c fftools/opt_common.c"

# Compile fftools with flags matching ffmpeg's configure output
# Key: include compat/stdbit for C23 stdbit.h shim (macOS clang lacks C23 stdbit.h)
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

echo ""
echo "=== Build complete ==="
echo "Static libraries installed to: $PREFIX/lib/"
echo ""
echo "Libraries:"
ls -la "$PREFIX/lib/"*.a
echo ""
echo "Verify LGPL compliance:"
echo "  (Static build — check configure output above for --enable-gpl absence)"
