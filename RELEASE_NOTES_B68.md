# MXF2PRXY — Build 68

## New Feature

### Half-Size Proxy Support

A new **Size** dropdown has been added to the main window (below Codec) with two options: **Full** and **Half**. When Half is selected, proxies are encoded at half resolution — for example, 3840x2160 source footage produces 1920x1080 proxies, and 4448x1856 produces 2224x928.

Half-size scaling uses ffmpeg's bicubic scaler with even-dimension rounding to ensure codec compatibility. The setting persists across sessions.

All processing paths are supported:
- QuickTime (.mov) output from MXF and MOV sources
- MPEG-4 (.mp4) output
- MXF output
- All watermark modes (image, custom text, none)
- LUT application

### Improved Hardware Encoding for Half-Size Output

The hardware encoder eligibility check now considers the output dimensions rather than the input dimensions. Sources wider than 4096 pixels (such as ARRI Open Gate at 4448px) that previously fell back to software encoding (libx265) now use VideoToolbox when half-size scaling brings them within the hardware encoder's limits. This results in approximately 30% faster encoding for these sources.

## Housekeeping

### Source Directory Rename

The source directory has been renamed from `HelloApp/` to `Sources/`, following Swift Package Manager conventions. The unused default template file `Sources/MXFToQuickTime/MXFToQuickTime.swift` has been removed.

## Installation

1. Download **MXF2PRXY.app.zip** from the release assets below.
2. Unzip and move **MXF2PRXY.app** to your Applications folder.
3. Right-click the app and select **Open** on first launch to bypass Gatekeeper.
