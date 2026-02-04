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

class FlippedView: NSView {
    override var isFlipped: Bool { return true }
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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, DropViewDelegate {
    var window: NSWindow?
    weak var settingsWindow: NSWindow?
    weak var lutManagementWindow: NSWindow?
    weak var watermarkManagementWindow: NSWindow?
    private var formatButtons: [NSButton] = []
    private var modeButtons: [NSButton] = []
    private let sessionUUID = UUID().uuidString
    private var dropView: DropView?
    private var contentView: NSView?
    private var formatLabel: NSTextField?
    private var button: NSButton?
    private var queueCountLabel: NSTextField?
    private var watermarkCheckbox: NSButton?
    private var lutCheckbox: NSButton?
    private var lutSelectButton: NSButton?
    private var lutLabel: NSTextField?
    private var dropLabel: NSTextField?
    private var encodingPathLabel: NSTextField?
    private var dropBorderLayer: CAShapeLayer?
    private var gearButton: NSButton?
    private var selectedFormat: Int = 0
    private var selectedMode: Int = 0
    private var jobQueue: [URL] = []
    private var activeJob: URL?
    private var isProcessing: Bool = false
    private var totalClipsQueued: Int = 0
    private var overwriteAllFiles: Bool = false
    private var skipAllExisting: Bool = false

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

        // Determine initial mode FIRST
        selectedFormat = UserDefaults.standard.integer(forKey: "selectedFormatSegment")
        selectedMode = UserDefaults.standard.integer(forKey: "selectedModeSegment")
        self.currentMode = selectedMode == 1 ? .night : (selectedMode == 2 ? .auto : .day)

        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "MXF2Prxy"
        window.titlebarAppearsTransparent = true
        window.isRestorable = false

        // Set initial appearance and colors based on mode
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        window.backgroundColor = titleBarColor

        if #available(macOS 10.14, *) {
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }

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
        borderLayer.lineWidth = 1.0
        borderLayer.lineDashPattern = [2, 2]
        dropView.layer?.addSublayer(borderLayer)
        self.dropBorderLayer = borderLayer

        let dropLabel = NSTextField(labelWithString: "Drag files or folders here")
        dropLabel.frame = NSRect(x: 0, y: 110, width: 500, height: 30)
        dropLabel.font = NSFont.systemFont(ofSize: 16)
        dropLabel.alignment = .center
        dropView.addSubview(dropLabel)
        self.dropLabel = dropLabel

        let encodingPathLabel = NSTextField(labelWithString: "")
        encodingPathLabel.frame = NSRect(x: 0, y: 75, width: 500, height: 30)
        encodingPathLabel.font = NSFont.systemFont(ofSize: 12)
        encodingPathLabel.alignment = .center
        dropView.addSubview(encodingPathLabel)
        self.encodingPathLabel = encodingPathLabel

        let queueCountLabel = NSTextField(labelWithString: "Items in queue: 0")
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
        self.gearButton = gearButton

