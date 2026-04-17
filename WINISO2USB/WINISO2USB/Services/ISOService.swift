import Foundation
import os

// Handles ISO validation, mounting, metadata extraction, and cleanup
final class ISOService: Sendable {
    private let logger = Logger(subsystem: "com.winiso2usb.app", category: "ISOService")
    private static let fourGB: Int64 = 4 * 1024 * 1024 * 1024

    // Validate that a file contains a valid ISO 9660 signature ("CD001" at offset 32769)
    func validateISO(at path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WINISO2USBError.isoNotFound(path.path)
        }

        let handle = try FileHandle(forReadingFrom: path)
        defer { handle.closeFile() }

        handle.seek(toFileOffset: 32769)
        let data = handle.readData(ofLength: 5)

        let expected = Data([0x43, 0x44, 0x30, 0x30, 0x31]) // "CD001"
        return data == expected
    }

    // Mount an ISO image and return the mount point path
    func mountISO(at path: URL) async throws -> String {
        // Check if already mounted
        if let existing = try? await findExistingMount(for: path) {
            logger.info("ISO already mounted at: \(existing)")
            return existing
        }

        logger.info("Mounting ISO: \(path.path)")
        let result = try await ProcessRunner.run(
            "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", path.path]
        )
        guard result.succeeded else {
            throw WINISO2USBError.isoMountFailed(result.stderr)
        }

        // Parse mount point from hdiutil output (last column of last /Volumes/ line)
        let lines = result.stdout.components(separatedBy: .newlines)
        for line in lines.reversed() {
            if let range = line.range(of: "/Volumes/") {
                let mountPoint = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                logger.info("ISO mounted at: \(mountPoint)")
                return mountPoint
            }
        }

        // Fallback: scan /Volumes for common Windows ISO volume names
        return try detectISOVolume()
    }

    // Examine a mounted ISO and return metadata about its contents
    func extractMetadata(isoPath: URL, mountPoint: String) throws -> ISOMetadata {
        let fm = FileManager.default
        let wimPath = "\(mountPoint)/sources/install.wim"
        let esdPath = "\(mountPoint)/sources/install.esd"

        let hasWim = fm.fileExists(atPath: wimPath)
        let hasEsd = fm.fileExists(atPath: esdPath)

        guard hasWim || hasEsd else {
            throw WINISO2USBError.isoNoInstallImage
        }

        let installPath = hasWim ? wimPath : esdPath
        let attrs = try fm.attributesOfItem(atPath: installPath)
        let installSize = (attrs[.size] as? Int64) ?? 0

        let isoAttrs = try fm.attributesOfItem(atPath: isoPath.path)
        let isoSize = (isoAttrs[.size] as? Int64) ?? 0

        let needsSplit = hasWim && installSize > Self.fourGB

        return ISOMetadata(
            filePath: isoPath,
            fileSize: isoSize,
            mountPoint: mountPoint,
            hasInstallWim: hasWim,
            hasInstallEsd: hasEsd,
            installImageSize: installSize,
            needsSplit: needsSplit
        )
    }

    // Detach a mounted ISO volume
    func unmountISO(at mountPoint: String) async throws {
        logger.info("Detaching ISO at: \(mountPoint)")
        let result = try await ProcessRunner.run(
            "/usr/bin/hdiutil",
            arguments: ["detach", mountPoint]
        )
        if !result.succeeded {
            logger.warning("hdiutil detach non-zero: \(result.stderr)")
        }
    }

    // Check hdiutil info for an already-mounted ISO matching the given path
    private func findExistingMount(for isoPath: URL) async throws -> String? {
        let result = try await ProcessRunner.run(
            "/usr/bin/hdiutil",
            arguments: ["info"]
        )
        guard result.succeeded else { return nil }

        var foundISO = false
        for line in result.stdout.components(separatedBy: .newlines) {
            if line.contains(isoPath.path) {
                foundISO = true
            } else if foundISO, let range = line.range(of: "/Volumes/") {
                let mount = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                if FileManager.default.fileExists(atPath: mount) {
                    return mount
                }
            }
        }
        return nil
    }

    // Scan /Volumes for common Windows ISO volume name patterns
    private func detectISOVolume() throws -> String {
        let prefixes = ["CCCOMA_", "ESD-ISO", "ESD-USB", "DVD", "Windows"]
        let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []

        for vol in volumes {
            for prefix in prefixes {
                if vol.hasPrefix(prefix) {
                    return "/Volumes/\(vol)"
                }
            }
        }
        throw WINISO2USBError.isoMountFailed("Could not locate mounted ISO volume under /Volumes")
    }
}
