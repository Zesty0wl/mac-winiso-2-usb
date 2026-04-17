import Foundation
import os

// Small MainActor-isolated reference wrapper used to share mutable counters
// between the non-isolated stdout callback and the MainActor Task that
// updates UI state. @MainActor classes are implicitly Sendable in Swift 6.
@MainActor
private final class IntBox {
    var value: Int
    init(_ value: Int) { self.value = value }
}

// Orchestrates the full USB creation pipeline: erase, mount ISO, copy, split, eject.
@MainActor
final class USBCreationService: ObservableObject {
    @Published var progress = CreationProgress()

    private let diskService: DiskService
    private let isoService = ISOService()
    private let logger = Logger(subsystem: "com.winiso2usb.app", category: "USBCreation")
    private var cancelRequested = false

    init(diskService: DiskService) {
        self.diskService = diskService
    }

    // Run the full creation pipeline from erase through eject
    func createBootableUSB(
        isoPath: URL,
        drive: USBDrive,
        volumeName: String,
        splitSizeMB: Int
    ) async throws {
        cancelRequested = false
        progress = CreationProgress()

        do {
            // 1. Unmount target disk
            updateProgress(.unmounting, 0.05)
            addLog("Unmounting /dev/\(drive.id)...")
            try await diskService.unmountDisk(drive)
            try checkCancelled()

            // 2. Erase as GPT + FAT32
            updateProgress(.erasing, 0.10)
            addLog("Erasing /dev/\(drive.id) as GPT + FAT32 (\(volumeName))...")
            try await diskService.eraseDisk(drive, volumeName: volumeName)
            try checkCancelled()

            let usbVolPath = "/Volumes/\(volumeName)"
            guard FileManager.default.fileExists(atPath: usbVolPath) else {
                throw WINISO2USBError.diskEraseFailed("Volume not found at \(usbVolPath) after formatting")
            }
            addLog("USB volume mounted at \(usbVolPath)")

            // 3. Mount ISO
            updateProgress(.mountingISO, 0.15)
            addLog("Mounting ISO: \(isoPath.lastPathComponent)...")
            let mountPoint = try await isoService.mountISO(at: isoPath)
            addLog("ISO mounted at \(mountPoint)")
            try checkCancelled()

            // 4. Determine install image situation
            let wimPath = "\(mountPoint)/sources/install.wim"
            let esdPath = "\(mountPoint)/sources/install.esd"
            let fm = FileManager.default
            let needsSplit: Bool
            let installPath: String

            if fm.fileExists(atPath: wimPath) {
                installPath = wimPath
                let attrs = try fm.attributesOfItem(atPath: wimPath)
                let size = (attrs[.size] as? Int64) ?? 0
                needsSplit = size > 4 * 1024 * 1024 * 1024
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                addLog("Found install.wim (\(sizeStr))\(needsSplit ? " - split required" : "")")
            } else if fm.fileExists(atPath: esdPath) {
                installPath = esdPath
                needsSplit = false
                addLog("Found install.esd (no split needed)")
            } else {
                throw WINISO2USBError.isoNoInstallImage
            }
            try checkCancelled()

            // 5. Copy files
            updateProgress(.copying, 0.20)
            if needsSplit {
                addLog("Copying files (excluding install.wim)...")
                try await rsyncFiles(
                    from: mountPoint,
                    to: usbVolPath,
                    excluding: "sources/install.wim"
                )
                try checkCancelled()

                // 6. Split install.wim
                updateProgress(.splitting, 0.75)
                addLog("Splitting install.wim into \(splitSizeMB)MB chunks...")
                try await splitWim(
                    wimPath: installPath,
                    destination: "\(usbVolPath)/sources/install.swm",
                    splitSizeMB: splitSizeMB
                )
            } else {
                addLog("Copying all ISO contents...")
                try await rsyncFiles(from: mountPoint, to: usbVolPath)
            }
            try checkCancelled()

            // 7. Sync
            updateProgress(.syncing, 0.90)
            addLog("Flushing writes to disk...")
            _ = try await ProcessRunner.run("/bin/sync")

            // 8. Detach ISO
            addLog("Detaching ISO...")
            try await isoService.unmountISO(at: mountPoint)

            // 9. Eject USB
            updateProgress(.ejecting, 0.95)
            addLog("Ejecting USB drive...")
            try await diskService.ejectDisk(drive)

            updateProgress(.complete, 1.0)
            addLog("Bootable Windows USB created successfully.")

        } catch {
            progress.stage = .failed
            if let wfe = error as? WINISO2USBError {
                progress.error = wfe
            } else {
                progress.error = .processError(error.localizedDescription)
            }
            addLog("FAILED: \(error.localizedDescription)")
            throw error
        }
    }

