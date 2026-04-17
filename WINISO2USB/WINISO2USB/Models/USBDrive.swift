import Foundation

// Represents a connected USB drive available for formatting
struct USBDrive: Identifiable, Hashable, Sendable {
    let id: String          // BSD name, e.g. "disk2"
    let name: String        // Volume or media name
    let size: Int64         // Size in bytes
    let busProtocol: String // e.g. "USB", "Thunderbolt"
    let isRemovable: Bool

    // Human-readable size string
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // Display name for the UI
    var displayName: String {
        let label = name.isEmpty ? "Untitled" : name
        return "\(label) (\(id))"
    }
}
