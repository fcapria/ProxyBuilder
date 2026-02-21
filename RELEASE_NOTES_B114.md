**MXF2Prxy — Release Notes (since Build 68)**

**LGPL Compliance & Licensing**
- Removed all GPL-licensed code (x264, x265, fdk-aac); encoding now uses Apple VideoToolbox hardware encoders exclusively
- Rebuilt FFmpeg with LGPL-only configuration
- Switched FFmpeg from static to dynamic linking (.dylib), satisfying LGPL §6(b) re-linking requirements
- Added RELINKING.txt with step-by-step instructions for replacing LGPL libraries
- Added About window with full LGPL attribution notices, source code offer, and re-linking instructions

**App Store Preparation**
- Added App Sandbox with entitlements (file access, security-scoped bookmarks)
- Configured code signing with "3rd Party Mac Developer Application" certificate
- Embedded provisioning profile for App Store distribution
- Registered bundle identifier: com.frankcapria.mxf2prxy

**Destination Selector Rework**
- On first launch, Dest. shows "-Choose-" with two options: "Inside Source Folder" and "Select..."
- Selection persists across launches via UserDefaults and security-scoped bookmarks
- Proxy files are created inside the source folder in a "[folder name] proxies" subfolder
- Destination path displayed below the Dest. popup in the same style as the LUT filename label

**Build System**
- Added build_ffmpeg_dylib.sh for shared library builds
- Added build_ffmpeg_static.sh and build_ffmpeg_lgpl.sh
- Added CFFmpeg wrapper module for Swift Package Manager integration
- Updated build_app.sh with dylib bundling, inside-out code signing, and entitlements