    // Signal cancellation of the running pipeline
    func cancel() {
        cancelRequested = true
        addLog("Cancellation requested...")
    }

    // MARK: - Private helpers

    // Throw if the user has requested cancellation
    private func checkCancelled() throws {
        if cancelRequested { throw WINISO2USBError.cancelled }
    }

    // Update the published progress state
    private func updateProgress(_ stage: CreationProgress.Stage, _ fraction: Double) {
        progress.stage = stage
        progress.overallProgress = fraction
    }

    // Append a line to the visible log
    private func addLog(_ line: String) {
        logger.info("\(line)")
        progress.logLines.append(line)
    }

    // Copy files from source to destination using rsync.
    // Uses -v for per-file output and polls destination size for smooth progress,
    // since macOS's built-in rsync (2.6.9) lacks --info=progress2.
    private func rsyncFiles(
        from source: String,
        to destination: String,
        excluding: String? = nil
    ) async throws {
        var args = ["-av"]
        if let exclude = excluding {
            args += ["--exclude=\(exclude)"]
        }
        args += ["\(source)/", destination]

        // Calculate expected total bytes for the source directory
        let totalBytes = directorySize(atPath: source, excluding: excluding)
        let baseProgress = progress.overallProgress
        let targetProgress = excluding != nil ? 0.75 : 0.85

        // Poll destination size in a background task to update progress
        let destPath = destination
        let pollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                let copiedBytes = self?.directorySize(atPath: destPath, excluding: nil) ?? 0
                let fraction: Double
                if totalBytes > 0 {
                    fraction = min(Double(copiedBytes) / Double(totalBytes), 1.0)
                } else {
                    fraction = 0
                }
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let range = targetProgress - baseProgress
                    self.progress.overallProgress = baseProgress + (range * fraction)
                }
            }
        }

        // Track file count for log throttling
        let fileCount = IntBox(0)

        let result = try await ProcessRunner.runWithOutput(
            "/usr/bin/rsync",
            arguments: args
        ) { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // rsync -v outputs relative file paths, skip blank/summary lines
                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("sending "),
                      !trimmed.hasPrefix("sent "),
                      !trimmed.hasPrefix("total "),
                      !trimmed.hasPrefix("building file") else {
                    return
                }
                // Show current file being copied
                self.progress.currentFile = trimmed
                fileCount.value += 1
                // Log every 50th file to keep the log useful without flooding
                if fileCount.value % 50 == 1 {
                    self.addLog("  Copying: \(trimmed)")
                }
            }
        }

        pollTask.cancel()

        guard result.succeeded else {
            throw WINISO2USBError.copyFailed(result.stderr)
        }

        addLog("  Copied \(fileCount.value) files")
        progress.overallProgress = targetProgress
        progress.currentFile = ""
    }

    // Calculate the total size in bytes of a directory, optionally skipping one path
    nonisolated private func directorySize(atPath path: String, excluding: String?) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            if let exclude = excluding, file.hasPrefix(exclude) {
                continue
            }
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    // Split an oversized install.wim using wimlib-imagex.
    // Parses wimlib progress output to show percentage, speed, and ETA.
    private func splitWim(
        wimPath: String,
        destination: String,
        splitSizeMB: Int
    ) async throws {
        let wimlibPath = try await findWimlib()
        addLog("Using wimlib at: \(wimlibPath)")

        // Ensure the destination directory exists
        let destDir = (destination as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: destDir,
            withIntermediateDirectories: true
        )

        let lastLoggedPct = IntBox(-1)
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await ProcessRunner.runWithOutput(
            wimlibPath,
            arguments: ["split", wimPath, destination, String(splitSizeMB)]
        ) { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self = self else { return }                // Parse "Splitting WIM: 512 MiB of 6509 MiB (7%) written, part 1 of 2"
                if let info = self.parseWimlibDetail(line) {
                    let fraction = Double(info.pct) / 100.0
                    self.progress.overallProgress = 0.75 + (0.15 * fraction)

                    // Calculate speed and ETA from elapsed time and MiB written
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    var statusParts = ["Splitting: \(info.pct)%"]
                    if elapsed > 2 && info.writtenMiB > 0 {
                        let speedMBps = Double(info.writtenMiB) / elapsed
                        statusParts.append(String(format: "%.0f MB/s", speedMBps))
                        let remainingMiB = info.totalMiB - info.writtenMiB
                        if speedMBps > 0 && remainingMiB > 0 {
                            let etaSeconds = Int(Double(remainingMiB) / speedMBps)
                            let mins = etaSeconds / 60
                            let secs = etaSeconds % 60
                            if mins > 0 {
                                statusParts.append("\(mins)m \(secs)s remaining")
                            } else {
                                statusParts.append("\(secs)s remaining")
                            }
                        }
                    }
                    self.progress.currentFile = statusParts.joined(separator: " - ")

                    // Log every 10%
                    let rounded = (info.pct / 10) * 10
                    if rounded > lastLoggedPct.value && rounded > 0 {
                        lastLoggedPct.value = rounded
                        self.addLog("  wimlib: \(info.pct)% complete")
                    }
                }
            }
        }

        guard result.succeeded else {
            throw WINISO2USBError.wimSplitFailed(result.stderr)
        }

        let totalTime = Int(CFAbsoluteTimeGetCurrent() - startTime)
        addLog("  Split complete in \(totalTime / 60)m \(totalTime % 60)s")
        progress.currentFile = ""
    }

    // Parsed fields from a wimlib progress line
    private struct WimlibProgress {
        let writtenMiB: Int
        let totalMiB: Int
        let pct: Int
    }

    // Parse MiB written, total MiB, and percentage from wimlib output.
    // Input: "Splitting WIM: 512 MiB of 6509 MiB (7%) written, part 1 of 2"
    private func parseWimlibDetail(_ line: String) -> WimlibProgress? {
        guard let regex = try? NSRegularExpression(
            pattern: "(\\d+)\\s+MiB\\s+of\\s+(\\d+)\\s+MiB\\s+\\((\\d+)%\\)"
        ) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let writtenRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line),
              let pctRange = Range(match.range(at: 3), in: line),
              let written = Int(line[writtenRange]),
              let total = Int(line[totalRange]),
              let pct = Int(line[pctRange]) else {
            return nil
        }
        return WimlibProgress(writtenMiB: written, totalMiB: total, pct: pct)
    }

    // Parse percentage from wimlib output (simple fallback).
    // Matches "(42%)" in lines like "Splitting WIM: 512 MiB of 6509 MiB (42%) written"
    private func parseWimlibProgress(_ line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\((\\d+)%\\)") else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, range: range),
           let pctRange = Range(match.range(at: 1), in: line) {
            return Int(line[pctRange])
        }
        return nil
    }

    // Locate the wimlib-imagex binary, preferring the bundled copy
    private func findWimlib() async throws -> String {
        // Check the bundled copy in Resources/bin
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = (resourcePath as NSString).appendingPathComponent("bin/wimlib-imagex")
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Fallback: check common Homebrew paths
        let searchPaths = [
            "/opt/homebrew/bin/wimlib-imagex",
            "/usr/local/bin/wimlib-imagex",
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Last resort: PATH lookup
        if let result = try? await ProcessRunner.run(
            "/usr/bin/which", arguments: ["wimlib-imagex"]
        ), result.succeeded {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }

        throw WINISO2USBError.wimlibNotFound
    }
}
