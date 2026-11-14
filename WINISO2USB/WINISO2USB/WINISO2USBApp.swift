import SwiftUI

@main
struct WINISO2USBApp: App {
    @StateObject private var wizardState = WizardState()
    @StateObject private var diskService = DiskService()
    @StateObject private var creationService: USBCreationService

    init() {
        let ds = DiskService()
        _diskService = StateObject(wrappedValue: ds)
        _creationService = StateObject(wrappedValue: USBCreationService(diskService: ds))
    }

    var body: some Scene {
        WindowGroup {
            WizardContainerView()
                .environmentObject(wizardState)
                .environmentObject(diskService)
                .environmentObject(creationService)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    #if DEBUG
                    await ScreenshotMode.run(wizard: wizardState, disks: diskService, creation: creationService)
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Screenshots
//
// Debug builds can produce the README's screenshots themselves, with sample data and no ISO or USB drive:
//
//   WINISO2USB.app/Contents/MacOS/WINISO2USB -screenshots <folder> [-appearance dark] [-walkthrough YES]
//
// The app walks through the wizard's steps, saves a PNG of its window for each and quits. While this mode is on,
// nothing scans for drives and nothing is erased or written (see the `isActive` checks in the views).
// `docs/screenshots.sh` builds the app and runs this for light and dark, and makes the walkthrough video.
enum ScreenshotMode {
    #if DEBUG
    static let directory: URL? = UserDefaults.standard.string(forKey: "screenshots").map { URL(fileURLWithPath: $0, isDirectory: true) }
    #else
    static let directory: URL? = nil
    #endif

    static var isActive: Bool { directory != nil }
}

#if DEBUG
extension ScreenshotMode {
    private static let iso = ISOMetadata(
        filePath: URL(fileURLWithPath: "/Users/you/Downloads/Win11_24H2_English_x64.iso"),
        fileSize: 5_819_484_160,
        mountPoint: "/Volumes/CCCOMA_X64FRE_EN-GB_DV9",
        hasInstallWim: true,
        hasInstallEsd: false,
        installImageSize: 5_268_103_168,
        needsSplit: true
    )

    private static let drives = [
        USBDrive(id: "disk4", name: "SanDisk Ultra", size: 30_752_636_928, busProtocol: "USB", isRemovable: true),
        USBDrive(id: "disk5", name: "Kingston DataTraveler", size: 61_530_439_680, busProtocol: "USB", isRemovable: true),
    ]

    @MainActor
    static func run(wizard: WizardState, disks: DiskService, creation: USBCreationService) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if UserDefaults.standard.string(forKey: "appearance") == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { NSApp.terminate(nil); return }
        window.setContentSize(NSSize(width: 860, height: 640))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // With `-walkthrough YES` the same run also steps the progress screen from start to finish and numbers every
        // frame, writing `frames.txt` (ffmpeg's concat format: each frame and how long it stays up) for the video.
        let walkthrough = UserDefaults.standard.bool(forKey: "walkthrough")
        var frames: [String] = []
        var count = 0
        func shot(_ name: String, hold: Double = 1.6, settle: Int = 900, _ prepare: () -> Void) async {
            prepare()
            try? await Task.sleep(for: .milliseconds(settle))
            count += 1
            let file = walkthrough ? String(format: "%03d.png", count) : "\(name).png"
            capture(window, to: directory.appendingPathComponent(file))
            frames.append("file '\(file)'\nduration \(hold)")
        }
        func progress(_ stage: CreationProgress.Stage, _ fraction: Double, file: String = "", log: [String] = []) {
            var p = creation.progress
            p.stage = stage
            p.overallProgress = fraction
            p.currentFile = file
            p.logLines += log
            creation.progress = p
        }

        await shot("1-select-iso") {
            wizard.reset()
        }
        await shot("2-iso-ready", hold: 2.0) {
            wizard.isoFilePath = iso.filePath
            wizard.isoMetadata = iso
        }
        if walkthrough {
            await shot("select-usb-none", hold: 1.0) {
                disks.availableDrives = drives
                wizard.currentStep = .selectUSB
            }
        }
        await shot("3-select-usb") {
            disks.availableDrives = drives
            wizard.selectedDrive = drives[0]
            wizard.currentStep = .selectUSB
        }
        await shot("4-review", hold: 2.4) {
            wizard.currentStep = .review
        }

        let copied = ["boot/bcd", "boot/boot.sdi", "efi/boot/bootx64.efi", "efi/microsoft/boot/bcd", "sources/boot.wim"]
        if walkthrough {
            await shot("unmounting", hold: 0.5, settle: 500) {
                creation.progress = CreationProgress()
                progress(.unmounting, 0.05, log: ["Unmounting /dev/disk4..."])
                wizard.currentStep = .progress
            }
            await shot("erasing", hold: 0.7, settle: 300) {
                progress(.erasing, 0.10, log: ["Erasing /dev/disk4 as GPT + FAT32 (WINDOWSUSB)..."])
            }
            await shot("mounting", hold: 0.6, settle: 300) {
                progress(.mountingISO, 0.15, log: ["USB volume mounted at /Volumes/WINDOWSUSB", "Mounting ISO: Win11_24H2_English_x64.iso..."])
            }
            await shot("found", hold: 0.6, settle: 300) {
                progress(.copying, 0.20, log: ["ISO mounted at /Volumes/CCCOMA_X64FRE_EN-GB_DV9", "Found install.wim (5.27 GB) - split required", "Copying files (excluding install.wim)..."])
            }
            for (i, path) in copied.enumerated() {
                await shot("copying-\(i)", hold: 0.45, settle: 300) {
                    progress(.copying, 0.26 + Double(i) * 0.11, file: path, log: ["  Copying: \(path)"])
                }
            }
            for (i, pct) in [0, 25, 50, 75].enumerated() {
                let done = String(format: "%.1f", 5.27 * Double(pct) / 100)
                await shot("splitting-\(i)", hold: 0.55, settle: 300) {
                    progress(.splitting, 0.75 + Double(pct) * 0.0014, file: "install.wim - \(done) GB of 5.27 GB - \(pct)%",
                             log: i == 0 ? ["  Copied 912 files", "Splitting install.wim into 3800MB chunks...", "Using wimlib at: WINISO2USB.app/Contents/Resources/bin/wimlib-imagex"] : ["  wimlib: \(pct)% complete"])
                }
            }
            await shot("syncing", hold: 0.6, settle: 300) {
                progress(.syncing, 0.90, log: ["  wimlib: 100% complete", "  Split complete in 4m 12s", "Flushing writes to disk..."])
            }
            await shot("ejecting", hold: 0.6, settle: 300) {
                progress(.ejecting, 0.95, log: ["Detaching ISO...", "Ejecting USB drive..."])
            }
            await shot("done", hold: 1.6, settle: 400) {
                progress(.complete, 1.0, log: ["Bootable Windows USB created successfully."])
            }
        } else {
            let start = ["Unmounting /dev/disk4...", "Erasing /dev/disk4 as GPT + FAT32 (WINDOWSUSB)...", "USB volume mounted at /Volumes/WINDOWSUSB",
                         "Mounting ISO: Win11_24H2_English_x64.iso...", "ISO mounted at /Volumes/CCCOMA_X64FRE_EN-GB_DV9",
                         "Found install.wim (5.27 GB) - split required", "Copying files (excluding install.wim)..."]
            await shot("5-creating") {
                creation.progress = CreationProgress()
                progress(.copying, 0.47, file: "sources/boot.wim", log: start + copied.map { "  Copying: \($0)" })
                wizard.currentStep = .progress
            }
            await shot("6-splitting") {
                progress(.splitting, 0.82, file: "install.wim - 3.1 GB of 5.27 GB - 58%",
                         log: ["  Copied 912 files", "Splitting install.wim into 3800MB chunks...", "Using wimlib at: WINISO2USB.app/Contents/Resources/bin/wimlib-imagex", "  wimlib: 25% complete", "  wimlib: 50% complete"])
            }
        }
        await shot("7-complete", hold: 3.0) {
            wizard.currentStep = .completion
        }
        if walkthrough, let last = frames.last?.split(separator: "\n").first {
            // ffmpeg's concat needs the last file named again for its duration to count.
            try? (frames + [String(last)]).joined(separator: "\n").write(to: directory.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }

    // Save a picture of the window. `screencapture` gives the real thing (rounded corners, shadow) but needs the
    // Screen Recording permission; without it, the window draws itself into an image instead (square, no shadow).
    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) {
        try? FileManager.default.removeItem(at: url)
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        tool.arguments = ["-x", "-l", String(window.windowNumber), url.path]
        tool.standardError = FileHandle.nullDevice
        try? tool.run()
        tool.waitUntilExit()
        if tool.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
            print("captured \(url.lastPathComponent)")
            return
        }
        guard let frame = window.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("drew \(url.lastPathComponent) (no Screen Recording permission)")
    }
}
#endif
