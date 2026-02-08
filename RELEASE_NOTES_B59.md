# MXF2PRXY — Build 60

## What's New

### Watermark Settings Window

The inline watermark dropdown has been replaced with a dedicated **Watermark Settings** window, accessible via the **Set...** button next to the "Apply watermark" checkbox. From this window you can:

- **Manage a watermark library** — Add, rename, and delete watermark images. A bundled default watermark is always available.
- **Use custom text** — Enter up to 48 characters of custom watermark text (e.g., "Proxy - Not for distribution") as an alternative to an image watermark.
- **Switch between modes** — Toggle between library image and custom text with radio buttons. Changes take effect immediately.

### Proportional Watermark Scaling

Watermark images now scale proportionally to the video frame instead of using a fixed pixel size:

- **Height** scales to 15% of the video height (minimum 160px)
- **Padding** is 5% from the right edge and 5% from the bottom edge
- Watermarks look consistent regardless of whether the source is 720p, 1080p, or 4K

### Anamorphic Watermark Correction

Watermarks on anamorphic footage (non-square pixel aspect ratio) are no longer distorted. MXF2PRXY now detects the Display Aspect Ratio from the source and pre-compensates the watermark width so it appears correctly when the player applies the anamorphic stretch.

### Application Menu

The MXF2PRXY menu now includes standard macOS items:

- **Hide MXF2PRXY** (Cmd+H)
- **Hide Others** (Cmd+Opt+H)
- **Show All**

### UI Polish

- Repositioned logo and "Select Files or Folders..." button for improved layout
- Custom watermark text is now saved automatically when closing the settings window

## Installation

1. Download **MXF2PRXY.app.zip** from the release assets below.
2. Unzip and move **MXF2PRXY.app** to your Applications folder.
3. Right-click the app and select **Open** on first launch to bypass Gatekeeper.
