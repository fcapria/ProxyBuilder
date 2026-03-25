**pxf — Release Notes v1.1**

**UI Updates**
- Queue counter label renamed from "Items in queue:" to "In Queue:" with increased font size
- Added progress bar that tracks encoding completion per batch (updates after each file finishes)
- Added FLV to accepted input formats

**Codec Changes**
- MP4 output now supports all four codecs: H.264, H.265, ProRes Proxy, and DNxHR LB
- MXF output now offers ProRes Proxy and DNxHR LB only (removed legacy MPEG-2 option)
- Codec selection is now preserved when switching between output formats (e.g., selecting ProRes then switching from QuickTime to MXF keeps ProRes selected)

**Bug Fixes**
- Fixed MXF output producing 0-byte files: FFmpeg's MXF muxer cannot write ARRI RDD 55 data tracks, so data and subtitle track mapping is now excluded from the MXF remux step
- Fixed encoding hang when "Inside Source Folder" destination was selected for folders containing subdirectories: the file count included proxy subfolder contents but the encoder skipped them, leaving the queue stuck. pxf now blocks this configuration and alerts the user to select a different destination
- Fixed AVFoundation intermediate path failing on source files wider than 4096px: these files now bypass AVFoundation and go directly through FFmpeg
- Fixed codec popup resetting to the first item when switching output formats (e.g., switching to MXF would always select MPEG-2 regardless of prior selection)
