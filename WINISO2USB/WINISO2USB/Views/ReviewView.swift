import SwiftUI

// Step 3: Review selections and confirm before starting the destructive operation.
// The ISO flows into the drive, left to right; below them, the confirmation that guards the erase.
struct ReviewView: View {
    @EnvironmentObject var wizardState: WizardState
    // Screenshot mode shows the screen as it is once the confirmation has been typed.
    @State private var confirmText: String = ScreenshotMode.isActive ? "ERASE" : ""
    @State private var confirmed: Bool = ScreenshotMode.isActive

    var body: some View {
        VStack(spacing: 16) {
            Text("Review and confirm")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.top, 10)

            // What goes where
            HStack(spacing: 12) {
                if let meta = wizardState.isoMetadata {
                    summaryCard(icon: "opticaldisc.fill", title: "Windows ISO", name: meta.sourceDescription) {
                        infoRow("Size", meta.formattedFileSize)
                        infoRow("Image", "\(meta.installImageType), \(meta.formattedInstallImageSize)")
                        infoRow("Split", meta.needsSplit ? "\(wizardState.splitSizeMB) MB parts" : "Not needed")
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.gradient, in: Circle())
                    .shadow(color: Theme.blue.opacity(0.5), radius: 8, y: 2)

                if let drive = wizardState.selectedDrive {
                    summaryCard(icon: "externaldrive.fill", title: "Target USB", name: drive.name.isEmpty ? "Untitled" : drive.name) {
                        infoRow("Size", drive.formattedSize)
                        infoRow("Device", "/dev/\(drive.id)")
                        infoRow("Bus", drive.busProtocol.isEmpty ? "External" : drive.busProtocol)
                    }
                }
            }

            // Volume name
            HStack {
                Text("Volume name")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("WINDOWSUSB", text: $wizardState.volumeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 180)
            }

            // Warning and confirmation
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text("Everything on the selected USB drive will be permanently erased.")
                        .font(.callout)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 10) {
                    Text("Type")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("ERASE")
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.danger)
                    Text("to confirm")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    TextField("", text: $confirmText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100)
                        .onChange(of: confirmText) { _, newValue in
                            confirmed = (newValue == "ERASE")
                        }

                    Button {
                        wizardState.advance()
                    } label: {
                        Label("Erase and Create", systemImage: "bolt.fill")
                    }
                    .buttonStyle(GlowButtonStyle(danger: true))
                    .disabled(!confirmed)
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.red.opacity(0.3)))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
    }

    // One side of the transfer: an icon, what it is, its name and a few facts
    private func summaryCard<Content: View>(
        icon: String,
        title: String,
        name: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(systemImage: icon, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // Key-value row
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}
