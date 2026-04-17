import Foundation

// Metadata extracted from a Windows ISO file
struct ISOMetadata: Sendable {
    let filePath: URL
    let fileSize: Int64
    let mountPoint: String?
    let hasInstallWim: Bool
    let hasInstallEsd: Bool
    let installImageSize: Int64  // Size of install.wim or install.esd in bytes
    let needsSplit: Bool         // True if install.wim exceeds the 4GB FAT32 limit

    // ISO file name for display
    var sourceDescription: String {
        filePath.lastPathComponent
    }

    // Human-readable file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    // Human-readable install image size
    var formattedInstallImageSize: String {
        ByteCountFormatter.string(fromByteCount: installImageSize, countStyle: .file)
    }

    // Description of the install image type found
    var installImageType: String {
        if hasInstallWim { return "install.wim" }
        if hasInstallEsd { return "install.esd" }
        return "Unknown"
    }
}
