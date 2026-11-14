import Foundation
import Combine
import os

// Enumerates and manages external USB drives
@MainActor
final class DiskService: ObservableObject {
    @Published var availableDrives: [USBDrive] = []
    @Published var isScanning: Bool = false

    private let logger = Logger(subsystem: "com.winiso2usb.app", category: "DiskService")
    private var pollTimer: Timer?

    init() {
        startMonitoring()
    }

    // Begin periodic scanning for USB drives
    func startMonitoring() {
        refreshDrives()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDrives()
            }
        }
    }

    // Stop periodic scanning
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // Trigger a fresh scan for USB drives
    func refreshDrives() {
        // Screenshot mode shows sample drives: don't replace them with the real ones.
        guard !ScreenshotMode.isActive else { return }
        Task {
            do {
                let drives = try await scanForUSBDrives()
                self.availableDrives = drives
            } catch {
                logger.error("Failed to scan drives: \(error.localizedDescription)")
            }
        }
    }

    // Enumerate external physical disks via diskutil
    private func scanForUSBDrives() async throws -> [USBDrive] {
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["list", "-plist", "external", "physical"]
        )

        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let wholeDisks = plist["WholeDisks"] as? [String] else {
            return []
        }

        // Get the boot disk identifier so we never show it
        let bootDisk = try? await getBootDiskIdentifier()

        var drives: [USBDrive] = []
        for bsdName in wholeDisks {
            if bsdName == bootDisk { continue }
            if let drive = try? await getDriveInfo(bsdName: bsdName) {
                if drive.isRemovable {
                    drives.append(drive)
                }
            }
        }
        return drives
    }

    // Query diskutil info for a single disk and build a USBDrive model
    private func getDriveInfo(bsdName: String) async throws -> USBDrive {
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["info", "-plist", bsdName]
        )
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let info = try PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else {
            throw WINISO2USBError.diskNotFound
        }

        let name = (info["MediaName"] as? String)
            ?? (info["VolumeName"] as? String)
            ?? ""
        let size = (info["TotalSize"] as? Int64)
            ?? (info["Size"] as? Int64)
            ?? 0
        let removableMedia = (info["RemovableMedia"] as? Bool) ?? false
        let removableOrExternal = (info["RemovableMediaOrExternalDevice"] as? Bool) ?? false
        let isInternal = (info["Internal"] as? Bool) ?? true
        let busProtocol = (info["BusProtocol"] as? String) ?? ""
        let ejectable = (info["Ejectable"] as? Bool) ?? false

        // Consider a drive removable if it is flagged as external/removable
        // and not internal
        let isUSB = busProtocol.lowercased().contains("usb")
        let isRemovable = (removableMedia || removableOrExternal || isUSB || ejectable) && !isInternal

        return USBDrive(
            id: bsdName,
            name: name,
            size: size,
            busProtocol: busProtocol,
            isRemovable: isRemovable
        )
    }

    // Determine the BSD name of the boot disk
    private func getBootDiskIdentifier() async throws -> String? {
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["info", "-plist", "/"]
        )
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let info = try PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else {
            return nil
        }
        return info["ParentWholeDisk"] as? String
    }

    // Unmount all volumes on a disk
    func unmountDisk(_ drive: USBDrive) async throws {
        logger.info("Unmounting \(drive.id)")
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["unmountDisk", drive.id]
        )
        if !result.succeeded {
            logger.warning("Unmount returned non-zero, continuing: \(result.stderr)")
        }
    }

    // Erase a disk with GPT partition scheme and FAT32 format
    func eraseDisk(_ drive: USBDrive, volumeName: String) async throws {
        logger.info("Erasing \(drive.id) as GPT/FAT32 with name \(volumeName)")
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["eraseDisk", "MS-DOS", volumeName, "GPT", drive.id]
        )
        guard result.succeeded else {
            throw WINISO2USBError.diskEraseFailed(result.stderr)
        }
        // Give macOS time to mount the new volume
        try await Task.sleep(for: .seconds(2))
    }

    // Eject a disk safely
    func ejectDisk(_ drive: USBDrive) async throws {
        logger.info("Ejecting \(drive.id)")
        let result = try await ProcessRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["eject", drive.id]
        )
        if !result.succeeded {
            logger.warning("Eject returned non-zero: \(result.stderr)")
        }
    }
}
