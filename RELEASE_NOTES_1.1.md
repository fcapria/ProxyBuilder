**pxf — Release Notes v1.1**

**UI Updates**
- Queue counter label renamed from "Items in queue:" to "In Queue:" with increased font size
- Added progress bar that tracks encoding completion per batch (updates as each file finishes)
- Added FLV to accepted input formats

**Codec Changes**
- MP4 output now supports all four codecs: H.264, H.265, ProRes Proxy, and DNxHR LB
- Removed legacy MPEG-2 option from MXF output offers ProRes Proxy and DNxHR LB 
- Codec selection is now preserved when switching between output formats when possible

**Bug Fixes**
- FFFmpeg's MXF muxer cannot write ARRI RDD 55 data tracks, so data and subtitle track mapping is now excluded from the MXF remux step
- Fixed encoding hang when "Inside Source Folder" destination was selected for folders containing subdirectories. pxf now blocks that configuration and alerts the user to select a different destination
- Fixed AVFoundation intermediate path failing on source files wider than 4096px: these files now bypass AVFoundation 
