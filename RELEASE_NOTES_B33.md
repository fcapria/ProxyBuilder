# MXF2PRXY — Build 33

## What's New

### MP4 Output

MXF2PRXY now supports MPEG-4 (.mp4) output alongside QuickTime (.mov) and MXF (.mxf). Select MP4 from the output format dropdown to generate lightweight proxies ideal for web review, client delivery, or any workflow that benefits from broad device compatibility.

Available codecs for MP4:
- H.265 (HEVC)
- H.264

### H.265 (HEVC) Codec

A new H.265 encoding option is available for both QuickTime and MP4 output. H.265 delivers roughly the same visual quality as H.264 at significantly lower bitrates, producing smaller proxy files without sacrificing usability.

- **Hardware-accelerated** via VideoToolbox on supported Macs (up to 4096px wide)
- **Automatic software fallback** (libx265) for sources that exceed the hardware encoder's resolution limit
- 10-bit encoding when using hardware acceleration

### Codec Selection

The output format and codec dropdowns now work together. Choosing an output format automatically filters the codec list to compatible options:

| Codec | QuickTime | MP4 | MXF |
|---|---|---|---|
| H.265 | Yes | Yes | — |
| H.264 | Yes | Yes | — |
| ProRes Proxy | Yes | — | Yes |
| DNxHR LB | Yes | — | Yes |
| MPEG-2 | — | — | Yes |

Your codec selection is remembered between sessions.

### UI Enhancements

- **Persistent destination selector** — Set a custom output folder once and it stays put across sessions. No more per-drop folder picker dialog.
- **Clickable output path** — The destination path displayed below the drop zone is now an interactive link. Click it to open the folder in Finder.
- **Theme-aware styling** — The destination link adapts to light and dark mode.

## Installation

1. Download **MXF2PRXY.app.zip** from the release assets below.
2. Unzip and move **MXF2PRXY.app** to your Applications folder.
3. Right-click the app and select **Open** on first launch to bypass Gatekeeper.
