# MXF2PRXY — Build 66

## Bug Fixes

### Panasonic P2 MXF Conversion

MXF-to-QuickTime conversions now succeed for Panasonic P2 camera originals. Previously, P2 files with data-wrapped audio streams (codec "none") caused ffmpeg to fail with "Could not find tag for codec none" when writing to MOV. The app no longer attempts to copy incompatible data streams into the QuickTime container.

**Note:** P2 MXF files store audio references as data tracks that ffmpeg cannot decode. Proxies from these sources will be video-only. This is an ffmpeg limitation, not a bug in MXF2PRXY.

### Build Script Code Signing

Bundled ffmpeg and its shared libraries are now re-signed after `install_name_tool` modifies their load paths. Previously, the signature invalidation could cause macOS to reject the bundled binaries.

## UI Fixes

### Select Button Appearance

The **Select Files or Folders...** button now returns to its correct appearance after dismissing the file picker dialog. Previously, the button reverted to a mismatched color instead of its original styling.

### Encoding Path Reset

The drop zone now clears the "Encoded to" path label after all queued jobs complete, returning to its idle state. When a custom destination is set, the label reverts to "Will encode to" instead of showing the last completed path.

### Dark Mode Link Color

The encoding path link in dark mode now uses the orange accent color, matching the drop zone border, instead of green.

## Installation

1. Download **MXF2PRXY.app.zip** from the release assets below.
2. Unzip and move **MXF2PRXY.app** to your Applications folder.
3. Right-click the app and select **Open** on first launch to bypass Gatekeeper.
