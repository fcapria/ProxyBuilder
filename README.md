# MXF2PRXY

A macOS app designed to streamline the creation of on-set dailies and edit proxies from professional video formats.

## Features

- **Multiple Format Support**: Process QuickTime and MXF files
- **Dual Output Options**:
  - QuickTime H.264 proxies (optimized for Adobe Premiere)
  - MXF MPEG-2 proxies for broadcast workflows
- **LUT Support**: Apply 3D LUTs (.cube format) for color grading
- **Watermarking**: Add custom watermarks to proxies
- **Batch Processing**: Process multiple files simultaneously
- **Metadata Preservation**: Maintains timecode, audio tracks, and data tracks
- **Adobe Premiere Compatible**: Preserves audio track IDs for seamless proxy workflows

## Installation

### For End Users (Recommended)

1. Download the latest `MXF2PRXY.app.zip` from the [Releases](https://github.com/fcapria/ProxyBuilder/releases) page
2. Unzip the file
3. Move `MXF2PRXY.app` to your Applications folder
4. Right-click the app and select "Open" (first launch only, to bypass Gatekeeper)

### For Developers (Building from Source)

#### Requirements
- macOS 10.15 or later
- Xcode Command Line Tools

#### Build Steps

1. Install Xcode Command Line Tools (if not already installed):
   ```bash
   xcode-select --install
   ```

2. Clone the repository:
   ```bash
   git clone https://github.com/fcapria/ProxyBuilder.git
   cd ProxyBuilder
   ```

3. Add required resource files to the project directory:
   - `AppIcon.icns` - Application icon
   - `watermark.png` - Optional watermark image
   - `MXF2Prxy-logo.png` - Optional logo image

4. Build and launch:
   ```bash
   ./build_app.sh
   ```

The build script will:
- Download a static ffmpeg binary automatically
- Compile the Swift code
- Create the app bundle
- Copy all resources
- Launch the app

## Usage

1. Launch MXF2PRXY
2. Select output format (QuickTime or MXF)
3. Drag and drop video files onto the drop zone
4. Select an output folder for the proxies
5. Files will be processed automatically

### Optional Settings

- **LUT Management**: Settings → Manage LUTs to add .cube LUT files
- **Output Format**: Toggle between QuickTime (.mov) and MXF (.mxf)

## Technical Details

- Built with Swift and AVFoundation
- Uses ffmpeg for advanced video processing
- Supports multi-channel audio preservation
- Maintains professional metadata (timecode, data tracks)

## License

MIT License - Feel free to use and modify for your projects.

## Contributing

Issues and pull requests are welcome on the [GitHub repository](https://github.com/fcapria/ProxyBuilder).