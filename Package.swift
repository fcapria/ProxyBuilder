// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pxf",
    platforms: [.macOS(.v13)],
    targets: [
        // C wrapper around ffmpeg — calls ffmpeg_main() in libfftools.a,
        // which resolves symbols from FFmpeg dylibs at runtime
        .target(
            name: "CFFmpeg",
            path: "Sources/CFFmpeg",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../ffmpeg-dylib/include"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L./ffmpeg-dylib/lib",
                    "-L/opt/homebrew/lib",
                    // Tell the binary to look for dylibs in Contents/Frameworks/
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
                // fftools (statically linked — our patched ffmpeg_main entry point)
                .linkedLibrary("fftools"),
                // FFmpeg shared libraries (resolved at runtime via @rpath)
                .linkedLibrary("avfilter"),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("swresample"),
                .linkedLibrary("swscale"),
                .linkedLibrary("avutil"),
                // System libraries (needed by libfftools.a static code)
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
            name: "pxf",
            dependencies: ["CFFmpeg"],
            path: "Sources",
            exclude: ["CFFmpeg"]
        ),
    ]
)