        // Watermark checkbox
        let watermarkCheckbox = NSButton(checkboxWithTitle: "Apply watermark", target: self, action: #selector(watermarkCheckboxChanged(_:)))
        watermarkCheckbox.frame = NSRect(x: 345, y: 336, width: 140, height: 20)
        // Default to true on first launch
        if UserDefaults.standard.object(forKey: "watermarkEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "watermarkEnabled")
        }
        if UserDefaults.standard.object(forKey: "watermarkMode") == nil {
            UserDefaults.standard.set("default", forKey: "watermarkMode")
        }
        watermarkCheckbox.state = UserDefaults.standard.bool(forKey: "watermarkEnabled") ? .on : .off
        self.watermarkCheckbox = watermarkCheckbox

        let lutCheckbox = NSButton(checkboxWithTitle: "Apply LUT", target: self, action: #selector(lutCheckboxChanged(_:)))
        lutCheckbox.frame = NSRect(x: 345, y: 306, width: 100, height: 20)
        self.lutCheckbox = lutCheckbox

        let lutSelectButton = NSButton(frame: NSRect(x: 450, y: 303, width: 110, height: 28))
        lutSelectButton.title = "Select LUT"
        lutSelectButton.bezelStyle = .rounded
        lutSelectButton.target = self
        lutSelectButton.action = #selector(showLUTMenu(_:))
        self.lutSelectButton = lutSelectButton
        
        let lutLabel = NSTextField(labelWithString: "No LUT selected")
        lutLabel.frame = NSRect(x: 345, y: 271, width: 200, height: 16)
        lutLabel.font = NSFont.systemFont(ofSize: 11)
        lutLabel.textColor = NSColor.secondaryLabelColor
        self.lutLabel = lutLabel
        
        // Check if LUT already selected
        if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
            let lutPath = getLUTDirectoryURL().appendingPathComponent(savedLUT).path
            if FileManager.default.fileExists(atPath: lutPath) {
                lutCheckbox.state = UserDefaults.standard.bool(forKey: "lutEnabled") ? .on : .off
                lutLabel.stringValue = lutCheckbox.state == .on ? savedLUT : ""
                // Color will be set by updateWindowColors()
            }
        }
        
        contentView.addSubview(formatLabel)
        for btn in formatButtons {
            contentView.addSubview(btn)
        }
        contentView.addSubview(watermarkCheckbox)
        contentView.addSubview(lutCheckbox)
        contentView.addSubview(lutSelectButton)
        contentView.addSubview(lutLabel)
        contentView.addSubview(button)
        contentView.addSubview(dropView)
        contentView.addSubview(gearButton)
        self.contentView = contentView
        window.contentView = contentView
        window.delegate = self

        // Apply colors after all views are added
        updateFormatButtons()
        updateModeButtons()
        window.makeKeyAndOrderFront(nil)
        updateWindowColors()

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Prevent actual window close for secondary windows to avoid animation crashes
        // Instead, just hide them like the Close button does
        if sender === settingsWindow {
            settingsWindow?.orderOut(nil)
            settingsWindow = nil
            return false  // Prevent the actual close
        } else if sender === lutManagementWindow {
            lutManagementWindow?.orderOut(nil)
            lutManagementWindow = nil
            return false  // Prevent the actual close
        } else if sender === watermarkManagementWindow {
            // X button = Cancel (don't save)
            watermarkManagementWindow?.orderOut(nil)
            watermarkManagementWindow = nil
            return false  // Prevent the actual close
        }

        // Allow main window to close normally (quits the app)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        // Clear window references for main window
        if closingWindow === window {
            window?.delegate = nil
            window = nil
        }
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


    private func updateDropZoneAvailability() {
        dropView?.isDropEnabled = true
        queueCountLabel?.stringValue = "Items in queue: \(totalClipsQueued)"
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
        updateSettingsWindowColors()
        updateLUTManagementWindowColors()
        updateWatermarkManagementWindowColors()
    }

    @objc func watermarkCheckboxChanged(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        UserDefaults.standard.set(isEnabled, forKey: "watermarkEnabled")
    }

    @objc func lutCheckboxChanged(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        UserDefaults.standard.set(isEnabled, forKey: "lutEnabled")
        
        if !isEnabled {
            lutLabel?.stringValue = ""
        } else if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath"),
                  FileManager.default.fileExists(atPath: getLUTDirectoryURL().appendingPathComponent(savedLUT).path) {
            lutLabel?.stringValue = savedLUT
            let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
            lutLabel?.textColor = isDark ? NSColor(red: 0.408, green: 0.867, blue: 0.427, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
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
                let isDark = self.currentMode == .auto ? self.isSystemDarkAppearance() : (self.currentMode == .night)
                self.lutLabel?.textColor = isDark ? NSColor(red: 0.408, green: 0.867, blue: 0.427, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)

                // Refresh LUT management window if it's open
                if self.lutManagementWindow != nil {
                    self.closeLUTManagement()
                    self.selectLUT()
                }
            } catch {
                self.appendLog(logURL: URL(fileURLWithPath: "/tmp/mxf2prxy.log"), entry: "Failed to copy LUT: \(error)\n")
            }
        }
    }
    
    private func updateFormatButtons() {
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        let selectedColor = isDark ? NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        let selectedTextColor = isDark ? NSColor.black : NSColor(white: 1.0, alpha: 0.8)
        for (index, btn) in formatButtons.enumerated() {
            if index == selectedFormat {
                btn.bezelColor = selectedColor
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: selectedTextColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            } else {
                btn.bezelColor = isDark ? NSColor.darkGray : NSColor(calibratedWhite: 0.75, alpha: 1.0)
                let textColor = isDark ? NSColor.lightGray : NSColor(white: 0.0, alpha: 0.8)
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            }
        }
    }

    private func updateModeButtons() {
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        let selectedColor = isDark ? NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        let selectedTextColor = isDark ? NSColor.black : NSColor(white: 1.0, alpha: 0.8)
        for (index, btn) in modeButtons.enumerated() {
            if index == selectedMode {
                btn.bezelColor = selectedColor
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: selectedTextColor]
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
            } else {
                btn.bezelColor = isDark ? NSColor.darkGray : NSColor(calibratedWhite: 0.75, alpha: 1.0)
                let textColor = isDark ? NSColor.lightGray : NSColor(white: 0.0, alpha: 0.8)
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
        let menu = buildLUTMenu()
        let point = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: point, in: sender)
    }
    
    private func buildLUTMenu() -> NSMenu {
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
        return menu
    }
    
    @objc func selectLUTFromMenu(_ sender: NSMenuItem) {
        let lutFilename = sender.title
        UserDefaults.standard.set(lutFilename, forKey: "lutFilePath")
        UserDefaults.standard.set(true, forKey: "lutEnabled")
        lutCheckbox?.state = .on
        lutLabel?.stringValue = lutFilename
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        lutLabel?.textColor = isDark ? NSColor(red: 0.408, green: 0.867, blue: 0.427, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        // No need to repopulate menu; it will be rebuilt next time
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

        // Set window background color for title bar first
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        window?.backgroundColor = titleBarColor

        // Set appearance explicitly without animations to prevent crashes
        if let win = window {
            let savedBehavior = win.animationBehavior
            win.animationBehavior = .none
            if #available(macOS 10.14, *) {
                win.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            }
            win.animationBehavior = savedBehavior
        }

        // Update background color without implicit animations
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.backgroundColor = bgColor.cgColor
        contentView?.wantsLayer = true
        CATransaction.commit()

        // Update text color
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) // #AAAAAA : #333333
        formatLabel?.textColor = textColor

        // Update queue count label color - green in dark mode
        let queueCountColor = isDark ? NSColor(red: 0.408, green: 0.867, blue: 0.427, alpha: 1.0) : textColor // #68dd6d in dark mode
        queueCountLabel?.textColor = queueCountColor

        // Update button appearance
        let accentColor = isDark ? NSColor(red: 1.0, green: 0.486, blue: 0.024, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        if #available(macOS 10.14, *) {
            button?.contentTintColor = accentColor
        }

        // Update button text color - use same color as Output label
        if let btn = button {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
        }

        // Update gear icon color to match text color
        if #available(macOS 10.14, *) {
            gearButton?.contentTintColor = textColor
        }

        // Update drop zone label color to match text, border stays accent color
        dropLabel?.textColor = textColor
        dropBorderLayer?.strokeColor = accentColor.cgColor

        // Update watermark checkbox text color
        if let checkbox = watermarkCheckbox {
            let checkboxAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            checkbox.attributedTitle = NSAttributedString(string: checkbox.title, attributes: checkboxAttrs)
        }

        // Update LUT checkbox text color
        if let checkbox = lutCheckbox {
            let checkboxAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            checkbox.attributedTitle = NSAttributedString(string: checkbox.title, attributes: checkboxAttrs)
        }

        // Update LUT select button text color
        if let selectBtn = lutSelectButton {
            let selectBtnAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            selectBtn.attributedTitle = NSAttributedString(string: selectBtn.title, attributes: selectBtnAttrs)
        }

        // Update LUT label color - green in dark mode when LUT is selected, otherwise secondary
        if let label = lutLabel {
            if label.stringValue.isEmpty || label.stringValue == "No LUT selected" {
                label.textColor = NSColor.secondaryLabelColor
            } else {
                // LUT is selected - use green in dark mode, blue in light mode
                label.textColor = isDark ? NSColor(red: 0.408, green: 0.867, blue: 0.427, alpha: 1.0) : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
            }
        }

