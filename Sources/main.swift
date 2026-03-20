
import AppKit
import AVFoundation
import StoreKit
import UniformTypeIdentifiers

let acceptedFormats: Set<String> = ["mxf", "mov", "mp4", "avi"]

let app = NSApplication.shared
@MainActor
func setup() {
    let delegate = AppDelegate()
    app.delegate = delegate
}

MainActor.assumeIsolated {
    setup()
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

class OrangeButton: NSButton {
    let orangeColor = NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0)
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
        self.bezelColor = nil
        self.contentTintColor = orangeColor
        self.title = self.title  // reset to plain title, letting contentTintColor style it
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

class ClickableLabel: NSTextField {
    var useHandCursor = false

    override func resetCursorRects() {
        if useHandCursor {
            addCursorRect(bounds, cursor: .pointingHand)
        } else {
            super.resetCursorRects()
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
            if exists && (isDir.boolValue || acceptedFormats.contains(ext)) {
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
            return exists && (isDir.boolValue || acceptedFormats.contains(ext))
        })
    }
}

@MainActor
protocol DropViewDelegate {
    func handleDrop(url: URL)
}

@MainActor
class StoreManager {
    static let productID = "com.frankcapria.pxf.pro"
    private var product: Product?
    private var updateTask: Task<Void, Never>?
    var onPurchaseUpdate: ((Bool) -> Void)?

    func fetchProduct() async {
        do {
            let products = try await Product.products(for: [StoreManager.productID])
            product = products.first
        } catch {

        }
    }

    func purchase() async -> Bool {
        if product == nil {

            await fetchProduct()
        }
        guard let product = product else {

            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()

                    onPurchaseUpdate?(true)
                    return true
                case .unverified(let transaction, _):
                    await transaction.finish()

                    onPurchaseUpdate?(true)
                    return true
                }
            case .userCancelled:

                return false
            case .pending:

                return false
            @unknown default:

                return false
            }
        } catch {

            return false
        }
    }

    func checkEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.productID == StoreManager.productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func listenForTransactions() {
        updateTask = Task {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    if transaction.productID == StoreManager.productID {
                        let entitled = transaction.revocationDate == nil
                        onPurchaseUpdate?(entitled)
                    }
                }
            }
        }
    }

    var displayPrice: String {
        product?.displayPrice ?? "$9.99"
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, DropViewDelegate {
    var window: NSWindow?
    weak var settingsWindow: NSWindow?
    weak var aboutWindow: NSWindow?
    weak var lutManagementWindow: NSWindow?
    weak var watermarkManagementWindow: NSWindow?
    private var formatPopup: NSPopUpButton?
    private var modePopup: NSPopUpButton?
    private var codecLabel: NSTextField?
    private var codecPopup: NSPopUpButton?
    private var selectedCodecIndex: Int = 0
    private var sizePopup: NSPopUpButton?
    private var selectedSizeIndex: Int = 0
    private var lutPopup: NSPopUpButton?
    private let sessionUUID = UUID().uuidString
    private var dropView: DropView?
    private var contentView: NSView?
    private var formatLabel: NSTextField?
    private var button: NSButton?
    private var queueCountLabel: NSTextField?
    private var watermarkCheckbox: NSButton?
    private var watermarkSetButton: NSButton?
    private var upgradeButton: NSButton?
    private var encodingSpinner: NSProgressIndicator?
    private var encodingLabel: NSTextField?
    private var lutCheckbox: NSButton?
    private var lutLabel: NSTextField?
    private var dropLabel: NSTextField?
    private var encodingPathLabel: ClickableLabel?
    private var encodingPathURL: URL?
    private var encodingPathPrefix: String?
    private var insideSourceButton: NSButton?
    private var chooseFolderButton: NSButton?
    private var destinationLabel: NSTextField?
    private var destinationPathLabel: NSTextField?
    private var selectedDestinationURL: URL?
    private var destinationAccessGranted: Bool = false
    private var dropBorderLayer: CAShapeLayer?
    private var didAutoHalfSize = false
    private var gearButton: NSButton?
    private var selectedFormat: Int = 0
    private var selectedMode: Int = 0
    private var jobQueue: [URL] = []
    private var activeJob: URL?
    private var isProcessing: Bool = false
    private var totalClipsQueued: Int = 0
    private var fileRelativePaths: [URL: String] = [:]
    private var isPremiumUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: "isPremiumUnlocked") }
        set { UserDefaults.standard.set(newValue, forKey: "isPremiumUnlocked") }
    }
    private var storeManager: StoreManager?
    private var overwriteAllFiles: Bool = false
    private var skipAllExisting: Bool = false

    private enum OutputFormat {
        case quickTime
        case mpeg4
        case mxf
    }

    private enum VideoCodec: Int, CaseIterable {
        case h265 = 0
        case h264 = 1
        case proresProxy = 2
        case dnxhrLB = 3
        case mpeg2 = 4

        var displayName: String {
            switch self {
            case .h265: return "H.265"
            case .h264: return "H.264"
            case .proresProxy: return "ProRes Proxy"
            case .dnxhrLB: return "DNxHR LB"
            case .mpeg2: return "MPEG-2"
            }
        }

        static func codecs(for format: OutputFormat) -> [VideoCodec] {
            switch format {
            case .quickTime:
                return [.h265, .h264, .proresProxy, .dnxhrLB]
            case .mpeg4:
                return [.h265, .h264]
            case .mxf:
                return [.mpeg2, .proresProxy, .dnxhrLB]
            }
        }
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
            contentRect: NSRect(x: 100, y: 100, width: 610, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "pxf"
        window.titlebarAppearsTransparent = true
        window.isRestorable = false
        window.minSize = NSSize(width: 610, height: 530)

        // Set initial appearance and colors based on mode
        let titleBarColor = isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) : NSColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0)
        window.backgroundColor = titleBarColor

        if #available(macOS 10.14, *) {
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }

        // Output format label and popup
        let formatLabel = NSTextField(labelWithString: "Output")
        formatLabel.frame = NSRect(x: 270, y: 486, width: 50, height: 20)
        formatLabel.autoresizingMask = [.minYMargin]
        self.formatLabel = formatLabel

        let formatPopup = NSPopUpButton(frame: NSRect(x: 325, y: 483, width: 150, height: 26))
        (formatPopup.cell as? NSPopUpButtonCell)?.autoenablesItems = false
        formatPopup.addItems(withTitles: ["QuickTime", "MPEG-4", "MXF"])
        formatPopup.selectItem(at: selectedFormat)
        formatPopup.target = self
        formatPopup.action = #selector(formatPopupChanged(_:))
        formatPopup.autoresizingMask = [.minYMargin]
        self.formatPopup = formatPopup

        // Destination label and popup
        let destinationLabel = NSTextField(labelWithString: "Save to")
        destinationLabel.frame = NSRect(x: 270, y: 453, width: 50, height: 20)
        destinationLabel.autoresizingMask = [.minYMargin]
        self.destinationLabel = destinationLabel

        let insideSourceButton = NSButton(frame: NSRect(x: 325, y: 450, width: 110, height: 26))
        insideSourceButton.title = "Source Folder"
        insideSourceButton.bezelStyle = .rounded
        insideSourceButton.target = self
        insideSourceButton.action = #selector(insideSourceFolderClicked(_:))
        insideSourceButton.autoresizingMask = [.minYMargin]
        self.insideSourceButton = insideSourceButton

        let chooseFolderButton = NSButton(frame: NSRect(x: 440, y: 450, width: 70, height: 26))
        chooseFolderButton.title = "Other..."
        chooseFolderButton.bezelStyle = .rounded
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolderClicked(_:))
        chooseFolderButton.autoresizingMask = [.minYMargin]
        self.chooseFolderButton = chooseFolderButton

        // Destination path label (below Save to row, same style as LUT label)
        let destinationPathLabel = NSTextField(labelWithString: "")
        destinationPathLabel.frame = NSRect(x: 270, y: 427, width: 305, height: 16)
        destinationPathLabel.font = NSFont.systemFont(ofSize: 13)
        destinationPathLabel.textColor = NSColor.secondaryLabelColor
        destinationPathLabel.autoresizingMask = [.minYMargin]
        self.destinationPathLabel = destinationPathLabel

        // Restore destination from UserDefaults
        let savedDestMode = UserDefaults.standard.integer(forKey: "destinationMode")
        if savedDestMode == 2, let bookmarkData = UserDefaults.standard.data(forKey: "destinationBookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(newBookmark, forKey: "destinationBookmark")
                    }
                }
                if url.startAccessingSecurityScopedResource() {
                    destinationAccessGranted = true
                    selectedDestinationURL = url
                    let path = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    destinationPathLabel.stringValue = path
                }
            }
        }
        if !destinationAccessGranted {
            UserDefaults.standard.set(1, forKey: "destinationMode")
            destinationPathLabel.stringValue = "Inside Source Folder"
        }

        // Codec label and popup
        let codecLabel = NSTextField(labelWithString: "Codec")
        codecLabel.frame = NSRect(x: 270, y: 392, width: 50, height: 20)
        codecLabel.autoresizingMask = [.minYMargin]
        self.codecLabel = codecLabel

        let codecPopup = NSPopUpButton(frame: NSRect(x: 325, y: 389, width: 150, height: 26))
        (codecPopup.cell as? NSPopUpButtonCell)?.autoenablesItems = false
        codecPopup.target = self
        codecPopup.action = #selector(codecPopupChanged(_:))
        codecPopup.autoresizingMask = [.minYMargin]
        self.codecPopup = codecPopup

        // Size label and popup
        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.frame = NSRect(x: 270, y: 359, width: 50, height: 20)
        sizeLabel.autoresizingMask = [.minYMargin]

        let sizePopup = NSPopUpButton(frame: NSRect(x: 325, y: 356, width: 150, height: 26))
        sizePopup.addItems(withTitles: ["Full", "Half"])
        selectedSizeIndex = UserDefaults.standard.integer(forKey: "selectedSizeIndex")
        sizePopup.selectItem(at: selectedSizeIndex)
        sizePopup.target = self
        sizePopup.action = #selector(sizePopupChanged(_:))
        sizePopup.autoresizingMask = [.minYMargin]
        self.sizePopup = sizePopup

        let button = NSButton(frame: NSRect(x: 170, y: 200, width: 270, height: 26))
        button.title = "Select Files or Folders to Encode..."
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(selectFolder)
        button.autoresizingMask = [.minYMargin]
        self.button = button

        let dropView = DropView()
        dropView.dropDelegate = self
        dropView.wantsLayer = true
        self.dropView = dropView
        updateDropViewColor()
        dropView.frame = NSRect(x: 50, y: 40, width: 500, height: 150)
        dropView.autoresizingMask = [.height]
        
        // Create dotted border using CAShapeLayer
        let borderLayer = CAShapeLayer()
        let borderPath = CGPath(rect: dropView.bounds, transform: nil)
        borderLayer.path = borderPath
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.0
        borderLayer.lineDashPattern = [2, 2]
        dropView.layer?.addSublayer(borderLayer)
        self.dropBorderLayer = borderLayer

        let dropLabel = NSTextField(labelWithString: "...Or Drag Files and Folders Here to Begin Encoding")
        dropLabel.frame = NSRect(x: 0, y: 110, width: 500, height: 30)
        dropLabel.font = NSFont.systemFont(ofSize: 13)
        dropLabel.alignment = .center
        dropLabel.autoresizingMask = [.minYMargin]
        dropView.addSubview(dropLabel)
        self.dropLabel = dropLabel

        let encodingPathLabel = ClickableLabel(labelWithString: "")
        encodingPathLabel.frame = NSRect(x: 0, y: 55, width: 500, height: 50)
        encodingPathLabel.font = NSFont.systemFont(ofSize: 16)
        encodingPathLabel.alignment = .center
        encodingPathLabel.maximumNumberOfLines = 2
        encodingPathLabel.autoresizingMask = [.minYMargin]
        dropView.addSubview(encodingPathLabel)
        self.encodingPathLabel = encodingPathLabel

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(encodingPathClicked))
        encodingPathLabel.addGestureRecognizer(clickGesture)

        let queueCountLabel = NSTextField(labelWithString: "Items in queue: 0")
        queueCountLabel.frame = NSRect(x: 0, y: 10, width: 500, height: 20)
        queueCountLabel.font = NSFont.systemFont(ofSize: 13)
        queueCountLabel.alignment = .center
        dropView.addSubview(queueCountLabel)
        self.queueCountLabel = queueCountLabel
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 610, height: 530))
        contentView.wantsLayer = true
          if let logoURL = Bundle.main.url(forResource: "pfx_only", withExtension: "png"),
              let logoImage = NSImage(contentsOf: logoURL) {
                let scaledSize = NSSize(width: logoImage.size.width * 0.20, height: logoImage.size.height * 0.20)
            logoImage.size = scaledSize
                let logoOrigin = NSPoint(x: 38, y: contentView.bounds.height - scaledSize.height - 50)
            let logoView = NSImageView(frame: NSRect(origin: logoOrigin, size: scaledSize))
            logoView.image = logoImage
            logoView.imageScaling = .scaleProportionallyUpOrDown
            logoView.autoresizingMask = [.maxXMargin, .minYMargin]
            contentView.addSubview(logoView)

            // Upgrade to Pro button (below logo, hidden when premium)
            let upgradeBtn = NSButton(frame: NSRect(x: 68, y: logoOrigin.y - 2, width: 140, height: 24))
            upgradeBtn.title = "Upgrade to Pro"
            upgradeBtn.bezelStyle = .rounded
            upgradeBtn.target = self
            upgradeBtn.action = #selector(showUpgradePrompt)
            upgradeBtn.autoresizingMask = [.maxXMargin, .minYMargin]
            contentView.addSubview(upgradeBtn)
            self.upgradeButton = upgradeBtn
        }

        // Encoding spinner (below Upgrade button, hidden by default)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        let spinnerSize: CGFloat = 48
        let spinnerX: CGFloat = 67
        let spinnerY: CGFloat = 290
        spinner.frame = NSRect(x: spinnerX, y: spinnerY, width: spinnerSize, height: spinnerSize)
        spinner.isHidden = true
        spinner.autoresizingMask = [.minYMargin]
        contentView.addSubview(spinner)
        self.encodingSpinner = spinner

        let encLabel = NSTextField(labelWithString: "Encoding...")
        encLabel.frame = NSRect(x: 123, y: 304, width: 100, height: 20)
        encLabel.font = NSFont.systemFont(ofSize: 13)
        encLabel.isHidden = true
        encLabel.autoresizingMask = [.minYMargin]
        contentView.addSubview(encLabel)
        self.encodingLabel = encLabel

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
        gearButton.autoresizingMask = [.minXMargin]
        self.gearButton = gearButton

        // Watermark checkbox
        let watermarkCheckbox = NSButton(checkboxWithTitle: "Apply watermark", target: self, action: #selector(watermarkCheckboxChanged(_:)))
        watermarkCheckbox.frame = NSRect(x: 270, y: 326, width: 140, height: 20)
        watermarkCheckbox.autoresizingMask = [.minYMargin]
        // Default to true on first launch
        if UserDefaults.standard.object(forKey: "watermarkEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "watermarkEnabled")
        }
        // Migrate "default" mode to "library" with bundled watermark
        let currentWMMode = UserDefaults.standard.string(forKey: "watermarkMode") ?? "default"
        if currentWMMode == "default" || UserDefaults.standard.object(forKey: "watermarkMode") == nil {
            UserDefaults.standard.set("library", forKey: "watermarkMode")
            if UserDefaults.standard.string(forKey: "watermarkLibraryFile") == nil {
                UserDefaults.standard.set(bundledWatermarkName, forKey: "watermarkLibraryFile")
            }
        }
        watermarkCheckbox.state = UserDefaults.standard.bool(forKey: "watermarkEnabled") ? .on : .off
        self.watermarkCheckbox = watermarkCheckbox

        let watermarkSetButton = NSButton(frame: NSRect(x: 410, y: 323, width: 60, height: 26))
        watermarkSetButton.title = "Set…"
        watermarkSetButton.bezelStyle = .rounded
        watermarkSetButton.target = self
        watermarkSetButton.action = #selector(showWatermarkManagement)
        let wmEnabled = UserDefaults.standard.bool(forKey: "watermarkEnabled")
        watermarkSetButton.isEnabled = wmEnabled
        watermarkSetButton.autoresizingMask = [.minYMargin]
        self.watermarkSetButton = watermarkSetButton

        // LUT checkbox and popup
        let lutCheckbox = NSButton(checkboxWithTitle: "Apply LUT", target: self, action: #selector(lutCheckboxChanged(_:)))
        lutCheckbox.frame = NSRect(x: 270, y: 293, width: 90, height: 20)
        lutCheckbox.autoresizingMask = [.minYMargin]
        self.lutCheckbox = lutCheckbox

        let lutPopup = NSPopUpButton(frame: NSRect(x: 360, y: 290, width: 215, height: 26))
        lutPopup.target = self
        lutPopup.action = #selector(lutPopupChanged(_:))
        lutPopup.autoresizingMask = [.minYMargin]
        self.lutPopup = lutPopup
        populateLUTPopup()

        // LUT filename label (below LUT row)
        let lutLabel = NSTextField(labelWithString: "")
        lutLabel.frame = NSRect(x: 270, y: 267, width: 305, height: 16)
        lutLabel.font = NSFont.systemFont(ofSize: 13)
        lutLabel.textColor = NSColor.secondaryLabelColor
        lutLabel.autoresizingMask = [.minYMargin]
        self.lutLabel = lutLabel

        // Check if LUT already selected and set initial states
        let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
        if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
            let lutPath = getLUTDirectoryURL().appendingPathComponent(savedLUT).path
            if FileManager.default.fileExists(atPath: lutPath) {
                lutCheckbox.state = lutEnabled ? .on : .off
                selectLUTInPopup(savedLUT)
                if lutEnabled {
                    lutLabel.stringValue = savedLUT
                    // Color will be set by updateWindowColors()
                }
            } else {
                // LUT file not found — keep checkbox/popup state, label stays empty
                lutCheckbox.state = lutEnabled ? .on : .off
            }
        }
        // Set initial enabled state for LUT popup
        lutPopup.isEnabled = lutEnabled
        
        contentView.addSubview(formatLabel)
        contentView.addSubview(formatPopup)
        contentView.addSubview(destinationLabel)
        contentView.addSubview(insideSourceButton)
        contentView.addSubview(chooseFolderButton)
        contentView.addSubview(destinationPathLabel)
        contentView.addSubview(codecLabel)
        contentView.addSubview(codecPopup)
        contentView.addSubview(sizeLabel)
        contentView.addSubview(sizePopup)
        contentView.addSubview(watermarkCheckbox)
        contentView.addSubview(watermarkSetButton)
        contentView.addSubview(lutCheckbox)
        contentView.addSubview(lutPopup)
        contentView.addSubview(lutLabel)
        contentView.addSubview(button)
        contentView.addSubview(dropView)
        contentView.addSubview(gearButton)
        self.contentView = contentView
        window.contentView = contentView
        window.delegate = self

        // Apply colors and premium restrictions after all views are added
        self.window = window
        applyPremiumRestrictions()
        updateModePopup()
        window.makeKeyAndOrderFront(nil)
        updateWindowColors()

        // Initialize StoreKit
        let store = StoreManager()
        store.onPurchaseUpdate = { [weak self] entitled in
            self?.isPremiumUnlocked = entitled
            self?.applyPremiumRestrictions()
        }
        self.storeManager = store
        Task {
            await store.fetchProduct()
            let entitled = await store.checkEntitlement()
            if entitled && !self.isPremiumUnlocked {
                self.isPremiumUnlocked = true
                self.applyPremiumRestrictions()
            } else if !entitled && self.isPremiumUnlocked {
                self.isPremiumUnlocked = false
                self.applyPremiumRestrictions()
            }
            store.listenForTransactions()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
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
        } else if sender === aboutWindow {
            aboutWindow?.orderOut(nil)
            aboutWindow = nil
            return false
        }

        // Allow main window to close normally (quits the app)
        return true
    }

    func windowDidResize(_ notification: Notification) {
        guard let dv = dropView else { return }
        dropBorderLayer?.path = CGPath(rect: dv.bounds, transform: nil)
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
            // Count MXF/MOV files in folder (recursive)
            if let enumerator = FileManager.default.enumerator(at: standardizedURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                var fileCount = 0
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if acceptedFormats.contains(ext) {
                        fileCount += 1
                    }
                }
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

        let isEncoding = totalClipsQueued > 0
        encodingSpinner?.isHidden = !isEncoding
        encodingLabel?.isHidden = !isEncoding
        if isEncoding {
            encodingSpinner?.startAnimation(nil)
        } else {
            encodingSpinner?.stopAnimation(nil)
        }
    }
    
    @objc func formatPopupChanged(_ sender: NSPopUpButton) {
        selectedFormat = sender.indexOfSelectedItem
        UserDefaults.standard.set(selectedFormat, forKey: "selectedFormatSegment")
        updateCodecPopup()
    }

    @objc func codecPopupChanged(_ sender: NSPopUpButton) {
        selectedCodecIndex = sender.indexOfSelectedItem
        UserDefaults.standard.set(selectedCodecIndex, forKey: "selectedCodecIndex_\(selectedFormat)")
    }

    @objc func sizePopupChanged(_ sender: NSPopUpButton) {
        selectedSizeIndex = sender.indexOfSelectedItem
        UserDefaults.standard.set(selectedSizeIndex, forKey: "selectedSizeIndex")
    }

    @objc func insideSourceFolderClicked(_ sender: NSButton) {
        if destinationAccessGranted {
            selectedDestinationURL?.stopAccessingSecurityScopedResource()
            destinationAccessGranted = false
        }
        selectedDestinationURL = nil
        UserDefaults.standard.set(1, forKey: "destinationMode")
        UserDefaults.standard.removeObject(forKey: "destinationBookmark")
        destinationPathLabel?.stringValue = "Inside Source Folder"
        destinationPathLabel?.textColor = NSColor.secondaryLabelColor
    }

    @objc func chooseFolderClicked(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose destination folder for proxies"

        if panel.runModal() == .OK, let url = panel.url {
            if destinationAccessGranted {
                selectedDestinationURL?.stopAccessingSecurityScopedResource()
                destinationAccessGranted = false
            }
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "destinationBookmark")
            }
            selectedDestinationURL = url
            UserDefaults.standard.set(2, forKey: "destinationMode")
            let path = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            destinationPathLabel?.stringValue = path
            updateDestinationPathLabelColor()
        }
    }

    private func updateDestinationPathLabelColor() {
        guard let label = destinationPathLabel, !label.stringValue.isEmpty else { return }
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        label.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
    }

    private func updateCodecPopup() {
        guard let popup = codecPopup else { return }
        popup.removeAllItems()
        let format = currentOutputFormat()
        let codecs = VideoCodec.codecs(for: format)
        for codec in codecs {
            let isPro = !isPremiumUnlocked && (codec == .proresProxy || codec == .dnxhrLB)
            let title = isPro ? "\(codec.displayName) (Pro)" : codec.displayName
            popup.addItem(withTitle: title)
            if isPro {
                popup.lastItem?.isEnabled = false
            }
        }
        // Restore saved codec for this format, or default to first
        let savedIndex = UserDefaults.standard.integer(forKey: "selectedCodecIndex_\(selectedFormat)")
        if savedIndex < codecs.count && (popup.item(at: savedIndex)?.isEnabled ?? false) {
            selectedCodecIndex = savedIndex
        } else {
            // Find first enabled item
            selectedCodecIndex = 0
            for i in 0..<codecs.count {
                if popup.item(at: i)?.isEnabled ?? false {
                    selectedCodecIndex = i
                    break
                }
            }
        }
        popup.selectItem(at: selectedCodecIndex)
    }

    private func applyPremiumRestrictions() {
        guard let formatPopup = formatPopup else { return }

        // Rebuild format popup
        let previousFormat = selectedFormat
        formatPopup.removeAllItems()
        formatPopup.addItems(withTitles: ["QuickTime", "MPEG-4", isPremiumUnlocked ? "MXF" : "MXF (Pro)"])
        if !isPremiumUnlocked {
            formatPopup.lastItem?.isEnabled = false
            if previousFormat == 2 {
                selectedFormat = 0
                UserDefaults.standard.set(selectedFormat, forKey: "selectedFormatSegment")
            }
        }
        if selectedFormat < formatPopup.numberOfItems && (formatPopup.item(at: selectedFormat)?.isEnabled ?? false) {
            formatPopup.selectItem(at: selectedFormat)
        } else {
            formatPopup.selectItem(at: 0)
        }

        // Refresh codec popup
        updateCodecPopup()

        // Watermark restrictions
        if isPremiumUnlocked {
            watermarkCheckbox?.isEnabled = true
            watermarkSetButton?.title = "Set…"
            updateWatermarkSetButtonState()
        } else {
            watermarkCheckbox?.state = .on
            watermarkCheckbox?.isEnabled = false
            watermarkSetButton?.title = "Pro"
            watermarkSetButton?.isEnabled = false
            UserDefaults.standard.set(true, forKey: "watermarkEnabled")
            UserDefaults.standard.set("library", forKey: "watermarkMode")
            UserDefaults.standard.set(bundledWatermarkName, forKey: "watermarkLibraryFile")
        }

        // Upgrade button visibility
        upgradeButton?.isHidden = isPremiumUnlocked

        // Update window title
        window?.title = isPremiumUnlocked ? "pxf Pro" : "pxf Free"
    }

    @objc func modePopupChanged(_ sender: NSPopUpButton) {
        selectedMode = sender.indexOfSelectedItem
        self.currentMode = selectedMode == 1 ? .night : (selectedMode == 2 ? .auto : .day)
        UserDefaults.standard.set(selectedMode, forKey: "selectedModeSegment")

        updateWindowColors()
        updateSettingsWindowColors()
        updateLUTManagementWindowColors()
        updateWatermarkManagementWindowColors()
    }

    @objc func watermarkCheckboxChanged(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        UserDefaults.standard.set(isEnabled, forKey: "watermarkEnabled")
        updateWatermarkSetButtonState()
    }

    private func setEncodingPath(_ prefix: String, url: URL) {
        encodingPathURL = url
        encodingPathPrefix = prefix
        guard let label = encodingPathLabel else { return }
        let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let linkColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let path = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: prefix + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]))
        result.append(NSAttributedString(string: path, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraphStyle
        ]))
        label.attributedStringValue = result
        label.useHandCursor = true
        label.window?.invalidateCursorRects(for: label)
    }

    private func clearEncodingPath() {
        encodingPathURL = nil
        encodingPathPrefix = nil
        guard let label = encodingPathLabel else { return }
        label.stringValue = ""
        label.useHandCursor = false
        label.window?.invalidateCursorRects(for: label)
    }

    @objc func encodingPathClicked(_ sender: NSClickGestureRecognizer) {
        guard let url = encodingPathURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func lutCheckboxChanged(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        UserDefaults.standard.set(isEnabled, forKey: "lutEnabled")

        // Enable/disable LUT popup based on checkbox
        lutPopup?.isEnabled = isEnabled

        // Update LUT label
        if isEnabled {
            if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath"),
               FileManager.default.fileExists(atPath: getLUTDirectoryURL().appendingPathComponent(savedLUT).path) {
                lutLabel?.stringValue = savedLUT
                let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
                lutLabel?.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
            }
        } else {
            lutLabel?.stringValue = ""
        }
    }

    @objc func lutPopupChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.titleOfSelectedItem else { return }
        if selectedTitle == "Add LUT..." {
            selectLUTFile()
            // Revert to previous selection while file picker is open
            if let savedLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
                selectLUTInPopup(savedLUT)
            } else {
                sender.selectItem(at: 0)
            }
        } else if selectedTitle != "No LUTs" {
            UserDefaults.standard.set(selectedTitle, forKey: "lutFilePath")
            UserDefaults.standard.set(true, forKey: "lutEnabled")
            lutCheckbox?.state = .on
            lutPopup?.isEnabled = true
            // Update LUT label
            lutLabel?.stringValue = selectedTitle
            let isDark = currentMode == .auto ? isSystemDarkAppearance() : (currentMode == .night)
            lutLabel?.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        }
    }

    private func populateLUTPopup() {
        guard let popup = lutPopup else { return }
        popup.removeAllItems()

        let lutDir = getLUTDirectoryURL()
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: lutDir, includingPropertiesForKeys: nil)
            let lutFiles = files.filter { $0.pathExtension.lowercased() == "cube" }
                                .map { $0.lastPathComponent }
                                .sorted()

            if lutFiles.isEmpty {
                popup.addItem(withTitle: "No LUTs")
            } else {
                popup.addItems(withTitles: lutFiles)
            }
        } catch {
            popup.addItem(withTitle: "No LUTs")
        }

        popup.menu?.addItem(NSMenuItem.separator())
        popup.addItem(withTitle: "Add LUT...")
    }

    private func selectLUTInPopup(_ lutName: String) {
        guard let popup = lutPopup else { return }
        if let index = popup.itemTitles.firstIndex(of: lutName) {
            popup.selectItem(at: index)
        }
    }

    @objc func selectLUTFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .data]
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
                self.lutPopup?.isEnabled = true

                // Refresh LUT popup and select the new LUT
                self.populateLUTPopup()
                self.selectLUTInPopup(url.lastPathComponent)

                // Update LUT label
                self.lutLabel?.stringValue = url.lastPathComponent
                let isDark = self.currentMode == .auto ? self.isSystemDarkAppearance() : (self.currentMode == .night)
                self.lutLabel?.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)

                // Refresh LUT management window if it's open
                if self.lutManagementWindow != nil {
                    self.closeLUTManagement()
                    self.selectLUT()
                }
            } catch {
                self.appendLog(logURL: URL(fileURLWithPath: "/tmp/pxf.log"), entry: "Failed to copy LUT: \(error)\n")
            }
        }
    }
    
    private func updateModePopup() {
        modePopup?.selectItem(at: selectedMode)
    }

    private func getLUTDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let lutDir = appSupport.appendingPathComponent("pxf").appendingPathComponent("LUTs")
        
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
        lutLabel?.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
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

    private let bundledWatermarkName = "pxf_watermark.png"
    private let bundledWatermarkBase64 = "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"

    private func getWatermarkDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let wmDir = appSupport.appendingPathComponent("pxf").appendingPathComponent("Watermarks")

        if !fileManager.fileExists(atPath: wmDir.path) {
            try? fileManager.createDirectory(at: wmDir, withIntermediateDirectories: true)
        }

        // Ensure bundled watermark is always present in the library
        let bundledDest = wmDir.appendingPathComponent(bundledWatermarkName)
        if !fileManager.fileExists(atPath: bundledDest.path) {
            if let data = Data(base64Encoded: bundledWatermarkBase64, options: .ignoreUnknownCharacters) {
                try? data.write(to: bundledDest)
            }
        }

        return wmDir
    }

    private func getAvailableWatermarks() -> [String] {
        let wmDir = getWatermarkDirectoryURL()
        let fileManager = FileManager.default
        let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp"]

        guard let files = try? fileManager.contentsOfDirectory(at: wmDir, includingPropertiesForKeys: nil) else {
            return [bundledWatermarkName]
        }

        let allFiles = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .sorted()

        // Pin bundled watermark at the top
        var result = allFiles.filter { $0 == bundledWatermarkName }
        result += allFiles.filter { $0 != bundledWatermarkName }
        return result
    }

    private func updateWatermarkSetButtonState() {
        let isEnabled = UserDefaults.standard.bool(forKey: "watermarkEnabled")
        watermarkSetButton?.isEnabled = isEnabled
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
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.backgroundColor = bgColor.cgColor
        contentView?.wantsLayer = true
        CATransaction.commit()

        // Update text color
        let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) // #AAAAAA : #333333
        formatLabel?.textColor = textColor
        destinationLabel?.textColor = textColor
        codecLabel?.textColor = textColor

        // Update queue count label color - orange in both modes
        let queueCountColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        queueCountLabel?.textColor = queueCountColor

        // Update button appearance
        let accentColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)

        // Update button text color

        // Update gear icon color to match text color
        if #available(macOS 10.14, *) {
            gearButton?.contentTintColor = textColor
        }

        // Update drop zone label color to match text, border stays accent color
        dropLabel?.textColor = textColor
        encodingLabel?.textColor = textColor
        if let url = encodingPathURL, let prefix = encodingPathPrefix {
            setEncodingPath(prefix, url: url)
        } else {
            encodingPathLabel?.textColor = textColor
        }
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

        // Update LUT label color - orange in dark mode, blue in light mode (when LUT is selected)
        if let label = lutLabel, !label.stringValue.isEmpty {
            label.textColor = isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        }

        // Update destination path label color
        updateDestinationPathLabelColor()

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
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0)
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
        updateModePopup()
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
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0)
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
        let bgColor = isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.layer?.backgroundColor = bgColor.cgColor
        CATransaction.commit()

        // Update all labels, buttons, and scroll view
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

    private func updateDropViewColor() {
        let color: NSColor
        let mode = currentMode

        // If auto mode, check system appearance
        if mode == .auto {
            let isDark = isSystemDarkAppearance()
            color = isDark ? NSColor.black : NSColor(red: 0.585, green: 0.585, blue: 0.585, alpha: 1.0)
        } else if mode == .night {
            color = NSColor.black
        } else {
            color = NSColor(red: 0.585, green: 0.585, blue: 0.585, alpha: 1.0)
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
        panel.prompt = "Create Proxies"
        
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

            var relativePaths: [URL: String] = [:]

            if isDir.boolValue {
                // It's a folder — create proxies subfolder inside it
                let folderName = url.lastPathComponent
                proxyFolderName = "\(folderName) proxies"
                proxyFolderURL = url.appendingPathComponent(proxyFolderName)

                // Recursively find all MXF/MOV files in folder and sub-folders
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        // Skip anything inside the proxy output folder to avoid re-encoding proxies
                        if fileURL.path.hasPrefix(proxyFolderURL.path + "/") {
                            enumerator.skipDescendants()
                            continue
                        }
                        let ext = fileURL.pathExtension.lowercased()
                        if acceptedFormats.contains(ext) {
                            mxfFiles.append(fileURL)
                            // Compute relative subdirectory path from source folder
                            let parentDir = fileURL.deletingLastPathComponent()
                            if parentDir.path != url.path {
                                let relativeSub = parentDir.path.replacingOccurrences(of: url.path + "/", with: "")
                                relativePaths[fileURL] = relativeSub
                            }
                        }
                    }
                }
                mxfFiles.sort { $0.path < $1.path }
            } else {
                // It's a file
                let parentURL = url.deletingLastPathComponent()
                proxyFolderName = "Proxies"
                proxyFolderURL = parentURL.appendingPathComponent(proxyFolderName)
                mxfFiles = [url]
                relativePaths = [:]
            }

            // Determine destination based on popup selection
            let finalMxfFiles = mxfFiles
            let finalRelativePaths = relativePaths

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.fileRelativePaths = finalRelativePaths

                var destinationURL = proxyFolderURL

                if let selectedDest = self.selectedDestinationURL {
                    // "Select" mode - use remembered destination with proxy subfolder
                    destinationURL = selectedDest.appendingPathComponent(proxyFolderName)
                }

                // Continue on background thread
                let finalDestinationURL = destinationURL
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try FileManager.default.createDirectory(at: finalDestinationURL, withIntermediateDirectories: true)
                    } catch {
                        print("Error: \(error)")
                        DispatchQueue.main.async { completion() }
                        return
                    }

                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.didAutoHalfSize = false
                        self.setEncodingPath("Encoding to", url: finalDestinationURL)
                        self.processNextFile(index: 0, mxfFiles: finalMxfFiles, proxyFolderURL: finalDestinationURL, outputFormat: outputFormat, completion: completion)
                    }
                }
            }
        }
    }

    private func processNextFile(index: Int, mxfFiles: [URL], proxyFolderURL: URL, outputFormat: OutputFormat, forceOverwrite: Bool = false, completion: @escaping @Sendable () -> Void) {
        guard index < mxfFiles.count else {
            print("Conversion complete: \(proxyFolderURL.path)")
            self.setEncodingPath("Encoded to", url: proxyFolderURL)
            if self.didAutoHalfSize {
                let alert = NSAlert()
                alert.messageText = "Half Resolution Applied"
                alert.informativeText = "One or more files exceeded 4096px and were encoded at half resolution. H.264/H.265 hardware encoding is limited to 4096px."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                }
            }
            completion()
            return
        }

        let mxfFile = mxfFiles[index]
        let outputFileName: String
        switch outputFormat {
        case .quickTime:
            outputFileName = mxfFile.deletingPathExtension().lastPathComponent + ".mov"
        case .mpeg4:
            outputFileName = mxfFile.deletingPathExtension().lastPathComponent + ".mp4"
        case .mxf:
            outputFileName = mxfFile.deletingPathExtension().lastPathComponent + ".mxf"
        }
        // Determine output directory, preserving sub-folder structure
        let relativeSub = fileRelativePaths[mxfFile] ?? ""
        let outputDir = relativeSub.isEmpty ? proxyFolderURL : proxyFolderURL.appendingPathComponent(relativeSub)
        if !relativeSub.isEmpty {
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        let outputFileURL = outputDir.appendingPathComponent(outputFileName)

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
                            // Wipe the proxy folder so no stale files remain, then restart from the beginning
                            try? FileManager.default.removeItem(at: proxyFolderURL)
                            try? FileManager.default.createDirectory(at: proxyFolderURL, withIntermediateDirectories: true)
                            self.processNextFile(index: 0, mxfFiles: mxfFiles, proxyFolderURL: proxyFolderURL, outputFormat: outputFormat, forceOverwrite: true, completion: completion)
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

        // Resolve watermark image path based on mode
        // In free mode, always use bundled watermark
        let watermarkEnabled: Bool
        let watermarkMode: String
        let customWatermarkText: String
        let libraryWatermarkFile: String
        if !isPremiumUnlocked {
            watermarkEnabled = true
            watermarkMode = "library"
            customWatermarkText = ""
            libraryWatermarkFile = bundledWatermarkName
        } else {
            watermarkEnabled = UserDefaults.standard.bool(forKey: "watermarkEnabled")
            watermarkMode = UserDefaults.standard.string(forKey: "watermarkMode") ?? "library"
            customWatermarkText = UserDefaults.standard.string(forKey: "watermarkCustomText") ?? ""
            libraryWatermarkFile = UserDefaults.standard.string(forKey: "watermarkLibraryFile") ?? ""
        }

        let watermarkURL: URL?
        if watermarkMode != "custom" && !libraryWatermarkFile.isEmpty {
            let libraryPath = getWatermarkDirectoryURL().appendingPathComponent(libraryWatermarkFile)
            watermarkURL = FileManager.default.fileExists(atPath: libraryPath.path) ? libraryPath : nil
        } else {
            watermarkURL = nil
        }

        let hasImageWatermark = watermarkEnabled && watermarkMode != "custom" && watermarkURL != nil
        let hasCustomTextWatermark = watermarkEnabled && watermarkMode == "custom" && !customWatermarkText.isEmpty
        let hasWatermark = hasImageWatermark || hasCustomTextWatermark

        // Debug log watermark settings
        appendLog(logURL: logURL, entry: "Watermark settings: enabled=\(watermarkEnabled), mode=\(watermarkMode), customText='\(customWatermarkText)', libraryFile='\(libraryWatermarkFile)', hasImage=\(hasImageWatermark), hasCustomText=\(hasCustomTextWatermark)\n")

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

        appendLog(logURL: logURL, entry: "Using in-process ffmpeg (static library)\n")

        // Get video dimensions and codec using ffmpeg probe (in-process)
        var videoWidth: Int = 0
        var videoHeight: Int = 0
        var darNum: Int = 0
        var darDen: Int = 0
        var sourceIsProRes = false
        var sourceHasAudio = false
        do {
            let probeArgs = ["ffmpeg", "-i", mxfFile.path, "-hide_banner"]
            ffmpegRunCapture(probeArgs)
            let output = String(cString: ffmpeg_get_captured_output())

            // Parse "1234x5678" from output
            let pattern = #"(\d{3,5})x(\d{3,5})"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let widthRange = Range(match.range(at: 1), in: output),
               let heightRange = Range(match.range(at: 2), in: output) {
                videoWidth = Int(output[widthRange]) ?? 0
                videoHeight = Int(output[heightRange]) ?? 0
            }
            // Detect if source is ProRes (needs AVFoundation for high bit-depth)
            if output.contains("Video: prores") {
                sourceIsProRes = true
            }
            // Detect if source has audio streams
            if output.contains("Audio:") {
                sourceHasAudio = true
            }
            // Parse DAR (e.g. "DAR 16:9")
            let darPattern = #"DAR (\d+):(\d+)"#
            if let darRegex = try? NSRegularExpression(pattern: darPattern),
               let darMatch = darRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let darNumRange = Range(darMatch.range(at: 1), in: output),
               let darDenRange = Range(darMatch.range(at: 2), in: output) {
                darNum = Int(output[darNumRange]) ?? 0
                darDen = Int(output[darDenRange]) ?? 0
            }
        }
        var isHalfSize = (self.sizePopup?.indexOfSelectedItem ?? 0) == 1

        // Auto-force half-size for H.264/H.265 when source exceeds VideoToolbox 4096px limit
        let selectedCodecForSizeCheck = currentVideoCodec()
        let needsVideoToolbox = selectedCodecForSizeCheck == .h264 || selectedCodecForSizeCheck == .h265
        if videoWidth > 4096 && !isHalfSize && needsVideoToolbox {
            isHalfSize = true
            didAutoHalfSize = true
            appendLog(logURL: logURL, entry: "Auto-enabling half-size: source width \(videoWidth)px exceeds VideoToolbox 4096px limit for \(selectedCodecForSizeCheck.displayName)\n")
        }
        let videoScaleExpr = isHalfSize ? "trunc(iw/4)*2:trunc(ih/4)*2" : "-1:-1"
        let scalePrefix = isHalfSize ? "scale=trunc(iw/4)*2:trunc(ih/4)*2:flags=bicubic:out_color_matrix=bt709," : ""
        let wmPadX = 30
        let wmPadY = 30
        let sizeDiv = isHalfSize ? 2 : 1
        let wmHeight = max(videoHeight * 15 / 100 / sizeDiv, 1)
        // Anamorphic correction: scale to target height preserving AR, then squeeze width
        var wmScaleFilter = "scale=-2:\(wmHeight)"
        if videoWidth > 0 && videoHeight > 0 && darNum > 0 && darDen > 0 {
            let rasterAR = Double(videoWidth) / Double(videoHeight)
            let dar = Double(darNum) / Double(darDen)
            let squeeze = rasterAR / dar
            if abs(squeeze - 1.0) > 0.01 {
                wmScaleFilter = "scale=-2:\(wmHeight),scale=trunc(iw*\(squeeze)/2)*2:ih"
            }
        }
        appendLog(logURL: logURL, entry: "Detected video width: \(videoWidth), height: \(videoHeight), DAR: \(darNum):\(darDen), wmScaleFilter: \(wmScaleFilter), wmHeight: \(wmHeight)\n")

        // Always use VideoToolbox hardware encoders (LGPL build has no libx264/libx265)
        let h264Codec = "h264_videotoolbox"
        let h264PixelFormat = "nv12"

        // Get selected codec
        let selectedCodec = currentVideoCodec()
        appendLog(logURL: logURL, entry: "Selected codec: \(selectedCodec.displayName)\n")

        // Generate codec args based on selection
        let videoCodecArgs: [String]
        switch selectedCodec {
        case .h265:
            videoCodecArgs = ["-c:v", "hevc_videotoolbox", "-pix_fmt", "p010le", "-b:v", "10M", "-tag:v", "hvc1"]
        case .h264:
            videoCodecArgs = ["-c:v", "h264_videotoolbox", "-pix_fmt", "nv12", "-b:v", "10M"]
        case .proresProxy:
            videoCodecArgs = ["-c:v", "prores_ks", "-profile:v", "0", "-pix_fmt", "yuv422p10le"]
        case .dnxhrLB:
            videoCodecArgs = ["-c:v", "dnxhd", "-profile:v", "dnxhr_lb", "-pix_fmt", "yuv422p"]
        case .mpeg2:
            videoCodecArgs = ["-c:v", "mpeg2video", "-b:v", "45M", "-maxrate", "45M", "-bufsize", "90M"]
        }

        // Pixel format compatible with the selected encoder
        // VideoToolbox requires semi-planar formats (p010le for HEVC, nv12 for H.264)
        let videoPixelFormat: String
        switch selectedCodec {
        case .h265:
            videoPixelFormat = "p010le"
        case .h264:
            videoPixelFormat = "nv12"
        case .proresProxy, .dnxhrLB, .mpeg2:
            videoPixelFormat = "yuv420p"
        }

        // Legacy aliases for compatibility
        let quickTimeCodecArgs = videoCodecArgs
        let mxfCodecArgs = videoCodecArgs

        switch outputFormat {
        case .quickTime:
            // Only ProRes MOV files need AVFoundation intermediate (handles high bit-depth)
            // Other MOV codecs (DNxHR, H.264, etc.) go direct through FFmpeg
            let needsIntermediateConversion = mxfFile.pathExtension.lowercased() == "mov" && sourceIsProRes
            
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
                        if lutEnabled && !hasLUT {
                            self.appendLog(logURL: logURL, entry: "WARNING: LUT enabled but file not found: \(lutPath ?? "nil")\n")
                        }
                        self.appendLog(logURL: logURL, entry: "LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")
                        
                        // Step 2: Apply LUT and/or watermark to AVFoundation intermediate
                        var args: [String]
                        if hasImageWatermark {
                            // Build filter chain with optional LUT and image watermark
                            var filterChain = "[0:v]"
                            if hasLUT {
                                filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                            }
                            filterChain += "scale=\(videoScaleExpr):flags=bicubic:out_color_matrix=bt709,format=\(h264PixelFormat)[v0];[1:v]\(wmScaleFilter),format=rgba,colorchannelmixer=aa=0.50[wm];[v0][wm]overlay=W-w-\(wmPadX):H-h-\(wmPadY)[v]"

                            args = [
                                "-i", intermediateURL.path,
                                "-i", watermarkURL!.path,
                                "-i", mxfFile.path,
                                "-filter_complex", filterChain,
                                "-map", "2:d?",
                                "-c:d", "copy",
                                "-map", "[v]",
                            ] + (sourceHasAudio ? ["-map", "2:a?", "-c:a", "copy", "-map_metadata:s:a", "2:s:a"] : []) + [
                                "-c:v", h264Codec,
                                "-b:v", "10M",
                                "-sn",
                                outputFileURL.path
                            ]
                        } else if hasCustomTextWatermark {
                            // Build filter chain with optional scale, LUT and custom text watermark
                            var filterChain = scalePrefix
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
                            ] + (sourceHasAudio ? ["-map", "1:a?", "-c:a", "copy", "-map_metadata:s:a", "1:s:a"] : []) + [
                                "-c:v", h264Codec,
                                "-b:v", "10M",
                                "-sn",
                                outputFileURL.path
                            ]
                        } else {
                            // No watermark, but may have LUT
                            if hasLUT {
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                    "-vf", "\(scalePrefix)lut3d=file=\(escapePathForFFmpegFilter(lutPath!))",
                                    "-map", "1:d?",
                                    "-c:d", "copy",
                                    "-map", "0:v",
                                ] + (sourceHasAudio ? ["-map", "1:a?", "-c:a", "copy", "-map_metadata:s:a", "1:s:a"] : []) + [
                                    "-c:v", h264Codec,
                                    "-b:v", "10M",
                                    "-sn",
                                    outputFileURL.path
                                ]
                            } else {
                                let vfArgs: [String] = isHalfSize ? ["-vf", "scale=trunc(iw/4)*2:trunc(ih/4)*2:flags=bicubic:out_color_matrix=bt709"] : []
                                args = [
                                    "-i", intermediateURL.path,
                                    "-i", mxfFile.path,
                                ] + vfArgs + [
                                    "-map", "1:d?",
                                    "-c:d", "copy",
                                    "-map", "0:v",
                                ] + (sourceHasAudio ? ["-map", "1:a?", "-c:a", "copy", "-map_metadata:s:a", "1:s:a"] : []) + [
                                    "-c:v", h264Codec,
                                    "-b:v", "10M",
                                    "-sn",
                                    outputFileURL.path
                                ]
                            }
                        }
                        
                        self.runProcessDetached(arguments: args, logURL: logURL) { [weak self] status2 in
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
                if lutEnabled && !hasLUT {
                    self.appendLog(logURL: logURL, entry: "WARNING: LUT enabled but file not found: \(lutPath ?? "nil")\n")
                }
                self.appendLog(logURL: logURL, entry: "MXF->QT: LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")

                var args = (forceOverwrite || self.overwriteAllFiles) ? ["-y", "-i", mxfFile.path] : ["-i", mxfFile.path]
                var videoFilterArgs: [String]
                var videoMapArgs: [String]

                self.appendLog(logURL: logURL, entry: "MXF->QT: Watermark check: hasImageWatermark=\(hasImageWatermark), hasCustomTextWatermark=\(hasCustomTextWatermark), escapedCustomText='\(escapedCustomText)'\n")

                if hasImageWatermark {
                    // Add watermark input
                    args += ["-i", watermarkURL!.path]

                    // Build filter chain with optional LUT and image watermark
                    var filterChain = "[0:v]"
                    if hasLUT {
                        filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                    }
                    filterChain += "scale=\(videoScaleExpr):flags=bicubic:out_color_matrix=bt709,format=\(videoPixelFormat)[v0];[1:v]\(wmScaleFilter),format=rgba,colorchannelmixer=aa=0.50[wm];[v0][wm]overlay=W-w-\(wmPadX):H-h-\(wmPadY)[v]"

                    videoFilterArgs = ["-filter_complex", filterChain]
                    videoMapArgs = ["-map", "[v]"]
                } else if hasCustomTextWatermark {
                    // Build filter chain with optional scale, LUT and custom text watermark
                    var filterChain = scalePrefix
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
                    videoFilterArgs = ["-vf", "\(scalePrefix)lut3d=file=\(escapePathForFFmpegFilter(lutPath!))"]
                    videoMapArgs = ["-map", "0:v"]
                } else {
                    // No watermark, no LUT
                    if isHalfSize {
                        videoFilterArgs = ["-vf", "scale=trunc(iw/4)*2:trunc(ih/4)*2:flags=bicubic:out_color_matrix=bt709"]
                    } else {
                        videoFilterArgs = []
                    }
                    videoMapArgs = ["-map", "0:v"]
                }

                args += videoFilterArgs
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

                runProcessDetached(arguments: args, logURL: logURL) { [weak self] status in
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
        case .mpeg4:
            // MPEG-4 output - similar to QuickTime but without data tracks (not supported in MP4)
            // Check for LUT
            let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
            let lutFilename = UserDefaults.standard.string(forKey: "lutFilePath")
            let lutPath = lutFilename != nil ? self.getLUTDirectoryURL().appendingPathComponent(lutFilename!).path : nil
            let hasLUT = lutEnabled && lutPath != nil && FileManager.default.fileExists(atPath: lutPath!)
            if lutEnabled && !hasLUT {
                self.appendLog(logURL: logURL, entry: "WARNING: LUT enabled but file not found: \(lutPath ?? "nil")\n")
            }
            self.appendLog(logURL: logURL, entry: "MPEG-4: LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")

            var args = (forceOverwrite || self.overwriteAllFiles) ? ["-y", "-i", mxfFile.path] : ["-i", mxfFile.path]
            var videoFilterArgs: [String]
            var videoMapArgs: [String]

            if hasImageWatermark {
                args += ["-i", watermarkURL!.path]
                var filterChain = "[0:v]"
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                filterChain += "scale=\(videoScaleExpr):flags=bicubic:out_color_matrix=bt709,format=\(videoPixelFormat)[v0];[1:v]\(wmScaleFilter),format=rgba,colorchannelmixer=aa=0.50[wm];[v0][wm]overlay=W-w-\(wmPadX):H-h-\(wmPadY)[v]"
                videoFilterArgs = ["-filter_complex", filterChain]
                videoMapArgs = ["-map", "[v]"]
            } else if hasCustomTextWatermark {
                var filterChain = scalePrefix
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                filterChain += "format=\(videoPixelFormat),drawtext=fontfile=\(fontFile):text=\(escapedCustomText):fontsize=if(gt(h\\,1800)\\,144\\,72):fontcolor=white@0.5:x=(w-text_w)/2:y=h*9/10-text_h"
                videoFilterArgs = ["-vf", filterChain]
                videoMapArgs = ["-map", "0:v"]
            } else if hasLUT {
                videoFilterArgs = ["-vf", "\(scalePrefix)lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),format=\(videoPixelFormat)"]
                videoMapArgs = ["-map", "0:v"]
            } else {
                videoFilterArgs = ["-vf", "\(scalePrefix)format=\(videoPixelFormat)"]
                videoMapArgs = ["-map", "0:v"]
            }

            args += videoFilterArgs
            args += videoMapArgs
            args += videoCodecArgs
            args += [
                "-map", "0:a?",
                "-c:a", "aac",
                "-b:a", "192k",
                "-map_metadata", "0",
                "-sn",
                "-f", "mp4",
                outputFileURL.path
            ]

            self.appendLog(logURL: logURL, entry: "MPEG-4 FULL ARGS: \(args.joined(separator: " "))\n")

            runProcessDetached(arguments: args, logURL: logURL) { [weak self] status in
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
        case .mxf:
            // Two-step process for MXF output
            // Check for LUT
            let lutEnabled = UserDefaults.standard.bool(forKey: "lutEnabled")
            let lutFilename = UserDefaults.standard.string(forKey: "lutFilePath")
            let lutPath = lutFilename != nil ? self.getLUTDirectoryURL().appendingPathComponent(lutFilename!).path : nil
            let hasLUT = lutEnabled && lutPath != nil && FileManager.default.fileExists(atPath: lutPath!)
            if lutEnabled && !hasLUT {
                self.appendLog(logURL: logURL, entry: "WARNING: LUT enabled but file not found: \(lutPath ?? "nil")\n")
            }
            self.appendLog(logURL: logURL, entry: "MXF output: LUT check: lutEnabled=\(lutEnabled), lutFilename=\(lutFilename ?? "nil"), hasLUT=\(hasLUT)\n")

            // Step 1: Create intermediate video with LUT and/or watermark
            let tempVideoURL = proxyFolderURL.appendingPathComponent(".\(mxfFile.deletingPathExtension().lastPathComponent)_temp.mov")
            var args1 = (forceOverwrite || self.overwriteAllFiles) ? ["-y", "-i", mxfFile.path] : ["-i", mxfFile.path]
            var videoFilterArgs: [String]
            var videoMapArgs: [String]

            if hasImageWatermark {
                // Add watermark input
                args1 += ["-i", watermarkURL!.path]

                // Build filter chain with optional LUT and image watermark
                var filterChain = "[0:v]"
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                filterChain += "scale=\(videoScaleExpr):flags=bicubic:out_color_matrix=bt709,format=\(videoPixelFormat)[v0];[1:v]\(wmScaleFilter),format=rgba,colorchannelmixer=aa=0.50[wm];[v0][wm]overlay=W-w-\(wmPadX):H-h-\(wmPadY)[v]"

                videoFilterArgs = ["-filter_complex", filterChain]
                videoMapArgs = ["-map", "[v]"]
            } else if hasCustomTextWatermark {
                // Build filter chain with optional scale, LUT and custom text watermark
                var filterChain = scalePrefix
                if hasLUT {
                    filterChain += "lut3d=file=\(escapePathForFFmpegFilter(lutPath!)),"
                }
                // Custom text: centered horizontally, 10% up from bottom, white at 50% opacity
                filterChain += "drawtext=fontfile=\(fontFile):text=\(escapedCustomText):fontsize=if(gt(h\\,1800)\\,144\\,72):fontcolor=white@0.5:x=(w-text_w)/2:y=h*9/10-text_h"

                videoFilterArgs = ["-vf", filterChain]
                videoMapArgs = ["-map", "0:v"]
            } else if hasLUT {
                // LUT only, no watermark
                videoFilterArgs = ["-vf", "\(scalePrefix)lut3d=file=\(escapePathForFFmpegFilter(lutPath!))"]
                videoMapArgs = ["-map", "0:v"]
            } else {
                // No watermark, no LUT
                if isHalfSize {
                    videoFilterArgs = ["-vf", "scale=trunc(iw/4)*2:trunc(ih/4)*2:flags=bicubic:out_color_matrix=bt709"]
                } else {
                    videoFilterArgs = []
                }
                videoMapArgs = ["-map", "0:v"]
            }

            args1 += videoFilterArgs
            args1 += videoMapArgs
            args1 += mxfCodecArgs
            args1 += [
                "-an",
                tempVideoURL.path
            ]

            runProcessDetached(arguments: args1, logURL: logURL) { [weak self] status1 in
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
                    self.runProcessDetached(arguments: args2, logURL: logURL) { [weak self] status2 in
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

    private func runProcessDetached(arguments: [String], logURL: URL, completion: @escaping @Sendable (Int32) -> Void) {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let logHandle = FileHandle(forWritingAtPath: logURL.path)
        logHandle?.seekToEndOfFile()
        let logFD = logHandle?.fileDescriptor ?? -1

        let fullArgs = ["ffmpeg"] + arguments
        let args = fullArgs
        let fd = logFD
        let handle = logHandle
        let done = completion

        DispatchQueue.global(qos: .userInitiated).async {
            var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
            defer { cArgs.forEach { free($0) } }
            let ret = ffmpeg_run(Int32(args.count), &cArgs, Int32(fd))
            handle?.closeFile()

            DispatchQueue.main.async {
                done(ret)
            }
        }
    }

    @discardableResult
    private func ffmpegRunCapture(_ args: [String]) -> Int32 {
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        return ffmpeg_run(Int32(args.count), &cArgs, -1)
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
        let destMode = UserDefaults.standard.integer(forKey: "destinationMode")
        if destMode == 0 {
            let alert = NSAlert()
            alert.messageText = "No Destination Selected"
            alert.informativeText = "Please choose a destination folder or leave as default to save inside the source folder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = self.window {
                alert.beginSheetModal(for: window)
            }
            jobQueue.removeAll()
            totalClipsQueued = 0
            updateDropZoneAvailability()
            return
        }
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
                contentView.layer?.backgroundColor = NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0).cgColor
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
            openFolderButton.title = "Show in Finder"
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

                    // Refresh the main LUT popup and re-select
                    self.populateLUTPopup()
                    if let currentLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
                        self.selectLUTInPopup(currentLUT)
                    }

                    // Refresh the management window
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

                    // Refresh the main LUT popup and re-select
                    self.populateLUTPopup()
                    if let currentLUT = UserDefaults.standard.string(forKey: "lutFilePath") {
                        self.selectLUTInPopup(currentLUT)
                    }

                    // Refresh the management window
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
            let windowSize = NSSize(width: 500, height: 480)
            let mainOrigin = mainWindow.frame.origin
            let windowOrigin = NSPoint(x: mainOrigin.x + 100, y: mainOrigin.y + 50)

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
            contentView.layer?.backgroundColor = (isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0)).cgColor

            let textColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            let buttonTextColor = isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(white: 0.2, alpha: 1.0)

            // Title label
            let titleLabel = NSTextField(labelWithString: "Watermark Settings")
            titleLabel.frame = NSRect(x: 20, y: 440, width: 300, height: 24)
            titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
            titleLabel.textColor = textColor
            contentView.addSubview(titleLabel)

            // Load current mode from UserDefaults
            let currentWatermarkMode = UserDefaults.standard.string(forKey: "watermarkMode") ?? "library"
            let currentCustomText = UserDefaults.standard.string(forKey: "watermarkCustomText") ?? ""
            let currentLibraryFile = UserDefaults.standard.string(forKey: "watermarkLibraryFile") ?? ""

            // Radio button: Custom text
            let customRadio = NSButton(radioButtonWithTitle: "Custom text", target: self, action: #selector(watermarkRadioClicked(_:)))
            customRadio.frame = NSRect(x: 20, y: 410, width: 150, height: 20)
            customRadio.tag = 1
            customRadio.identifier = NSUserInterfaceItemIdentifier("customRadio")
            customRadio.state = (currentWatermarkMode == "custom") ? .on : .off
            let customAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            customRadio.attributedTitle = NSAttributedString(string: customRadio.title, attributes: customAttrs)
            contentView.addSubview(customRadio)

            // Text field for custom text
            let textField = NSTextField(frame: NSRect(x: 40, y: 380, width: 340, height: 24))
            textField.stringValue = currentCustomText
            textField.placeholderString = "Enter custom watermark text (max 48 characters)"
            textField.isEnabled = (currentWatermarkMode == "custom")
            textField.identifier = NSUserInterfaceItemIdentifier("watermarkTextField")
            textField.target = self
            textField.action = #selector(watermarkTextFieldChanged(_:))
            contentView.addSubview(textField)

            // Max length hint
            let maxLenLabel = NSTextField(labelWithString: "(48 characters max.)")
            maxLenLabel.frame = NSRect(x: 240, y: 358, width: 140, height: 16)
            maxLenLabel.font = NSFont.systemFont(ofSize: 11)
            maxLenLabel.textColor = NSColor.secondaryLabelColor
            maxLenLabel.alignment = .right
            contentView.addSubview(maxLenLabel)

            // Radio button: Library image
            let libraryRadio = NSButton(radioButtonWithTitle: "Library image", target: self, action: #selector(watermarkRadioClicked(_:)))
            libraryRadio.frame = NSRect(x: 20, y: 328, width: 150, height: 20)
            libraryRadio.tag = 2
            libraryRadio.identifier = NSUserInterfaceItemIdentifier("libraryRadio")
            libraryRadio.state = (currentWatermarkMode == "custom") ? .off : .on
            let libraryAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]
            libraryRadio.attributedTitle = NSAttributedString(string: libraryRadio.title, attributes: libraryAttrs)
            contentView.addSubview(libraryRadio)

            // Scroll view for watermark library list
            let scrollView = NSScrollView(frame: NSRect(x: 20, y: 90, width: 460, height: 200))
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.borderType = .lineBorder
            scrollView.identifier = NSUserInterfaceItemIdentifier("watermarkScrollView")

            let listBgColor = isDark ? NSColor.black : NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
            scrollView.backgroundColor = listBgColor

            let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: 200))
            listView.wantsLayer = true
            listView.layer?.backgroundColor = listBgColor.cgColor

            let watermarks = getAvailableWatermarks()
            var yPos: CGFloat = 0

            for (index, wmName) in watermarks.enumerated() {
                let rowView = NSView(frame: NSRect(x: 0, y: yPos, width: 440, height: 30))

                // Clickable name label — clicking selects the watermark
                let nameButton = NSButton(frame: NSRect(x: 10, y: 2, width: 340, height: 24))
                nameButton.title = wmName
                nameButton.alignment = .left
                nameButton.bezelStyle = .inline
                nameButton.isBordered = false
                let isSelected = wmName == currentLibraryFile
                let nameColor: NSColor = isSelected
                    ? (isDark ? NSColor(red: 0.898, green: 0.361, blue: 0.090, alpha: 1.0) : NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0))
                    : (isDark ? NSColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))
                nameButton.font = NSFont.systemFont(ofSize: 12)
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: nameColor,
                    .font: NSFont.systemFont(ofSize: 12)
                ]
                nameButton.attributedTitle = NSAttributedString(string: wmName, attributes: nameAttrs)
                nameButton.target = self
                nameButton.action = #selector(selectWatermarkFromList(_:))
                nameButton.identifier = NSUserInterfaceItemIdentifier(wmName)
                nameButton.tag = index
                rowView.addSubview(nameButton)

                // Only show rename/delete for user-added watermarks (not the bundled one)
                if wmName != bundledWatermarkName {
                    // Rename button (pencil icon)
                    let renameButton = NSButton(frame: NSRect(x: 360, y: 2, width: 30, height: 24))
                    if #available(macOS 11.0, *) {
                        if let pencilImage = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename") {
                            renameButton.image = pencilImage
                            renameButton.imageScaling = .scaleProportionallyDown
                        } else {
                            renameButton.title = "Rn"
                        }
                    } else {
                        renameButton.title = "Rn"
                    }
                    renameButton.bezelStyle = .regularSquare
                    renameButton.isBordered = true
                    renameButton.tag = index
                    renameButton.target = self
                    renameButton.action = #selector(renameWatermark(_:))
                    renameButton.identifier = NSUserInterfaceItemIdentifier(wmName)
                    renameButton.toolTip = "Rename watermark"
                    rowView.addSubview(renameButton)

                    // Delete button (trash icon)
                    let deleteButton = NSButton(frame: NSRect(x: 395, y: 2, width: 30, height: 24))
                    if #available(macOS 11.0, *) {
                        if let trashImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
                            deleteButton.image = trashImage
                            deleteButton.imageScaling = .scaleProportionallyDown
                        } else {
                            deleteButton.title = "Del"
                        }
                    } else {
                        deleteButton.title = "Del"
                    }
                    deleteButton.bezelStyle = .regularSquare
                    deleteButton.isBordered = true
                    deleteButton.tag = index
                    deleteButton.target = self
                    deleteButton.action = #selector(deleteWatermark(_:))
                    deleteButton.identifier = NSUserInterfaceItemIdentifier(wmName)
                    deleteButton.toolTip = "Delete watermark"
                    rowView.addSubview(deleteButton)
                }

                listView.addSubview(rowView)
                yPos += 30
            }

            if watermarks.count * 30 > 200 {
                listView.frame = NSRect(x: 0, y: 0, width: 440, height: CGFloat(watermarks.count * 30))
            }

            scrollView.documentView = listView
            contentView.addSubview(scrollView)

            // Add Watermark button
            let addButton = NSButton(frame: NSRect(x: 20, y: 52, width: 150, height: 28))
            addButton.title = "Add Watermark..."
            addButton.bezelStyle = .rounded
            addButton.target = self
            addButton.action = #selector(selectWatermarkFile)
            if #available(macOS 10.14, *) {
                addButton.contentTintColor = buttonTextColor
            }
            let addAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            addButton.attributedTitle = NSAttributedString(string: addButton.title, attributes: addAttrs)
            contentView.addSubview(addButton)

            // Show in Finder button
            let openFolderButton = NSButton(frame: NSRect(x: 180, y: 52, width: 140, height: 28))
            openFolderButton.title = "Show in Finder"
            openFolderButton.bezelStyle = .rounded
            openFolderButton.target = self
            openFolderButton.action = #selector(openWatermarkFolder)
            if #available(macOS 10.14, *) {
                openFolderButton.contentTintColor = buttonTextColor
            }
            let openAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            openFolderButton.attributedTitle = NSAttributedString(string: openFolderButton.title, attributes: openAttrs)
            contentView.addSubview(openFolderButton)

            // Close button
            let closeButton = NSButton(frame: NSRect(x: 370, y: 15, width: 90, height: 28))
            closeButton.title = "Set"
            closeButton.bezelStyle = .rounded
            closeButton.target = self
            closeButton.action = #selector(closeWatermarkManagement)
            let closeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: buttonTextColor]
            closeButton.attributedTitle = NSAttributedString(string: closeButton.title, attributes: closeAttrs)
            contentView.addSubview(closeButton)

            wmWin.contentView = contentView
            wmWin.delegate = self
            self.watermarkManagementWindow = wmWin
        }

        watermarkManagementWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshWatermarkManagementWindow() {
        guard let wmWin = watermarkManagementWindow else { return }
        let savedFrame = wmWin.frame
        // Close existing window and rebuild
        wmWin.orderOut(nil)
        watermarkManagementWindow = nil
        showWatermarkManagement()
        watermarkManagementWindow?.setFrame(savedFrame, display: true)
    }

    @objc private func selectWatermarkFromList(_ sender: NSButton) {
        guard let wmName = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(wmName, forKey: "watermarkLibraryFile")
        UserDefaults.standard.set("library", forKey: "watermarkMode")
        updateWatermarkSetButtonState()
        refreshWatermarkManagementWindow()
    }

    @objc private func watermarkRadioClicked(_ sender: NSButton) {
        let isCustom = sender.tag == 1
        UserDefaults.standard.set(isCustom ? "custom" : "library", forKey: "watermarkMode")
        updateWatermarkSetButtonState()
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
        if sender.stringValue.count > 48 {
            sender.stringValue = String(sender.stringValue.prefix(48))
        }
        UserDefaults.standard.set(sender.stringValue, forKey: "watermarkCustomText")
    }

    @objc private func closeWatermarkManagement() {
        // Save custom text field before closing
        if let contentView = watermarkManagementWindow?.contentView {
            for subview in contentView.subviews {
                if let textField = subview as? NSTextField,
                   textField.identifier?.rawValue == "watermarkTextField",
                   textField.isEnabled {
                    watermarkTextFieldChanged(textField)
                }
            }
        }
        watermarkManagementWindow?.orderOut(nil)
        watermarkManagementWindow = nil
    }

    @objc func selectWatermarkFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.message = "Select a watermark image file"

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }

            let wmDir = self.getWatermarkDirectoryURL()
            let destURL = wmDir.appendingPathComponent(url.lastPathComponent)
            let fileManager = FileManager.default

            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
                UserDefaults.standard.set(url.lastPathComponent, forKey: "watermarkLibraryFile")
                UserDefaults.standard.set("library", forKey: "watermarkMode")
                UserDefaults.standard.set(true, forKey: "watermarkEnabled")
                self.watermarkCheckbox?.state = .on

                self.updateWatermarkSetButtonState()

                // Refresh watermark management window if it's open
                if self.watermarkManagementWindow != nil {
                    self.refreshWatermarkManagementWindow()
                }
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Error"
                errorAlert.informativeText = "Failed to import watermark: \(error.localizedDescription)"
                errorAlert.alertStyle = .critical
                errorAlert.runModal()
            }
        }
    }

    @objc private func deleteWatermark(_ sender: NSButton) {
        guard let wmName = sender.identifier?.rawValue else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Watermark"
        alert.informativeText = "Are you sure you want to delete '\(wmName)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: watermarkManagementWindow!) { response in
            if response == .alertFirstButtonReturn {
                let wmDir = self.getWatermarkDirectoryURL()
                let wmURL = wmDir.appendingPathComponent(wmName)

                do {
                    try FileManager.default.removeItem(at: wmURL)

                    if UserDefaults.standard.string(forKey: "watermarkLibraryFile") == wmName {
                        UserDefaults.standard.removeObject(forKey: "watermarkLibraryFile")
                        UserDefaults.standard.set("library", forKey: "watermarkMode")
                    }

                    self.updateWatermarkSetButtonState()
                    self.refreshWatermarkManagementWindow()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "Failed to delete watermark: \(error.localizedDescription)"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
    }

    @objc private func renameWatermark(_ sender: NSButton) {
        guard let oldName = sender.identifier?.rawValue else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Watermark"
        alert.informativeText = "Enter a new name for '\(oldName)':"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let ext = (oldName as NSString).pathExtension
        let nameWithoutExt = (oldName as NSString).deletingPathExtension

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = nameWithoutExt
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: watermarkManagementWindow!) { response in
            if response == .alertFirstButtonReturn {
                var newName = textField.stringValue.trimmingCharacters(in: .whitespaces)

                if !newName.hasSuffix(".\(ext)") {
                    newName += ".\(ext)"
                }

                guard !newName.isEmpty && newName != oldName else { return }

                let wmDir = self.getWatermarkDirectoryURL()
                let oldURL = wmDir.appendingPathComponent(oldName)
                let newURL = wmDir.appendingPathComponent(newName)

                if FileManager.default.fileExists(atPath: newURL.path) {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "A watermark with the name '\(newName)' already exists."
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                    return
                }

                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)

                    if UserDefaults.standard.string(forKey: "watermarkLibraryFile") == oldName {
                        UserDefaults.standard.set(newName, forKey: "watermarkLibraryFile")
                    }

                    self.updateWatermarkSetButtonState()
                    self.refreshWatermarkManagementWindow()
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Error"
                    errorAlert.informativeText = "Failed to rename watermark: \(error.localizedDescription)"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
    }

    @objc private func openWatermarkFolder() {
        let wmDir = getWatermarkDirectoryURL()
        NSWorkspace.shared.activateFileViewerSelecting([wmDir])
    }

    func setupMenuBar() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: "About pxf", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide pxf", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit pxf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

        let helpMenu = NSMenu(title: "Help")
        let supportItem = NSMenuItem(title: "pxf Support", action: #selector(openSupport), keyEquivalent: "")
        helpMenu.addItem(supportItem)
        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func openSupport() {
        NSWorkspace.shared.open(URL(string: "https://frankcapria.com/support/")!)
    }
    
    @objc func showAbout() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let aboutWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        aboutWin.title = "About pxf"
        aboutWin.center()
        aboutWin.delegate = self
        aboutWin.minSize = NSSize(width: 400, height: 300)

        let scrollView = NSScrollView(frame: aboutWin.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = NSFont.systemFont(ofSize: 12)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        let aboutText = """
        pxf  v\(version) (\(build))
        MXF/MOV to proxy converter
        Privacy Policy: https://frankcapria.com/privacy-policy/

        This application uses the following open-source libraries. \
        The FFmpeg libraries are dynamically linked under the terms of the \
        GNU Lesser General Public License v2.1 (LGPL). You may replace the \
        bundled .dylib files in Contents/Frameworks/ with modified versions; \
        see the LGPL notice below for details.

        ─────────────────────────────────────────
        FFmpeg  (libavcodec, libavformat, libavfilter, libswscale, libswresample, libavutil)
        Copyright (c) 2000-2024 the FFmpeg developers
        Licensed under the GNU Lesser General Public License v2.1 or later.
        Source: https://ffmpeg.org  ·  Build script: build_ffmpeg_dylib.sh

        LGPL v2.1 — Your Rights
        This application uses FFmpeg, LAME, fribidi, GLib, libintl, and Graphite2 \
        under the GNU Lesser General Public License. In accordance with LGPL v2.1 \
        Section 6, you may replace the shared libraries (.dylib files) bundled in \
        pxf.app/Contents/Frameworks/ with your own modified versions.

        After replacing a library, re-sign the app:
            codesign --force --deep --sign - pxf.app

        Source Code Offer
        The complete source code for all LGPL-licensed libraries, along with the \
        build scripts and patches needed to reproduce the bundled binaries:
          - FFmpeg 7.1.1: https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz
          - LAME: https://lame.sourceforge.io
          - fribidi: https://github.com/fribidi/fribidi
          - GLib: https://gitlab.gnome.org/GNOME/glib
          - gettext: https://www.gnu.org/software/gettext/
          - Graphite2: https://github.com/nickshanks/graphite
          - Build script & patches: included in this app bundle at
            pxf.app/Contents/Resources/LGPL-Sources/
        This offer is valid for three years from the date of distribution.

        ─────────────────────────────────────────
        Replacing LGPL Libraries
        You have the right to replace any LGPL-licensed .dylib in this app bundle \
        with your own modified version. For step-by-step instructions, see:
          pxf.app/Contents/Resources/LGPL-Sources/RELINKING.txt

        ─────────────────────────────────────────
        LAME (libmp3lame)
        Copyright (C) 1999-2011 The LAME Project, et al.
        Licensed under the GNU Library General Public License v2 or later.

        fribidi
        Copyright (C) 2004-2024 Dov Grobgeld, Behdad Esfahbod, et al.
        Licensed under the GNU Lesser General Public License v2.1 or later.

        ─────────────────────────────────────────
        libaom  —  Copyright (c) 2016, Alliance for Open Media. BSD 2-Clause License.
        libvpx  —  Copyright (c) 2010, The WebM Project authors. BSD 3-Clause License.
        opus  —  Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell, Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon. BSD 3-Clause License.
        libvorbis  —  Copyright (c) 2002-2020 Xiph.org Foundation. BSD 3-Clause License.
        libogg  —  Copyright (c) 2002, Xiph.org Foundation. BSD 3-Clause License.
        libtheora  —  Copyright (C) 2002-2009 Xiph.org Foundation. BSD 3-Clause License.
        snappy  —  Copyright 2011, Google Inc. BSD 3-Clause License.
        libass  —  Copyright (C) 2006-2016 libass contributors. ISC License.
        HarfBuzz  —  Copyright (c) 2010-2022 Google, Inc. et al. MIT License.
        FreeType  —  Copyright (c) 1996-2024, David Turner, Robert Wilhelm, Werner Lemberg. FreeType License (FTL).
        Fontconfig  —  Copyright (c) 2000-2020 Keith Packard, Red Hat Inc., et al. MIT License.
        libpng  —  Copyright (c) 1995-2026 The PNG Reference Library Authors. libpng License.
        Brotli  —  Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors. MIT License.
        GLib  —  Copyright (C) 1995-2024, The GLib Team. LGPL v2.1.
        Graphite2  —  Copyright 2010, SIL International. LGPL v2.1 / MPL / GPL v2.
        PCRE2  —  Copyright (c) 1997-2024 Philip Hazel, University of Cambridge. BSD 3-Clause License.
        libvmaf  —  Copyright (c) 2020 Netflix, Inc. BSD 2-Clause-Patent License.
        zlib  —  Copyright (C) 1995-2024 Jean-loup Gailly and Mark Adler. zlib License.
        XZ Utils (liblzma)  —  Copyright (C) The XZ Utils authors and contributors. BSD Zero Clause License.
        bzip2  —  Copyright (c) 1996-2019, Julian Seward. bzip2 License.
        libunibreak  —  Copyright (C) Wu Yongwei, Tom Hacohen, et al. zlib License.
        libintl (gettext)  —  Copyright (C) 1995-2024, Free Software Foundation. LGPL v2.1.
        """

        textView.string = aboutText
        scrollView.documentView = textView
        aboutWin.contentView = scrollView
        aboutWin.makeKeyAndOrderFront(nil)
        self.aboutWindow = aboutWin
    }

    @objc func showUpgradePrompt() {
        let price = storeManager?.displayPrice ?? "$9.99"
        let alert = NSAlert()
        alert.messageText = "Upgrade to pxf Pro"
        alert.informativeText = "Unlock MXF output, ProRes Proxy and DNxHR LB codecs, and watermark customization for \(price)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Buy for \(price)")
        alert.addButton(withTitle: "Restore Purchase")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            if response == .alertFirstButtonReturn {
                // Buy
                Task { @MainActor in

                    let success = await self.storeManager?.purchase() ?? false

                    if success {
                        self.isPremiumUnlocked = true
                        self.applyPremiumRestrictions()
                        let done = NSAlert()
                        done.messageText = "Thank You!"
                        done.informativeText = "pxf Pro has been unlocked."
                        done.alertStyle = .informational
                        done.addButton(withTitle: "OK")
                        await done.beginSheetModal(for: window)
                    }
                }
            } else if response == .alertSecondButtonReturn {
                // Restore
                Task { @MainActor in
                    let entitled = await self.storeManager?.checkEntitlement() ?? false
                    let done = NSAlert()
                    if entitled {
                        self.isPremiumUnlocked = true
                        self.applyPremiumRestrictions()
                        done.messageText = "Purchase Restored"
                        done.informativeText = "pxf Pro has been unlocked."
                    } else {
                        done.messageText = "No Purchase Found"
                        done.informativeText = "No previous purchase was found for this Apple ID."
                    }
                    done.alertStyle = .informational
                    done.addButton(withTitle: "OK")
                    await done.beginSheetModal(for: window)
                }
            }
        }
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
            watermarkButton.title = isPremiumUnlocked ? "Manage Watermarks" : "Manage Watermarks (Pro)"
            watermarkButton.bezelStyle = .rounded
            watermarkButton.target = self
            watermarkButton.action = #selector(showWatermarkManagement)
            watermarkButton.isEnabled = isPremiumUnlocked
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

            let modeLabel = NSTextField(labelWithString: "Mode")
            modeLabel.frame = NSRect(x: 50, y: 133, width: 40, height: 20)
            // Use the same color as the main window's Output label
            modeLabel.textColor = mainLabelColor

            // Create mode popup for settings window
            let modePopup = NSPopUpButton(frame: NSRect(x: 95, y: 130, width: 120, height: 26))
            modePopup.addItems(withTitles: ["Light", "Dark", "Auto"])
            modePopup.selectItem(at: selectedMode)
            modePopup.target = self
            modePopup.action = #selector(modePopupChanged(_:))
            self.modePopup = modePopup

            let contentView = NSView()
            contentView.wantsLayer = true

            if isDark {
                contentView.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
            } else {
                contentView.layer?.backgroundColor = NSColor(red: 0.655, green: 0.655, blue: 0.655, alpha: 1.0).cgColor
            }

            contentView.addSubview(watermarkButton)
            contentView.addSubview(lutButton)
            contentView.addSubview(modeLabel)
            contentView.addSubview(modePopup)

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
        switch selectedFormat {
        case 0: return .quickTime
        case 1: return .mpeg4
        case 2: return .mxf
        default: return .quickTime
        }
    }

    private func currentVideoCodec() -> VideoCodec {
        let format = currentOutputFormat()
        let codecs = VideoCodec.codecs(for: format)
        let index = codecPopup?.indexOfSelectedItem ?? 0
        guard index >= 0 && index < codecs.count else {
            return codecs.first ?? .h265
        }
        return codecs[index]
    }
    
    private func convertProResWithAVFoundation(inputURL: URL, outputURL: URL, logURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            appendLog(logURL: logURL, entry: "AVFoundation: Failed to create export session\n")
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        let session = exportSession
        let done = completion
        session.exportAsynchronously {
            DispatchQueue.main.async { [weak self] in
                let success = session.status == .completed
                if !success {
                    let error = session.error?.localizedDescription ?? "unknown error"
                    self?.appendLog(logURL: logURL, entry: "AVFoundation export failed: \(error)\n")
                }
                done(success)
            }
        }
    }
}
