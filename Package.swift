// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MXFToQuickTime",
    platforms: [.macOS(.v13)],
    targets: [
        // C wrapper around ffmpeg static libraries
        .target(
            name: "CFFmpeg",
            path: "Sources/CFFmpeg",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../ffmpeg-static/include"),
            ],
            linkerSettings: [
                // FFmpeg static libs (order matters for symbol resolution)
                .unsafeFlags([
                    "-L./ffmpeg-static/lib",
                    "-L/opt/homebrew/lib",
                ]),
                // fftools (our patched ffmpeg_main entry point)
                .linkedLibrary("fftools"),
                // FFmpeg libraries (order: higher-level first)
                .linkedLibrary("avdevice"),
                .linkedLibrary("avfilter"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("swresample"),
                .linkedLibrary("swscale"),
                .linkedLibrary("avutil"),
                // Third-party codec/format libraries
                .linkedLibrary("aom"),
                .linkedLibrary("vpx"),
                .linkedLibrary("mp3lame"),
                .linkedLibrary("opus"),
                .linkedLibrary("snappy"),
                .linkedLibrary("theora"),
                .linkedLibrary("theoraenc"),
                .linkedLibrary("theoradec"),
                .linkedLibrary("vorbis"),
                .linkedLibrary("vorbisenc"),
                .linkedLibrary("ogg"),
                // Text rendering / subtitle libraries
                .linkedLibrary("ass"),
                .linkedLibrary("harfbuzz"),
                .linkedLibrary("freetype"),
                .linkedLibrary("fontconfig"),
                .linkedLibrary("fribidi"),
                .linkedLibrary("unibreak"),
                // Support libraries
                .linkedLibrary("png"),
                .linkedLibrary("brotlidec"),
                .linkedLibrary("brotlienc"),
                .linkedLibrary("brotlicommon"),
                // X11/SDL libraries (required by libavdevice; will be removed for App Store build)
                .linkedLibrary("SDL2"),
                .linkedLibrary("xcb"),
                .linkedLibrary("xcb-shm"),
                .linkedLibrary("xcb-shape"),
                .linkedLibrary("xcb-xfixes"),
                .linkedLibrary("X11"),
                .linkedLibrary("Xau"),
                .linkedLibrary("Xdmcp"),
                // System libraries
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedLibrary("xml2"),
                .linkedLibrary("bz2"),
                .linkedLibrary("lzma"),
                // Apple frameworks
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("OpenGL"),
                .linkedFramework("Security"),
                .linkedFramework("OpenCL"),
                .linkedFramework("Metal"),
                .linkedFramework("IOKit"),
            ]
        ),
        // Main application target
        .executableTarget(
            name: "MXFToQuickTime",
            dependencies: ["CFFmpeg"],
            path: "Sources",
            exclude: ["CFFmpeg"]
        ),
    ]
)
