import AppKit
import AVFoundation

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

class OrangeButton: NSButton {
    let orangeColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0)
    private var isMouseDown = false
    
    override func awakeFromNib() {
        super.awakeFromNib()
        DispatchQueue.main.async { [weak self] in
            self?.setButtonDefault()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        updateButtonAppearance()
        super.mouseDown(with: event)
        isMouseDown = false
        updateButtonAppearance()
    }
    
    private func setButtonDefault() {
        self.bezelColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.darkGray]
        self.attributedTitle = NSAttributedString(string: self.title, attributes: attrs)
    }
    
    private func updateButtonAppearance() {
        if isMouseDown {
            self.bezelColor = orangeColor
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]
            self.attributedTitle = NSAttributedString(string: self.title, attributes: attrs)
        } else {
            setButtonDefault()
        }
    }
}

class DropView: NSView {
    var dropDelegate: DropViewDelegate?
    var isDropEnabled: Bool = true
    private let filenamePasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private let urlPasteboardType = NSPasteboard.PasteboardType.URL
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL, filenamePasteboardType, urlPasteboardType])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL, filenamePasteboardType, urlPasteboardType])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isDropEnabled else { return [] }
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        return containsAcceptableItem(urls) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isDropEnabled else { return [] }
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        return containsAcceptableItem(urls) ? .copy : []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isDropEnabled else { return false }
        let urls = extractFileURLs(from: sender.draggingPasteboard)

        guard !urls.isEmpty else {
            return false
        }

        // Process all acceptable items (folders or individual MXF/MOV files)
        var processedAny = false
        for url in urls {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let ext = url.pathExtension.lowercased()
            if exists && (isDir.boolValue || ext == "mxf" || ext == "mov") {
                dropDelegate?.handleDrop(url: url)
                processedAny = true
            }
        }

        return processedAny
    }

    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        if let paths = pasteboard.propertyList(forType: filenamePasteboardType) as? [String] {
            urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        if let anyURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls.append(contentsOf: anyURLs.filter { $0.isFileURL })
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL),
                   let fileURL = URL(string: fileURLString),
                   fileURL.isFileURL {
                    urls.append(fileURL)
                }

                if let fileURLString = item.string(forType: urlPasteboardType),
                   let fileURL = URL(string: fileURLString),
                   fileURL.isFileURL {
                    urls.append(fileURL)
                }
            }
        }

        return Array(Set(urls))
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }


    private func containsAcceptableItem(_ urls: [URL]) -> Bool {
        return urls.contains(where: { url in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let ext = url.pathExtension.lowercased()
            return exists && (isDir.boolValue || ext == "mxf" || ext == "mov")
        })
    }
}