        updateDropViewColor()
    }

    private func updateSettingsWindowColors() {
        guard let settingsWin = settingsWindow, settingsWin.isVisible, let contentView = settingsWin.contentView else { return }

        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)

        // Update title bar color
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        settingsWin.backgroundColor = titleBarColor

        // Update appearance explicitly without animations
        let savedBehavior = settingsWin.animationBehavior
        settingsWin.animationBehavior = .none
        if #available(macOS 10.14, *) {
            settingsWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
        settingsWin.animationBehavior = savedBehavior

        // Update content background without implicit animations
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.layer?.backgroundColor = bgColor.cgColor
        CATransaction.commit()

        // Update all labels and buttons in the settings window
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        for subview in contentView.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.textColor = textColor
            } else if let button = subview as? NSButton {
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs)
            }
        }

        // Update mode buttons to reflect selection
        updateModeButtons()
    }

    private func updateLUTManagementWindowColors() {
        guard let lutWin = lutManagementWindow, lutWin.isVisible, let contentView = lutWin.contentView else { return }

        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)

        // Update title bar color
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        lutWin.backgroundColor = titleBarColor

        // Update appearance explicitly without animations
        let savedBehavior = lutWin.animationBehavior
        lutWin.animationBehavior = .none
        if #available(macOS 10.14, *) {
            lutWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
        lutWin.animationBehavior = savedBehavior

        // Update content background without implicit animations
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.layer?.backgroundColor = bgColor.cgColor
        CATransaction.commit()

        // Update title label and buttons
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let listBgColor = isDark ? NSColor.black : NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)

        for subview in contentView.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.textColor = textColor
            } else if let button = subview as? NSButton {
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs)
            } else if let scrollView = subview as? NSScrollView {
                scrollView.backgroundColor = listBgColor
                if let listView = scrollView.documentView {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    listView.layer?.backgroundColor = listBgColor.cgColor
                    CATransaction.commit()
                    // Update all LUT row labels
                    for rowView in listView.subviews {
                        for item in rowView.subviews {
                            if let label = item as? NSTextField {
                                label.textColor = textColor
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateWatermarkManagementWindowColors() {
        guard let wmWin = watermarkManagementWindow, wmWin.isVisible, let contentView = wmWin.contentView else { return }

        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)

        // Update title bar color
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        wmWin.backgroundColor = titleBarColor

        // Update appearance explicitly without animations
        let savedBehavior = wmWin.animationBehavior
        wmWin.animationBehavior = .none
        if #available(macOS 10.14, *) {
            wmWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
        wmWin.animationBehavior = savedBehavior

        // Update content background without implicit animations
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.layer?.backgroundColor = bgColor.cgColor
        CATransaction.commit()

        // Update all labels and buttons
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        for subview in contentView.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.textColor = textColor
            } else if let button = subview as? NSButton {
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
                button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs)
            }
        }
    }

    private func updateDropViewColor() {
        let color: NSColor
        let mode = currentMode

        // If auto mode, check system appearance
        if mode == .auto {
            let isDark = isSystemDarkAppearance()
            color = isDark ? NSColor.black : NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
        } else if mode == .night {
            color = NSColor.black
        } else {
            color = NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0) // Lighter gray
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
        // Reset overwrite/skip flags for new batch
        self.overwriteAllFiles = false
        self.skipAllExisting = false

        // Save current selections to UserDefaults
        UserDefaults.standard.set(self.selectedFormat, forKey: "selectedFormatSegment")

        // Move file I/O to background queue to keep main thread responsive
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var mxfFiles: [URL] = []
            var proxyFolderURL: URL
            var proxyFolderName: String

            // Check if url is a file or folder
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                // It's a folder - use existing behavior
                let folderName = url.lastPathComponent
                let parentURL = url.deletingLastPathComponent()
                proxyFolderName = "\(folderName) proxies"
                proxyFolderURL = parentURL.appendingPathComponent(proxyFolderName)

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
                proxyFolderName = "m2p-proxies"
                proxyFolderURL = parentURL.appendingPathComponent(proxyFolderName)
                mxfFiles = [url]
            }

            // Capture values for use in closures
            let finalProxyFolderURL = proxyFolderURL
            let finalProxyFolderName = proxyFolderName
            let finalMxfFiles = mxfFiles

            // Show destination dialog on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let mainWindow = self.window else { return }

                let alert = NSAlert()
                alert.messageText = "Use default destination or select a custom destination?"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Default")
                alert.addButton(withTitle: "Select Destination")
                alert.beginSheetModal(for: mainWindow) { [weak self] response in
                    guard let self = self else { return }

                    var destinationURL = finalProxyFolderURL

                    if response == .alertSecondButtonReturn {
                        // User chose to select destination
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select"
                        panel.message = "Choose destination folder for proxies"

                        let panelShowTime = Date()
                        if panel.runModal() == .OK, let selectedURL = panel.url {
                            // Check if folder was just created (creation date after panel was shown)
                            var isNewlyCreated = false
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: selectedURL.path),
                               let creationDate = attrs[.creationDate] as? Date,
                               creationDate > panelShowTime {
                                isNewlyCreated = true
                            }

                            if isNewlyCreated {
                                // User created a new folder - use it directly
                                destinationURL = selectedURL
                            } else {
                                // Existing folder - create proxy subfolder inside
                                destinationURL = selectedURL.appendingPathComponent(finalProxyFolderName)
                            }
                        } else {
                            // User cancelled - abort
                            completion()
                            return
                        }
                    }

                    // Continue on background thread
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                        } catch {
                            print("Error: \(error)")
                            DispatchQueue.main.async { completion() }
                            return
                        }

                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.encodingPathLabel?.stringValue = "Encoding to: \(destinationURL.path)"
                            self.processNextFile(index: 0, mxfFiles: finalMxfFiles, proxyFolderURL: destinationURL, outputFormat: outputFormat, completion: completion)
                        }
                    }
                }
            }
        }
    }

    private func processNextFile(index: Int, mxfFiles: [URL], proxyFolderURL: URL, outputFormat: OutputFormat, forceOverwrite: Bool = false, completion: @escaping @Sendable () -> Void) {
        guard index < mxfFiles.count else {
            print("Conversion complete: \(proxyFolderURL.path)")
            self.encodingPathLabel?.stringValue = "Encoded to: \(proxyFolderURL.path)"
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

        // Initialize log file
        let logURL = proxyFolderURL.appendingPathComponent("conversion_log.txt")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        // Check if output file already exists (unless forceOverwrite is true)
        if !forceOverwrite && FileManager.default.fileExists(atPath: outputFileURL.path) {
            // If user already chose "Skip All", skip this file
            if self.skipAllExisting {
                self.appendLog(logURL: logURL, entry: "SKIPPED (already exists): \(mxfFile.lastPathComponent)\n\n")
                self.totalClipsQueued -= 1
                self.updateDropZoneAvailability()
                self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                return
            }

            // If user hasn't chosen "Overwrite All", ask what to do
            if !self.overwriteAllFiles {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.showDuplicateFileAlert(fileName: outputFileName) { action in
                        switch action {
                        case .overwrite:
                            self.continueProcessing(index: index, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, outputFileURL: outputFileURL, shouldOverwrite: true, completion: completion)
                        case .skip:
                            self.appendLog(logURL: logURL, entry: "SKIPPED (already exists): \(mxfFile.lastPathComponent)\n\n")
                            self.totalClipsQueued -= 1
                            self.updateDropZoneAvailability()
                            self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                        case .overwriteAll:
                            self.overwriteAllFiles = true
                            self.continueProcessing(index: index, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, outputFileURL: outputFileURL, shouldOverwrite: true, completion: completion)
                        case .skipAll:
                            self.skipAllExisting = true
                            self.appendLog(logURL: logURL, entry: "SKIPPED (already exists): \(mxfFile.lastPathComponent)\n\n")
                            self.totalClipsQueued -= 1
                            self.updateDropZoneAvailability()
                            self.processNextFile(index: index + 1, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, completion: completion)
                        case .cancel:
                            // Cancel the entire batch
                            self.appendLog(logURL: logURL, entry: "CANCELLED by user\n\n")
                            self.totalClipsQueued = 0
                            self.updateDropZoneAvailability()
                            completion()
                        }
                    }
                }
                return
            }
        }

        // Find watermark in Resources
        let watermarkURL = Bundle.main.resourceURL?.appendingPathComponent("watermark.png")
        let watermarkEnabled = UserDefaults.standard.bool(forKey: "watermarkEnabled")
        let watermarkMode = UserDefaults.standard.string(forKey: "watermarkMode") ?? "default"
        let customWatermarkText = UserDefaults.standard.string(forKey: "watermarkCustomText") ?? ""
        let hasDefaultWatermark = watermarkEnabled && watermarkMode == "default" && watermarkURL != nil && FileManager.default.fileExists(atPath: watermarkURL?.path ?? "")
        let hasCustomTextWatermark = watermarkEnabled && watermarkMode == "custom" && !customWatermarkText.isEmpty
        let hasWatermark = hasDefaultWatermark || hasCustomTextWatermark

        // Debug log watermark settings
        appendLog(logURL: logURL, entry: "Watermark settings: enabled=\(watermarkEnabled), mode=\(watermarkMode), customText='\(customWatermarkText)', hasDefault=\(hasDefaultWatermark), hasCustomText=\(hasCustomTextWatermark)\n")

        // Escape text for ffmpeg drawtext filter (for Process, not shell)
        // Only need single backslash escapes when not going through a shell
        let escapedCustomText = customWatermarkText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")

        // Helper to escape file paths for ffmpeg filter syntax (Process, not shell)
        func escapePathForFFmpegFilter(_ path: String) -> String {
            return path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: ":", with: "\\:")
        }

        // Font file for drawtext filter on macOS (must be specified explicitly)
        let fontFile = escapePathForFFmpegFilter("/System/Library/Fonts/Helvetica.ttc")

        let ffmpegURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ffmpeg")
        let debugPath = ffmpegURL?.path ?? "nil"
        let debugLog = "Using ffmpeg at: \(debugPath)\n"
        appendLog(logURL: logURL, entry: debugLog)

        // Get video dimensions using ffmpeg (AVFoundation can't read MXF)
        var videoWidth: Int = 0
        if let ffmpegPath = ffmpegURL?.path {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: ffmpegPath)
            probe.arguments = ["-i", mxfFile.path, "-hide_banner"]
            let pipe = Pipe()
            probe.standardError = pipe  // ffmpeg outputs info to stderr
            try? probe.run()
            probe.waitUntilExit()
            if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                // Parse "1234x5678" from output
                let pattern = #"(\d{3,5})x(\d{3,5})"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                   let widthRange = Range(match.range(at: 1), in: output) {
                    videoWidth = Int(output[widthRange]) ?? 0
                }
            }
        }
        appendLog(logURL: logURL, entry: "Detected video width: \(videoWidth)\n")

        // Use software encoder for oversized videos (VideoToolbox H.264 max is ~4096 width)
        let useHardwareEncoder = videoWidth > 0 && videoWidth <= 4096
        let h264Codec = useHardwareEncoder ? "h264_videotoolbox" : "libx264"
        let h264PresetArgs = useHardwareEncoder ? [] : ["-preset", "fast"]
        if !useHardwareEncoder {
            appendLog(logURL: logURL, entry: "Using software encoder (libx264) - width \(videoWidth) exceeds 4096 or unknown\n")
        }
        let quickTimeCodecArgs = ["-c:v", h264Codec] + h264PresetArgs + ["-b:v", "10M", "-pix_fmt", "yuv420p"]

        let mxfCodecArgs = [
            "-c:v", "mpeg2video",
            "-b:v", "45M",
            "-maxrate", "45M",
            "-bufsize", "90M"
        ]

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
                        if hasDefaultWatermark {
                            // Build filter chain with optional LUT and image watermark
                            var filterChain = "[0:v]"
                            if hasLUT {
                                filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                            }
                            filterChain += "scale=-1:-1:flags=bicubic:out_color_matrix=bt709,format=yuv420p[v0];[1:v]scale=-1:160,format=rgba,colorchannelmixer=aa=0.5[wm];[v0][wm]overlay=W-w-10:H-h-10[v]"

                            args = [
                                "-i", intermediateURL.path,
                                "-i", watermarkURL!.path,
                                "-i", mxfFile.path,
                                "-filter_complex", filterChain,
                                "-map", "2:d?",
                                "-c:d", "copy",
                                "-map", "[v]",
                                "-map", "2:a?",
                                "-c:v", h264Codec,
                                "-b:v", "10M",
                                "-c:a", "copy",
                                "-map_metadata:s:a", "2:s:a",
                                "-sn",
                                outputFileURL.path
                            ]
                        } else if hasCustomTextWatermark {
                            // Build filter chain with optional LUT and custom text watermark
                            var filterChain = ""
                            if hasLUT {
                                filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                            }
                            // Custom text: centered horizontally, 10% up from bottom, white at 50% opacity
                            // Font size: 144 for height > 1800, 72 otherwise
                            filterChain += "drawtext=fontfile=\(fontFile):text=\(escapedCustomText):fontsize=if(gt(h\\,1800)\\,144\\,72):fontcolor=white@0.5:x=(w-text_w)/2:y=h*9/10-text_h"

                            self.appendLog(logURL: logURL, entry: "MOV->QT CUSTOM TEXT PATH: filterChain=\(filterChain)\n")

                            args = [
                                "-i", intermediateURL.path,
                                "-i", mxfFile.path,
                                "-vf", filterChain,
                                "-map", "1:d?",
                                "-c:d", "copy",
                                "-map", "0:v",
                                "-map", "1:a?",
                                "-c:v", h264Codec,
                                "-b:v", "10M",
                                "-c:a", "copy",
                                "-map_metadata:s:a", "1:s:a",
                                "-sn",
                                outputFileURL.path
                            ]
                        } else {
                            // No watermark, but may have LUT
                            if hasLUT {
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                    "-vf", "lut3d=file=\(escapePathForFFmpegFilter(lutPath!))",
                                    "-map", "1:d?",
                                    "-c:d", "copy",
                                    "-map", "0:v",
                                    "-map", "1:a?",
                                    "-c:v", h264Codec,
                                    "-b:v", "10M",
                                    "-c:a", "copy",
                                    "-map_metadata:s:a", "1:s:a",
                                    "-sn",
                                    outputFileURL.path
                                ]
                            } else {
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                    "-map", "1:d?",
                                    "-c:d", "copy",
                                    "-map", "0:v",
                                    "-map", "1:a?",
                                    "-c:v", h264Codec,
                                    "-b:v", "10M",
                                    "-c:a", "copy",
                                    "-map_metadata:s:a", "1:s:a",
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
                // Single-pass for MXF files
                // Check for LUT
                let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
                let lutFilename = UserDefaults.standard.string(forKey: "lutFilePath")
                let lutPath = lutFilename != nil ? self.getLUTDirectoryURL().appendingPathComponent(lutFilename!).path : nil
                let hasLUT = lutEnabled && lutPath != nil && FileManager.default.fileExists(atPath: lutPath!)
                self.appendLog(logURL: logURL, entry: "MXF->QT: LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")

                var args = (forceOverwrite || self.overwriteAllFiles) ? ["-y", "-i", mxfFile.path] : ["-i", mxfFile.path]
                var videoFilterArgs: [String]
                var videoMapArgs: [String]

                self.appendLog(logURL: logURL, entry: "MXF->QT: Watermark check: hasDefaultWatermark=\(hasDefaultWatermark), hasCustomTextWatermark=\(hasCustomTextWatermark), escapedCustomText='\(escapedCustomText)'\n")

                if hasDefaultWatermark {
                    // Add watermark input
                    args += ["-i", watermarkURL!.path]

                    // Build filter chain with optional LUT and image watermark
                    var filterChain = "[0:v]"
                    if hasLUT {
                        filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                    }
                    filterChain += "scale=-1:-1:flags=bicubic:out_color_matrix=bt709,format=yuv420p[v0];[1:v]scale=-1:160,format=rgba,colorchannelmixer=aa=0.5[wm];[v0][wm]overlay=W-w-10:H-h-10[v]"

                    videoFilterArgs = ["-filter_complex", filterChain]
                    videoMapArgs = ["-map", "[v]"]
                } else if hasCustomTextWatermark {
                    // Build filter chain with optional LUT and custom text watermark
                    var filterChain = ""
                    if hasLUT {
                        filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                    }
                    // Custom text: centered horizontally, 10% up from bottom, white at 50% opacity
                    filterChain += "drawtext=fontfile=\(fontFile):text=\(escapedCustomText):fontsize=if(gt(h\\,1800)\\,144\\,72):fontcolor=white@0.5:x=(w-text_w)/2:y=h*9/10-text_h"

                    self.appendLog(logURL: logURL, entry: "MXF->QT CUSTOM TEXT: filterChain=\(filterChain)\n")

                    videoFilterArgs = ["-vf", filterChain]
                    videoMapArgs = ["-map", "0:v"]
                } else if hasLUT {
                    // LUT only, no watermark
                    videoFilterArgs = ["-vf", "lut3d=file=\(escapePathForFFmpegFilter(lutPath!))"]
                    videoMapArgs = ["-map", "0:v"]
                } else {
                    // No watermark, no LUT
                    videoFilterArgs = []
                    videoMapArgs = ["-map", "0:v"]
                }

                args += videoFilterArgs
                // Map data/timecode track FIRST to get track ID 1, pushing video to ID 2 and audio to IDs 3-6
                args += ["-map", "0:d?", "-c:d", "copy"]
                args += videoMapArgs
                args += quickTimeCodecArgs
                args += [
                    "-map", "0:a?",
                    "-c:a", "copy",
                    "-map_metadata", "0",
                    "-sn",
                    outputFileURL.path
                ]

                self.appendLog(logURL: logURL, entry: "MXF->QT FULL ARGS: \(args.joined(separator: " "))\n")

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
            // Two-step process for MXF output
            // Check for LUT
            let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
            let lutFilename = UserDefaults.standard.string(forKey: "lutFilePath")
            let lutPath = lutFilename != nil ? self.getLUTDirectoryURL().appendingPathComponent(lutFilename!).path : nil
            let hasLUT = lutEnabled && lutPath != nil && FileManager.default.fileExists(atPath: lutPath!)
            self.appendLog(logURL: logURL, entry: "MXF output: LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")

            // Step 1: Create intermediate video with LUT and/or watermark
            let tempVideoURL = proxyFolderURL.appendingPathComponent(".\(mxfFile.deletingPathExtension().lastPathComponent)_temp.mov")
            var args1 = (forceOverwrite || self.overwriteAllFiles) ? ["-y", "-i", mxfFile.path] : ["-i", mxfFile.path]
            var videoFilterArgs: [String]
            var videoMapArgs: [String]

            if hasDefaultWatermark {
                // Add watermark input
                args1 += ["-i", watermarkURL!.path]

                // Build filter chain with optional LUT and image watermark
                var filterChain = "[0:v]"
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                filterChain += "scale=-1:-1:flags=bicubic:out_color_matrix=bt709,format=yuv420p[v0];[1:v]scale=-1:160,format=rgba,colorchannelmixer=aa=0.5[wm];[v0][wm]overlay=W-w-10:H-h-10[v]"

                videoFilterArgs = ["-filter_complex", filterChain]
                videoMapArgs = ["-map", "[v]"]
            } else if hasCustomTextWatermark {
                // Build filter chain with optional LUT and custom text watermark
                var filterChain = ""
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                // Custom text: centered horizontally, 10% up from bottom, white at 50% opacity
                filterChain += "drawtext=fontfile=\(fontFile):text=\(escapedCustomText):fontsize=if(gt(h\\,1800)\\,144\\,72):fontcolor=white@0.5:x=(w-text_w)/2:y=h*9/10-text_h"

                videoFilterArgs = ["-vf", filterChain]
                videoMapArgs = ["-map", "0:v"]
            } else if hasLUT {
                // LUT only, no watermark
                videoFilterArgs = ["-vf", "lut3d=file=\(escapePathForFFmpegFilter(lutPath!))"]
                videoMapArgs = ["-map", "0:v"]
            } else {
                // No watermark, no LUT
                videoFilterArgs = []
                videoMapArgs = ["-map", "0:v"]
            }

            args1 += videoFilterArgs
            args1 += videoMapArgs
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

                    // Step 2: Replace video in original MXF with processed video
                    var args2 = (forceOverwrite || self.overwriteAllFiles) ? ["-y"] : []
                    args2 += [
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

    private enum DuplicateFileAction {
        case overwrite
        case skip
        case overwriteAll
        case skipAll
        case cancel
    }

    private func showDuplicateFileAlert(fileName: String, completion: @escaping (DuplicateFileAction) -> Void) {
        let alert = NSAlert()
        alert.messageText = "File Already Exists"
        alert.informativeText = "The file \"\(fileName)\" already exists in the output folder."
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Overwrite All")
        alert.addButton(withTitle: "Skip All")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  // Overwrite
            completion(.overwrite)
        case .alertSecondButtonReturn: // Skip
            completion(.skip)
        case .alertThirdButtonReturn:  // Overwrite All
            completion(.overwriteAll)
        case NSApplication.ModalResponse(rawValue: 1003): // Skip All
            completion(.skipAll)
        default: // Cancel
            completion(.cancel)
        }
    }

    private func continueProcessing(index: Int, mxfFiles: [URL], proxyFolderURL: URL, outputFormat: OutputFormat, outputFileURL: URL, shouldOverwrite: Bool, completion: @escaping @Sendable () -> Void) {
        // Continue processing with forceOverwrite flag to bypass duplicate check
        self.processNextFile(index: index, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, forceOverwrite: shouldOverwrite, completion: completion)
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

    // Check whether a URL is already queued or active
    private func isDuplicateJob(_ url: URL) -> Bool {
        if let active = activeJob, active == url { return true }
        return jobQueue.contains(where: { $0 == url })
    }

    // Start the next job if we're not already processing
    private func startNextJobIfNeeded() {
        guard !isProcessing, !jobQueue.isEmpty else { return }
        let next = jobQueue.removeFirst()
        activeJob = next
        isProcessing = true
        let fmt = currentOutputFormat()
        processFolder(next, outputFormat: fmt) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isProcessing = false
                self.activeJob = nil
                // Continue with remaining jobs
                self.startNextJobIfNeeded()
            }
        }
    }

    // Open LUT management window
    @objc func selectLUT() {
        if lutManagementWindow == nil {
            guard let mainWindow = window else { return }
            let windowSize = NSSize(width: 500, height: 400)
            let mainOrigin = mainWindow.frame.origin
            let windowOrigin = NSPoint(x: mainOrigin.x + 50, y: mainOrigin.y + 50)

            let lutWin = NSWindow(
                contentRect: NSRect(origin: windowOrigin, size: windowSize),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            lutWin.title = "Manage LUTs"
            lutWin.titlebarAppearsTransparent = true
            lutWin.isRestorable = false

            // Match background color to main window using current mode
            let isDark: Bool
            if currentMode == .auto {
                isDark = isSystemDarkAppearance()
            } else if currentMode == .night {
                isDark = true
            } else {
                isDark = false
            }

            // Set window background color for title bar first
            let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
            lutWin.backgroundColor = titleBarColor

            // Set appearance explicitly
            if #available(macOS 10.14, *) {
                lutWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            }

            let contentView = NSView()
            contentView.wantsLayer = true

            if isDark {
                contentView.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
            } else {
                contentView.layer?.backgroundColor = NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0).cgColor
            }

            // Title label
            let titleLabel = NSTextField(labelWithString: "LUT Library")
            titleLabel.frame = NSRect(x: 20, y: 360, width: 200, height: 24)
            titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
            titleLabel.textColor = formatLabel?.textColor ?? NSColor.labelColor
            contentView.addSubview(titleLabel)

            // Scroll view for LUT list
            let scrollView = NSScrollView(frame: NSRect(x: 20, y: 80, width: 460, height: 260))
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.borderType = .lineBorder

            // Set scroll view background to match list
            let listBgColor = isDark ? NSColor.black : NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
            scrollView.backgroundColor = listBgColor

            let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: 260))
            listView.wantsLayer = true
            listView.layer?.backgroundColor = listBgColor.cgColor

            // Populate LUT list
            let luts = getAvailableLUTs()
            var yPos: CGFloat = 0  // Start from top with flipped coordinates

            for (index, lutName) in luts.enumerated() {
                let rowView = NSView(frame: NSRect(x: 0, y: yPos, width: 440, height: 30))

                // LUT name label - with flipped coordinates, y=5 is 5 pixels from TOP
                let nameLabel = NSTextField(labelWithString: lutName)
                nameLabel.frame = NSRect(x: 10, y: 5, width: 300, height: 20)
                let lutTextColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
                nameLabel.textColor = lutTextColor
                nameLabel.font = NSFont.systemFont(ofSize: 12)
                nameLabel.alignment = .left
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.cell?.usesSingleLineMode = true
                nameLabel.cell?.truncatesLastVisibleLine = true
                // Try to control vertical alignment
                if let cell = nameLabel.cell {
                    cell.controlSize = .regular
                }
                rowView.addSubview(nameLabel)

                // Rename button (pencil icon)
                let renameButton = NSButton(frame: NSRect(x: 360, y: 2, width: 30, height: 24))
                if #available(macOS 11.0, *) {
                    if let pencilImage = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename") {
                        renameButton.image = pencilImage
                        renameButton.imageScaling = .scaleProportionallyDown
                    } else {
                        renameButton.title = "✏️"
                    }
                } else {
                    renameButton.title = "✏️"
                }
                renameButton.bezelStyle = .regularSquare
                renameButton.isBordered = true
                renameButton.tag = index
                renameButton.target = self
                renameButton.action = #selector(renameLUT(_:))
                renameButton.identifier = NSUserInterfaceItemIdentifier(lutName)
                renameButton.toolTip = "Rename LUT"
                rowView.addSubview(renameButton)

                // Delete button (trash icon)
                let deleteButton = NSButton(frame: NSRect(x: 395, y: 2, width: 30, height: 24))
                if #available(macOS 11.0, *) {
                    if let trashImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
                        deleteButton.image = trashImage
                        deleteButton.imageScaling = .scaleProportionallyDown
                    } else {
                        deleteButton.title = "🗑"
                    }
                } else {
                    deleteButton.title = "🗑"
                }
                deleteButton.bezelStyle = .regularSquare
                deleteButton.isBordered = true
                deleteButton.tag = index
                deleteButton.target = self
                deleteButton.action = #selector(deleteLUT(_:))
                deleteButton.identifier = NSUserInterfaceItemIdentifier(lutName)
                deleteButton.toolTip = "Delete LUT"
                rowView.addSubview(deleteButton)

                listView.addSubview(rowView)
                yPos += 30  // Increment for flipped coordinates (top to bottom)
            }

            // Adjust list view height
            if luts.count * 30 > 260 {
                listView.frame = NSRect(x: 0, y: 0, width: 440, height: CGFloat(luts.count * 30))
            }

            scrollView.documentView = listView
            contentView.addSubview(scrollView)

            // Button text color based on mode - match the Output label color
            let buttonTextColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(white: 0.2, alpha: 1.0)

            // Add LUT button
            let addButton = NSButton(frame: NSRect(x: 20, y: 40, width: 120, height: 28))
            addButton.title = "Add LUT..."
            addButton.bezelStyle = .rounded
            addButton.target = self
            addButton.action = #selector(selectLUTFile)
            if #available(macOS 10.14, *) {
                addButton.contentTintColor = buttonTextColor
            }
            let addAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            addButton.attributedTitle = NSAttributedString(string: addButton.title, attributes: addAttrs)
            contentView.addSubview(addButton)

            // Open Folder button
            let openFolderButton = NSButton(frame: NSRect(x: 150, y: 40, width: 140, height: 28))
            openFolderButton.title = "Open in Finder"
            openFolderButton.bezelStyle = .rounded
            openFolderButton.target = self
            openFolderButton.action = #selector(openLUTFolder)
            if #available(macOS 10.14, *) {
                openFolderButton.contentTintColor = buttonTextColor
            }
            let openAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            openFolderButton.attributedTitle = NSAttributedString(string: openFolderButton.title, attributes: openAttrs)
            contentView.addSubview(openFolderButton)

            // Close button
            let closeButton = NSButton(frame: NSRect(x: 360, y: 40, width: 120, height: 28))
            closeButton.title = "Close"
            closeButton.bezelStyle = .rounded
            closeButton.target = self
            closeButton.action = #selector(closeLUTManagement)
            if #available(macOS 10.14, *) {
                closeButton.contentTintColor = buttonTextColor
            }
            let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            closeButton.attributedTitle = NSAttributedString(string: closeButton.title, attributes: closeAttrs)
            contentView.addSubview(closeButton)

            lutWin.contentView = contentView
            lutWin.delegate = self
            self.lutManagementWindow = lutWin
        }

        lutManagementWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func deleteLUT(_ sender: NSButton) {
        guard let lutName = sender.identifier?.rawValue else { return }

        let alert = NSAlert()
        alert.messageText = "Delete LUT"
        alert.informativeText = "Are you sure you want to delete '\(lutName)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: lutManagementWindow!) { response in
            if response == .alertFirstButtonReturn {
                let lutDir = self.getLUTDirectoryURL()
                let lutURL = lutDir.appendingPathComponent(lutName)

                do {
                    try FileManager.default.removeItem(at: lutURL)

                    // If this was the selected LUT, clear the selection
                    if UserDefaults.standard.string(forKey: "lutFilePath") == lutName {
                        UserDefaults.standard.removeObject(forKey: "lutFilePath")
                        UserDefaults.standard.set(false, forKey: "lutEnabled")
                        self.lutCheckbox?.state = .off
                        self.lutLabel?.stringValue = ""
                    }

                    // Refresh the window
                    self.closeLUTManagement()
                    self.selectLUT()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "Failed to delete LUT: \(error.localizedDescription)"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
    }

    @objc private func renameLUT(_ sender: NSButton) {
        guard let oldLutName = sender.identifier?.rawValue else { return }

        let alert = NSAlert()
        alert.messageText = "Rename LUT"
        alert.informativeText = "Enter a new name for '\(oldLutName)':"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        // Add text field for new name
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = oldLutName.replacingOccurrences(of: ".cube", with: "")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: lutManagementWindow!) { response in
            if response == .alertFirstButtonReturn {
                var newLutName = textField.stringValue.trimmingCharacters(in: .whitespaces)

                // Ensure .cube extension
                if !newLutName.hasSuffix(".cube") {
                    newLutName += ".cube"
                }

                // Validate new name
                guard !newLutName.isEmpty && newLutName != oldLutName else { return }

                let lutDir = self.getLUTDirectoryURL()
                let oldURL = lutDir.appendingPathComponent(oldLutName)
                let newURL = lutDir.appendingPathComponent(newLutName)

                // Check if new name already exists
                if FileManager.default.fileExists(atPath: newURL.path) {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "A LUT with the name '\(newLutName)' already exists."
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                    return
                }

                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)

                    // If this was the selected LUT, update the selection
                    if UserDefaults.standard.string(forKey: "lutFilePath") == oldLutName {
                        UserDefaults.standard.set(newLutName, forKey: "lutFilePath")
                        self.lutLabel?.stringValue = newLutName
                    }

                    // Refresh the window
                    self.closeLUTManagement()
                    self.selectLUT()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "Failed to rename LUT: \(error.localizedDescription)"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
    }

    @objc private func openLUTFolder() {
        let lutDir = getLUTDirectoryURL()
        NSWorkspace.shared.activateFileViewerSelecting([lutDir])
    }

    @objc private func closeLUTManagement() {
        lutManagementWindow?.orderOut(nil)
        lutManagementWindow = nil
    }

    @objc func showWatermarkManagement() {
        if watermarkManagementWindow == nil {
            guard let mainWindow = window else { return }
            let windowSize = NSSize(width: 400, height: 220)
            let mainOrigin = mainWindow.frame.origin
            let windowOrigin = NSPoint(x: mainOrigin.x + 100, y: mainOrigin.y + 100)

            let wmWin = NSWindow(
                contentRect: NSRect(origin: windowOrigin, size: windowSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            wmWin.title = "Watermark Settings"
            wmWin.titlebarAppearsTransparent = true
            wmWin.isRestorable = false

            let isDark: Bool
            if currentMode == .auto {
                isDark = isSystemDarkAppearance()
            } else if currentMode == .night {
                isDark = true
            } else {
                isDark = false
            }

            let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
            wmWin.backgroundColor = titleBarColor

            if #available(macOS 10.14, *) {
                wmWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            }

            let contentView = NSView()
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = (isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)).cgColor

            let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

            // Title label
            let titleLabel = NSTextField(labelWithString: "Watermark Type")
            titleLabel.frame = NSRect(x: 20, y: 175, width: 200, height: 24)
            titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
            titleLabel.textColor = textColor
            contentView.addSubview(titleLabel)

            // Load current mode from UserDefaults
            let currentWatermarkMode = UserDefaults.standard.string(forKey: "watermarkMode") ?? "default"
            let currentCustomText = UserDefaults.standard.string(forKey: "watermarkCustomText") ?? ""

            // Radio button: Default watermark
            let defaultRadio = NSButton(radioButtonWithTitle: "Default watermark (image)", target: self, action: #selector(watermarkRadioClicked(_:)))
            defaultRadio.frame = NSRect(x: 20, y: 140, width: 300, height: 20)
            defaultRadio.tag = 0
            defaultRadio.identifier = NSUserInterfaceItemIdentifier("defaultRadio")
            defaultRadio.state = (currentWatermarkMode == "default") ? .on : .off
            let defaultAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            defaultRadio.attributedTitle = NSAttributedString(string: defaultRadio.title, attributes: defaultAttrs)
            contentView.addSubview(defaultRadio)

            // Radio button: Custom text
            let customRadio = NSButton(radioButtonWithTitle: "Custom text", target: self, action: #selector(watermarkRadioClicked(_:)))
            customRadio.frame = NSRect(x: 20, y: 110, width: 150, height: 20)
            customRadio.tag = 1
            customRadio.identifier = NSUserInterfaceItemIdentifier("customRadio")
            customRadio.state = (currentWatermarkMode == "custom") ? .on : .off
            let customAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            customRadio.attributedTitle = NSAttributedString(string: customRadio.title, attributes: customAttrs)
            contentView.addSubview(customRadio)

            // Text field for custom text
            let textField = NSTextField(frame: NSRect(x: 20, y: 75, width: 360, height: 24))
            textField.stringValue = currentCustomText
            textField.placeholderString = "Enter custom watermark text (max 48 characters)"
            textField.isEnabled = (currentWatermarkMode == "custom")
            textField.identifier = NSUserInterfaceItemIdentifier("watermarkTextField")
            textField.target = self
            textField.action = #selector(watermarkTextFieldChanged(_:))
            contentView.addSubview(textField)

            // Max length hint
            let maxLenLabel = NSTextField(labelWithString: "(48 characters max.)")
            maxLenLabel.frame = NSRect(x: 240, y: 50, width: 140, height: 16)
            maxLenLabel.font = NSFont.systemFont(ofSize: 11)
            maxLenLabel.textColor = NSColor.secondaryLabelColor
            maxLenLabel.alignment = .right
            contentView.addSubview(maxLenLabel)

            // Cancel button
            let cancelButton = NSButton(frame: NSRect(x: 100, y: 15, width: 90, height: 28))
            cancelButton.title = "Cancel"
            cancelButton.bezelStyle = .rounded
            cancelButton.target = self
            cancelButton.action = #selector(cancelWatermarkManagement)
            let cancelAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            cancelButton.attributedTitle = NSAttributedString(string: cancelButton.title, attributes: cancelAttrs)
            contentView.addSubview(cancelButton)

            // Save button
            let saveButton = NSButton(frame: NSRect(x: 210, y: 15, width: 90, height: 28))
            saveButton.title = "Save"
            saveButton.bezelStyle = .rounded
            saveButton.target = self
            saveButton.action = #selector(saveWatermarkManagement)
            let saveAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            saveButton.attributedTitle = NSAttributedString(string: saveButton.title, attributes: saveAttrs)
            contentView.addSubview(saveButton)

            wmWin.contentView = contentView
            wmWin.delegate = self
            self.watermarkManagementWindow = wmWin
        }

        watermarkManagementWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func watermarkRadioClicked(_ sender: NSButton) {
        // Just update UI - enable/disable text field based on selection
        let isCustom = sender.tag == 1
        if let contentView = watermarkManagementWindow?.contentView {
            for subview in contentView.subviews {
                if let textField = subview as? NSTextField,
                   textField.identifier?.rawValue == "watermarkTextField" {
                    textField.isEnabled = isCustom
                }
            }
        }
    }

    @objc private func watermarkTextFieldChanged(_ sender: NSTextField) {
        // Enforce 48 character limit on commit
        if sender.stringValue.count > 48 {
            sender.stringValue = String(sender.stringValue.prefix(48))
        }
    }

    @objc private func saveWatermarkManagement() {
        guard let contentView = watermarkManagementWindow?.contentView else { return }

        // Find which radio is selected
        var mode = "default"
        var customText = ""

        for subview in contentView.subviews {
            if let radio = subview as? NSButton,
               radio.identifier?.rawValue == "customRadio",
               radio.state == .on {
                mode = "custom"
            }
            if let textField = subview as? NSTextField,
               textField.identifier?.rawValue == "watermarkTextField" {
                customText = textField.stringValue
                if customText.count > 48 {
                    customText = String(customText.prefix(48))
                }
            }
        }

        // Save to UserDefaults
        UserDefaults.standard.set(mode, forKey: "watermarkMode")
        UserDefaults.standard.set(customText, forKey: "watermarkCustomText")

        watermarkManagementWindow?.orderOut(nil)
        watermarkManagementWindow = nil
    }

    @objc private func cancelWatermarkManagement() {
        // Just close without saving
        watermarkManagementWindow?.orderOut(nil)
        watermarkManagementWindow = nil
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
            settingsWin.titlebarAppearsTransparent = true
            settingsWin.isRestorable = false

            // Match background color to main window using current mode
            let isDark: Bool
            if currentMode == .auto {
                isDark = isSystemDarkAppearance()
            } else if currentMode == .night {
                isDark = true
            } else {
                isDark = false
            }

            // Set window background color for title bar first
            let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
            settingsWin.backgroundColor = titleBarColor

            // Set appearance explicitly
            if #available(macOS 10.14, *) {
                settingsWin.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            }

            let mainLabelColor = formatLabel?.textColor ?? NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

            let watermarkButton = NSButton(frame: NSRect(x: 100, y: 220, width: 200, height: 28))
            watermarkButton.title = "Manage watermark"
            watermarkButton.bezelStyle = .rounded
            watermarkButton.target = self
            watermarkButton.action = #selector(showWatermarkManagement)
            let watermarkButtonAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: mainLabelColor]
            watermarkButton.attributedTitle = NSAttributedString(string: watermarkButton.title, attributes: watermarkButtonAttrs)

            let lutButton = NSButton(frame: NSRect(x: 100, y: 185, width: 200, height: 28))
            lutButton.title = "Manage LUTs"
            lutButton.bezelStyle = .rounded
            lutButton.target = self
            lutButton.action = #selector(selectLUT)
            // Set button text color to match main window's Output label color
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

            if isDark {
                contentView.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
            } else {
                contentView.layer?.backgroundColor = NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0).cgColor
            }

            contentView.addSubview(watermarkButton)
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

            // Add build number label at the bottom
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            let buildLabel = NSTextField(labelWithString: "Build: \(buildNumber)")
            buildLabel.frame = NSRect(x: 10, y: 5, width: 380, height: 12)
            buildLabel.font = NSFont.systemFont(ofSize: 9)
            buildLabel.textColor = NSColor.secondaryLabelColor
            buildLabel.alignment = .center
            contentView.addSubview(buildLabel)

            settingsWin.contentView = contentView
            settingsWin.delegate = self
            self.settingsWindow = settingsWin
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeSettings() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }
    
    // Removed LUT menu logic from settings page for clarity and to avoid conflicts.
    
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