@MainActor
protocol DropViewDelegate {
    func handleDrop(url: URL)
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, DropViewDelegate {
    var window: NSWindow?
    var settingsWindow: NSWindow?
    private var formatButtons: [NSButton] = []
    private var modeButtons: [NSButton] = []
    private var dropView: DropView?
    private var contentView: NSView?
    private var formatLabel: NSTextField?
    private var button: NSButton?
    private var queueCountLabel: NSTextField?
    private var lutCheckbox: NSButton?
    private var lutSelectButton: NSButton?
    private var lutLabel: NSTextField?
    private var selectedFormat: Int = 0
    private var selectedMode: Int = 0
    private var jobQueue: [URL] = []
    private var activeJob: URL?
    private var isProcessing: Bool = false
    private var totalClipsQueued: Int = 0
    
    private enum OutputFormat {
        case quickTime
        case mxf
    }
    
    private enum VideoCodec {
        case proresProxy
    }
    
    private enum DisplayMode {
        case day
        case night
        case auto
    }
    
    private var currentMode: DisplayMode = .day
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MXF2Prxy"
        window.appearance = NSAppearance(named: .vibrantDark)
        
        let formatLabel = NSTextField(labelWithString: "Output")
        formatLabel.frame = NSRect(x: 345, y: 366, width: 60, height: 20)
        self.formatLabel = formatLabel
        
        // Create format buttons
        let formatTitles = ["QuickTime", "MXF"]
        var xPos: CGFloat = 400
        for (index, title) in formatTitles.enumerated() {
            let btn = NSButton(frame: NSRect(x: xPos, y: 365, width: 80, height: 28))
            btn.title = title
            btn.bezelStyle = .rounded
            btn.tag = index
            btn.target = self
            btn.action = #selector(formatButtonClicked(_:))
            formatButtons.append(btn)
            xPos += 80
        }
        selectedFormat = UserDefaults.standard.integer(forKey: "selectedFormatSegment")
        
        selectedMode = UserDefaults.standard.integer(forKey: "selectedModeSegment")
        self.currentMode = selectedMode == 1 ? .night : (selectedMode == 2 ? .auto : .day)
        
        let button = OrangeButton(frame: NSRect(x: 200, y: 210, width: 200, height: 40))
        button.title = "Select files or folders"
        button.bezelStyle = .rounded
        if #available(macOS 10.14, *) {
            button.contentTintColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) // #ff7c06
        }
        button.target = self
        button.action = #selector(selectFolder)
        self.button = button
        
        let dropView = DropView()
        dropView.dropDelegate = self
        dropView.wantsLayer = true
        self.dropView = dropView
        updateDropViewColor()
        dropView.frame = NSRect(x: 50, y: 40, width: 500, height: 150)
        
        // Create dotted border using CAShapeLayer
        let borderLayer = CAShapeLayer()
        let borderPath = CGPath(rect: dropView.bounds, transform: nil)
        borderLayer.path = borderPath
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0).cgColor // #ff7c06
        borderLayer.lineWidth = 1.0
        borderLayer.lineDashPattern = [2, 2]
        dropView.layer?.addSublayer(borderLayer)
        
        let dropLabel = NSTextField(labelWithString: "Drag files or folders here")
        dropLabel.frame = NSRect(x: 0, y: 100, width: 500, height: 30)
        dropLabel.textColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) // #ff7c06
        dropLabel.font = NSFont.systemFont(ofSize: 16)
        dropLabel.alignment = .center
        dropView.addSubview(dropLabel)
        
        let queueCountLabel = NSTextField(labelWithString: "items in queue: 0")
        queueCountLabel.frame = NSRect(x: 0, y: 10, width: 500, height: 20)
        queueCountLabel.font = NSFont.systemFont(ofSize: 12)
        queueCountLabel.alignment = .center
        dropView.addSubview(queueCountLabel)
        self.queueCountLabel = queueCountLabel
        
        let contentView = NSView()
        contentView.wantsLayer = true
          if let logoURL = Bundle.main.url(forResource: "MXF2Prxy-logo", withExtension: "png"),
              let logoImage = NSImage(contentsOf: logoURL) {
                let scaledSize = NSSize(width: logoImage.size.width * 0.20, height: logoImage.size.height * 0.20)
            logoImage.size = scaledSize
                let logoOrigin = NSPoint(x: 10, y: contentView.bounds.height - scaledSize.height)
            let logoView = NSImageView(frame: NSRect(origin: logoOrigin, size: scaledSize))
            logoView.image = logoImage
            logoView.imageScaling = .scaleProportionallyUpOrDown
            logoView.autoresizingMask = [.maxXMargin, .minYMargin]
            contentView.addSubview(logoView)
        }
        // Gear icon button (bottom right)
        let gearButton = NSButton(frame: NSRect(x: 560, y: 10, width: 24, height: 24))
        if #available(macOS 11.0, *) {
            if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
                gearButton.image = gearImage
                gearButton.imageScaling = .scaleProportionallyUpOrDown
            } else {
                gearButton.title = "⚙️"
            }
        } else {
            gearButton.title = "⚙️"
        }
        gearButton.bezelStyle = .regularSquare
        gearButton.isBordered = false
        gearButton.toolTip = "Settings"
        gearButton.target = self
        gearButton.action = #selector(showSettings)

        let lutCheckbox = NSButton(checkboxWithTitle: "Apply LUT", target: self, action: #selector(lutCheckboxChanged(_:)))
        lutCheckbox.frame = NSRect(x: 345, y: 320, width: 100, height: 20)
        self.lutCheckbox = lutCheckbox
        
        let lutSelectButton = NSButton(frame: NSRect(x: 450, y: 317, width: 110, height: 28))
        lutSelectButton.title = "Select LUT"
        lutSelectButton.bezelStyle = .rounded
        lutSelectButton.target = self
        lutSelectButton.action = #selector(showLUTMenu(_:))
        self.lutSelectButton = lutSelectButton
        populateLUTMenu()
        
        let lutLabel = NSTextField(labelWithString: "No LUT selected")
        lutLabel.frame = NSRect(x: 345, y: 285, width: 200, height: 16)
        lutLabel.font = NSFont.systemFont(ofSize: 11)
        lutLabel.textColor = NSColor.secondaryLabelColor
        self.lutLabel = lutLabel
        
        // Check if LUT already selected
        if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
            let lutPath = getLUTDirectoryURL().appendingPathComponent(savedLUT).path
            if FileManager.default.fileExists(atPath: lutPath) {
                lutCheckbox.state = UserDefaults.standard.bool(forKey: "lutEnabled") ? .on : .off
                lutLabel.stringValue = lutCheckbox.state == .on ? savedLUT : ""
                lutLabel.textColor = NSColor(red: 8/255, green: 1.0, blue: 125/255, alpha: 1.0)
            }
        }
        
        contentView.addSubview(formatLabel)
        for btn in formatButtons {
            contentView.addSubview(btn)
        }
        contentView.addSubview(lutCheckbox)
        contentView.addSubview(lutSelectButton)
        contentView.addSubview(lutLabel)
        contentView.addSubview(button)
        contentView.addSubview(dropView)
        contentView.addSubview(gearButton)
        self.contentView = contentView
        window.contentView = contentView
        
        // Apply colors after all views are added
        updateFormatButtons()
        updateModeButtons()
        window.makeKeyAndOrderFront(nil)
        updateWindowColors()
        
        self.window = window
    }
    
    func handleDrop(url: URL) {
        enqueueJob(url)
    }

    private func enqueueJob(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        if isDuplicateJob(standardizedURL) {
            return
        }
        jobQueue.append(standardizedURL)
        
        // Count clips for this job
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDir)
        
        if isDir.boolValue {
            // Count MXF/MOV files in folder
            if let contents = try? FileManager.default.contentsOfDirectory(at: standardizedURL, includingPropertiesForKeys: nil) {
                let fileCount = contents.filter { 
                    let ext = $0.pathExtension.lowercased()
                    return ext == "mxf" || ext == "mov"
                }.count
                totalClipsQueued += fileCount
            }
        } else {
            // Single file
            totalClipsQueued += 1
        }
        
        updateDropZoneAvailability()
        startNextJobIfNeeded()
    }

    private func isDuplicateJob(_ url: URL) -> Bool {
        if let activeJob = activeJob, activeJob.standardizedFileURL.path == url.standardizedFileURL.path {
            return true
        }
        return jobQueue.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }

    private func startNextJobIfNeeded() {
        guard !isProcessing else { return }
        guard !jobQueue.isEmpty else {
            updateDropZoneAvailability()
            return
        }
        isProcessing = true
        activeJob = jobQueue.removeFirst()
        updateDropZoneAvailability()
        let outputFormat = currentOutputFormat()
        if let jobURL = activeJob {
            processFolder(jobURL, outputFormat: outputFormat) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isProcessing = false
                    self.activeJob = nil
                    self.updateDropZoneAvailability()
                    self.startNextJobIfNeeded()
                }
            }
        }
    }

    private func updateDropZoneAvailability() {
        dropView?.isDropEnabled = true
        queueCountLabel?.stringValue = "items in queue: \(totalClipsQueued)"
    }
    
    @objc func formatButtonClicked(_ sender: NSButton) {
        selectedFormat = sender.tag
        UserDefaults.standard.set(selectedFormat, forKey: "selectedFormatSegment")
        updateFormatButtons()
    }
    
    @objc func modeButtonClicked(_ sender: NSButton) {
        selectedMode = sender.tag
        self.currentMode = selectedMode == 1 ? .night : (selectedMode == 2 ? .auto : .day)
        UserDefaults.standard.set(selectedMode, forKey: "selectedModeSegment")
        updateModeButtons()
        updateWindowColors()
    }
    
    @objc func lutCheckboxChanged(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        UserDefaults.standard.set(isEnabled, forKey: "lutEnabled")
        
        if !isEnabled {
            lutLabel?.stringValue = ""
        } else if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath"),
                  FileManager.default.fileExists(atPath: getLUTDirectoryURL().appendingPathComponent(savedLUT).path) {
            lutLabel?.stringValue = savedLUT
            lutLabel?.textColor = NSColor(red: 8/255, green: 1.0, blue: 125/255, alpha: 1.0)
        } else {
            lutLabel?.stringValue = "No LUT selected"
            lutLabel?.textColor = NSColor.secondaryLabelColor
        }
    }
    
    @objc func selectLUTFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["cube"]
        panel.message = "Select a LUT file (.cube format)"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            
            let lutDir = self.getLUTDirectoryURL()
            let destURL = lutDir.appendingPathComponent(url.lastPathComponent)
            let fileManager = FileManager.default
            
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
                UserDefaults.standard.set(url.lastPathComponent, forKey: "lutFilePath")
                UserDefaults.standard.set(true, forKey: "lutEnabled")
                self.lutCheckbox?.state = .on
                self.lutLabel?.stringValue = url.lastPathComponent
                self.lutLabel?.textColor = NSColor(red: 8/255, green: 1.0, blue: 125/255, alpha: 1.0)
                
                // Refresh the menu
                self.populateLUTMenu()
            } catch {
                self.appendLog(logURL: URL(fileURLWithPath: "/tmp/mxf2prxy.log"), entry: "Failed to copy LUT: \(error)\n")
            }
        }
    }
    
    private func updateFormatButtons() {
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        for (index, btn) in formatButtons.enumerated() {
            if index == selectedFormat {
                btn.bezelColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) // #ff7c06
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            } else {
                btn.bezelColor = isDark ? NSColor.darkGray : NSColor(calibratedWhite: 0.75, alpha: 1.0)
                let textColor = isDark ? NSColor.lightGray : NSColor.darkGray
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            }
        }
    }
    
    private func updateModeButtons() {
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        for (index, btn) in modeButtons.enumerated() {
            if index == selectedMode {
                btn.bezelColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) // #ff7c06
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            } else {
                btn.bezelColor = isDark ? NSColor.darkGray : NSColor(calibratedWhite: 0.75, alpha: 1.0)
                let textColor = isDark ? NSColor.lightGray : NSColor.darkGray
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            }
        }
    }
    
    private func getLUTDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let lutDir = appSupport.appendingPathComponent("MXF2Prxy").appendingPathComponent("LUTs")
        
        if !fileManager.fileExists(atPath: lutDir.path) {
            try? fileManager.createDirectory(at: lutDir, withIntermediateDirectories: true)
        }
        
        return lutDir
    }
    
    @objc func showLUTMenu(_ sender: NSButton) {
        if let menu = sender.menu {
            let point = NSPoint(x: 0, y: sender.bounds.height)
            menu.popUp(positioning: nil, at: point, in: sender)
        }
    }
    
    private func populateLUTMenu() {
        guard let button = lutSelectButton as? NSButton else { return }
        
        let menu = NSMenu()
        let currentLUT = UserDefaults.standard.string(forKey: "lutFilePath")
        
        // Add available LUTs
        let availableLUTs = getAvailableLUTs()
        for lut in availableLUTs {
            let item = NSMenuItem(title: lut, action: #selector(selectLUTFromMenu(_:)), keyEquivalent: "")
            item.target = self
            if lut == currentLUT {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        // Add separator if we have LUTs
        if !availableLUTs.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        
        // Add "Add LUT..."
        let addItem = NSMenuItem(title: "Add LUT...", action: #selector(selectLUTFile), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        
        button.menu = menu
    }
    
    @objc func selectLUTFromMenu(_ sender: NSMenuItem) {
        let lutFilename = sender.title
        UserDefaults.standard.set(lutFilename, forKey: "lutFilePath")
        UserDefaults.standard.set(true, forKey: "lutEnabled")
        lutCheckbox?.state = .on
        lutLabel?.stringValue = lutFilename
        lutLabel?.textColor = NSColor(red: 8/255, green: 1.0, blue: 125/255, alpha: 1.0)
    }
    
    private func getAvailableLUTs() -> [String] {
        let lutDir = getLUTDirectoryURL()
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: lutDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.filter { $0.pathExtension.lowercased() == "cube" }
            .map { $0.lastPathComponent }
            .sorted()
    }
    
    private func updateWindowColors() {
        let mode = currentMode
        let isDark: Bool
        
        if mode == .auto {
            isDark = isSystemDarkAppearance()
        } else if mode == .night {
            isDark = true
        } else {
            isDark = false
        }

        if #available(macOS 10.14, *) {
            window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        } else {
            window?.appearance = NSAppearance(named: .aqua)
        }
        
        // Update background color
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.537, green: 0.537, blue: 0.537, alpha: 1.0) // #898989
        contentView?.layer?.backgroundColor = bgColor.cgColor
        contentView?.wantsLayer = true
        
        // Update text color
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) // #AAAAAA : #333333
        formatLabel?.textColor = textColor
        queueCountLabel?.textColor = textColor
        
        // Update button appearance
        if #available(macOS 10.14, *) {
            button?.contentTintColor = NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) // #ff7c06
        }
        
        updateDropViewColor()
    }
    
    private func updateDropViewColor() {
        let color: NSColor
        let mode = currentMode
        
        // If auto mode, check system appearance
        if mode == .auto {
            let isDark = isSystemDarkAppearance()
            color = isDark ? NSColor.black : NSColor(red: 0.388, green: 0.388, blue: 0.388, alpha: 1.0)
        } else if mode == .night {
            color = NSColor.black
        } else {
            color = NSColor(red: 0.388, green: 0.388, blue: 0.388, alpha: 1.0) // #636363
        }
        dropView?.layer?.backgroundColor = color.cgColor
    }

    private func isSystemDarkAppearance() -> Bool {
        if #available(macOS 10.14, *) {
            return NSApp.effectiveAppearance.name == .darkAqua
        }
        return false
    }
    
    @objc func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select folders or MXF/MOV files"
        panel.prompt = "Select"
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    self.enqueueJob(url)
                }
            }
        }
    }
    
    private func processFolder(_ url: URL, outputFormat: OutputFormat, completion: @escaping @Sendable () -> Void) {
        // Save current selections to UserDefaults
        UserDefaults.standard.set(self.selectedFormat, forKey: "selectedFormatSegment")
        
        // Move file I/O to background queue to keep main thread responsive
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var mxfFiles: [URL] = []
            var proxyFolderURL: URL
            
            // Check if url is a file or folder
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                // It's a folder - use existing behavior
                let folderName = url.lastPathComponent
                let parentURL = url.deletingLastPathComponent()
                proxyFolderURL = parentURL.appendingPathComponent("\(folderName) proxies")
                
                do {
                    let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    let ext = { (u: URL) -> String in u.pathExtension.lowercased() }
                    mxfFiles = contents.filter { ext($0) == "mxf" || ext($0) == "mov" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                } catch {
                    print("Error reading folder: \(error)")
                    completion()
                    return
                }
            } else {
                // It's a file
                let parentURL = url.deletingLastPathComponent()
                proxyFolderURL = parentURL.appendingPathComponent("m2p-proxies")
                mxfFiles = [url]
            }
            
            do {
                try FileManager.default.createDirectory(at: proxyFolderURL, withIntermediateDirectories: true)
            } catch {
                print("Error: \(error)")
                completion()
                return
            }

            // Dispatch back to main thread before starting processing
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.processNextFile(index: 0, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
            }
        }
    }

    private func processNextFile(index: Int, mxfFiles: [URL], proxyFolderURL: URL, outputFormat: OutputFormat, completion: @escaping @Sendable () -> Void) {
        guard index < mxfFiles.count else {
            print("Conversion complete: \(proxyFolderURL.path)")
            completion()
            return
        }

        let mxfFile = mxfFiles[index]
        let outputFileName: String
        switch outputFormat {
        case .quickTime:
            outputFileName = mxfFile.deletingPathExtension().lastPathComponent + ".mov"
        case .mxf:
            outputFileName = mxfFile.deletingPathExtension().lastPathComponent + ".mxf"
        }
        let outputFileURL = proxyFolderURL.appendingPathComponent(outputFileName)

        // Find watermark in Resources
        let watermarkURL = Bundle.main.resourceURL?.appendingPathComponent("mxf2proxy.png")
        let hasWatermark = watermarkURL != nil && FileManager.default.fileExists(atPath: watermarkURL?.path ?? "")

        let ffmpegURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ffmpeg")
        let debugPath = ffmpegURL?.path ?? "nil"
        let debugLog = "Using ffmpeg at: \(debugPath)\n"
        let logURL = proxyFolderURL.appendingPathComponent("conversion_log.txt")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        appendLog(logURL: logURL, entry: debugLog)

        let quickTimeCodecArgs = [
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "18",
            "-pix_fmt", "yuv420p"
        ]

        let mxfCodecArgs = [
            "-c:v", "mpeg2video",
            "-b:v", "45M",
            "-maxrate", "45M",
            "-bufsize", "90M"
        ]

        // Watermark args only for MXF files (MOV uses two-pass method)
        let isMOVFile = mxfFile.pathExtension.lowercased() == "mov"
        let watermarkArgs: [String]
        let videoMap: [String]

        if hasWatermark && !isMOVFile {
            watermarkArgs = [
                "-i", watermarkURL!.path,
                "-filter_complex", "[0:v]scale=-1:-1:flags=bicubic:out_color_matrix=bt709,format=yuv420p[v0];[1:v]scale=-1:160,format=rgba,colorchannelmixer=aa=0.5[wm];[v0][wm]overlay=W-w-10:H-h-10[v]"
            ]
            videoMap = ["-map", "[v]"]
        } else {
            watermarkArgs = []
            videoMap = ["-map", "0:v"]
        }

        switch outputFormat {
        case .quickTime:
            // For MOV files, check if it's high bit-depth ProRes
            let needsIntermediateConversion = mxfFile.pathExtension.lowercased() == "mov"
            
            if needsIntermediateConversion {
                // Step 1: Use AVFoundation to convert ProRes to H.264 (handles all bit depths)
                let intermediateURL = proxyFolderURL.appendingPathComponent("\(mxfFile.deletingPathExtension().lastPathComponent)_8bit.mov")
                
                self.appendLog(logURL: logURL, entry: "Step 1: AVFoundation converting \(mxfFile.lastPathComponent)\n")
                self.convertProResWithAVFoundation(inputURL: mxfFile, outputURL: intermediateURL, logURL: logURL) { [weak self] success in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !success {
                            self.appendLog(logURL: logURL, entry: "FAILED (AVFoundation conversion): \(mxfFile.lastPathComponent)\n\n")
                            self.totalClipsQueued -= 1
                            self.updateDropZoneAvailability()
                            self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                            return
                        }
                        
                        self.appendLog(logURL: logURL, entry: "Step 1 SUCCESS. Step 2: watermarking with hasWatermark=\(hasWatermark)\n")
                        
                        // Check for LUT file
                        let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
                        let lutFilename = UserDefaults.standard.string(forKey: "lutFilePath")
                        let lutPath = lutFilename != nil ? self.getLUTDirectoryURL().appendingPathComponent(lutFilename!).path : nil
                        let hasLUT = lutEnabled && lutPath != nil && FileManager.default.fileExists(atPath: lutPath!)
                        self.appendLog(logURL: logURL, entry: "LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")
                        
                        // Step 2: Apply LUT and/or watermark to AVFoundation intermediate
                        var args: [String]
                        if hasWatermark {
                            // Build filter chain with optional LUT
                            var filterChain = "[0:v]"
                            if hasLUT {
                                filterChain += "lut3d=file='\(lutPath!)',"
                            }
                            filterChain += "scale=-1:-1:flags=bicubic:out_color_matrix=bt709,format=yuv420p[v0];[1:v]scale=-1:160,format=rgba,colorchannelmixer=aa=0.5[wm];[v0][wm]overlay=W-w-10:H-h-10[v]"
                            
                            args = [
                                "-i", intermediateURL.path,
                                "-i", watermarkURL!.path,
                                "-i", mxfFile.path,
                                "-filter_complex", filterChain,
                                "-map", "[v]",
                                "-map", "2:a?",
                                "-c:v", "libx264",
                                "-preset", "fast",
                                "-crf", "18",
                                "-c:a", "copy",
                                "-sn",
                                outputFileURL.path
                            ]
                        } else {
                            // No watermark, but may have LUT
                            if hasLUT {
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                    "-vf", "lut3d=file='\(lutPath!)'",
                                    "-map", "0:v",
                                    "-map", "1:a?",
                                    "-c:v", "libx264",
                                    "-preset", "fast",
                                    "-crf", "18",
                                    "-c:a", "copy",
                                    "-sn",
                                    outputFileURL.path
                                ]
                            } else {
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                    "-map", "0:v",
                                    "-map", "1:a?",
                                    "-c:v", "libx264",
                                    "-preset", "fast",
                                    "-crf", "18",
                                    "-c:a", "copy",
                                    "-sn",
                                    outputFileURL.path
                                ]
                            }
                        }
                        
                        self.runProcessDetached(executableURL: ffmpegURL, arguments: args, logURL: logURL) { [weak self] status2 in
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                if status2 != 0 {
                                    self.appendLog(logURL: logURL, entry: "FAILED (watermark): \(mxfFile.lastPathComponent)\n\n")
                                }
                                // Clean up intermediate file
                                try? FileManager.default.removeItem(at: intermediateURL)
                                self.totalClipsQueued -= 1
                                self.updateDropZoneAvailability()
                                self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                            }
                        }
                    }
                }
            } else {
                // Original single-pass for MXF files
                var args = ["-i", mxfFile.path]
                args += watermarkArgs
                args += videoMap
                args += quickTimeCodecArgs
                args += [
                    "-map", "0:a?",
                    "-c:a", "copy",
                    "-sn",
                    outputFileURL.path
                ]
                runProcessDetached(executableURL: ffmpegURL, arguments: args, logURL: logURL) { [weak self] status in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if status != 0 {
                            self.appendLog(logURL: logURL, entry: "FAILED: \(mxfFile.lastPathComponent)\n\n")
                        }
                        self.totalClipsQueued -= 1
                        self.updateDropZoneAvailability()
                        self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                    }
                }
            }
        case .mxf:
            // Two-step process for MXF:
            // 1. Create intermediate video with watermark
            let tempVideoURL = proxyFolderURL.appendingPathComponent(".\(mxfFile.deletingPathExtension().lastPathComponent)_temp.mov")
            var args1 = ["-i", mxfFile.path]
            args1 += watermarkArgs
            args1 += videoMap
            args1 += mxfCodecArgs
            args1 += [
                "-an",
                tempVideoURL.path
            ]
            runProcessDetached(executableURL: ffmpegURL, arguments: args1, logURL: logURL) { [weak self] status1 in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if status1 != 0 {
                        self.appendLog(logURL: logURL, entry: "FAILED: \(mxfFile.lastPathComponent)\n\n")
                        self.totalClipsQueued -= 1
                        self.updateDropZoneAvailability()
                        self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                        return
                    }

                    // Step 2: Replace video in original MXF with watermarked video
                    let args2 = [
                        "-i", mxfFile.path,
                        "-i", tempVideoURL.path,
                        "-map", "1:v:0",
                        "-map", "0:a?",
                        "-map", "0:d?",
                        "-map", "0:s?",
                        "-c:v", "copy",
                        "-c:a", "copy",
                        "-c:d", "copy",
                        "-c:s", "copy",
                        "-map_metadata", "0",
                        "-f", "mxf",
                        outputFileURL.path
                    ]
                    self.runProcessDetached(executableURL: ffmpegURL, arguments: args2, logURL: logURL) { [weak self] status2 in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempVideoURL)
                            if status2 != 0 {
                                self.appendLog(logURL: logURL, entry: "FAILED: \(mxfFile.lastPathComponent) (step 2)\n\n")
                            }
                            self.totalClipsQueued -= 1
                            self.updateDropZoneAvailability()
                            self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                        }
                    }
                }
            }
        }
    }

    private func runProcessDetached(executableURL: URL?, arguments: [String], logURL: URL, completion: @escaping @Sendable (Int32) -> Void) {
        guard let executableURL = executableURL else {
            completion(-1)
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let logHandle = FileHandle(forWritingAtPath: logURL.path)
        logHandle?.seekToEndOfFile()
        process.standardOutput = logHandle
        process.standardError = logHandle

        process.terminationHandler = { _ in
            logHandle?.closeFile()
            completion(process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            logHandle?.closeFile()
            completion(-1)
        }
    }

    private func appendLog(logURL: URL, entry: String) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = FileHandle(forWritingAtPath: logURL.path) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8) ?? Data())
                handle.closeFile()
            }
        } else {
            try? entry.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
    
    func setupMenuBar() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit MXF2Prxy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        let fileMenu = NSMenu()
        let quitFileItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitFileItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(quitFileItem)
        
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            guard let mainWindow = window else { return }
            let settingsSize = NSSize(width: 400, height: 260)
            // Offset settings window: +300 x, +200 y from main window's origin
            let mainOrigin = mainWindow.frame.origin
            let settingsOrigin = NSPoint(x: mainOrigin.x + 300, y: mainOrigin.y + 100)
            let settingsWin = NSWindow(
                contentRect: NSRect(origin: settingsOrigin, size: settingsSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWin.title = "Settings"
            settingsWin.appearance = NSAppearance(named: .vibrantDark)



            let lutButton = NSButton(frame: NSRect(x: 100, y: 185, width: 200, height: 28))
            lutButton.title = "Manage LUTs"
            lutButton.bezelStyle = .rounded
            lutButton.target = self
            lutButton.action = #selector(selectLUT)
            // Set button text color to match main window's Output label color
            let mainLabelColor = formatLabel?.textColor ?? NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            let lutButtonAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: mainLabelColor]
            lutButton.attributedTitle = NSAttributedString(string: lutButton.title, attributes: lutButtonAttrs)

            let modeLabel = NSTextField(labelWithString: "Display Mode:")
            modeLabel.frame = NSRect(x: 50, y: 130, width: 150, height: 20)
            // Use the same color as the main window's Output label
            modeLabel.textColor = mainLabelColor

            // Create mode buttons for settings window
            let modeTitles = ["Light", "Dark", "Auto"]
            var xPos: CGFloat = 50
            modeButtons.removeAll()
            for (index, title) in modeTitles.enumerated() {
                let btn = NSButton(frame: NSRect(x: xPos, y: 90, width: 90, height: 28))
                btn.title = title
                btn.bezelStyle = .rounded
                btn.tag = index
                btn.target = self
                btn.action = #selector(modeButtonClicked(_:))
                // Set button text color to match main window's Output label color
                let btnAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: mainLabelColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: btnAttrs)
                modeButtons.append(btn)
                xPos += 100
            }
            updateModeButtons()

            let contentView = NSView()
            contentView.wantsLayer = true
            // Match background color to main window in dark mode
            var isDark = false
            if #available(macOS 10.14, *) {
                isDark = (window?.appearance?.name == .darkAqua) || (window?.appearance?.name == .vibrantDark)
            } else {
                isDark = (window?.appearance?.name == .vibrantDark)
            }
            if isDark {
                contentView.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
            }
            contentView.addSubview(lutButton)
            contentView.addSubview(modeLabel)
            for btn in modeButtons {
                contentView.addSubview(btn)
            }

            let closeButton = NSButton(frame: NSRect(x: 150, y: 20, width: 100, height: 30))
            closeButton.title = "Close"
            closeButton.bezelStyle = .rounded
            closeButton.target = self
            closeButton.action = #selector(closeSettings)
            // Set button text color to match main window's Output label color
            let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: mainLabelColor]
            closeButton.attributedTitle = NSAttributedString(string: closeButton.title, attributes: closeAttrs)
            contentView.addSubview(closeButton)

            settingsWin.contentView = contentView
            self.settingsWindow = settingsWin
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeSettings() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }
    
    @objc private func selectLUT() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["cube"]
        panel.message = "Select LUT file (.cube format)"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "lutFilePath")
                // Update button title in settings window if it exists
                if let settingsContentView = self.settingsWindow?.contentView {
                    for subview in settingsContentView.subviews {
                        if let button = subview as? NSButton, button.action == #selector(self.selectLUT) {
                            button.title = url.lastPathComponent
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func currentOutputFormat() -> OutputFormat {
        return selectedFormat == 1 ? .mxf : .quickTime
    }
    
    private func currentVideoCodec() -> VideoCodec {
        return .proresProxy
    }
    
    private func convertProResWithAVFoundation(inputURL: URL, outputURL: URL, logURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            appendLog(logURL: logURL, entry: "AVFoundation: Failed to create export session\n")
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async { [weak self] in
                let success = exportSession.status == .completed
                if !success {
                    let error = exportSession.error?.localizedDescription ?? "unknown error"
                    self?.appendLog(logURL: logURL, entry: "AVFoundation export failed: \(error)\n")
                }
                completion(success)
            }
        }
    }
}
