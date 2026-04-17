import SwiftUI

// Step 3: Review selections and confirm before starting the destructive operation.
// ISO and USB summaries are placed side by side to keep everything visible.
struct ReviewView: View {
    @EnvironmentObject var wizardState: WizardState
    @State private var confirmText: String = ""
    @State private var confirmed: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Review and Confirm")
                .font(.title2)
                .fontWeight(.bold)

            // Side-by-side summaries
            HStack(alignment: .top, spacing: 12) {
                // ISO summary
                if let meta = wizardState.isoMetadata {
                    summarySection(title: "Windows ISO", icon: "opticaldisc") {
                        infoRow("File", meta.sourceDescription)
                        infoRow("Size", meta.formattedFileSize)
                        infoRow("Image", "\(meta.installImageType) (\(meta.formattedInstallImageSize))")
                        if meta.needsSplit {
                            infoRow("Split", "Yes (3800 MB chunks)")
                        }
                    }
                }

                // USB drive summary
                if let drive = wizardState.selectedDrive {
                    summarySection(title: "Target USB", icon: "externaldrive") {
                        infoRow("Drive", drive.displayName)
                        infoRow("Size", drive.formattedSize)
                        infoRow("ID", "/dev/\(drive.id)")
                        infoRow("Bus", drive.busProtocol.isEmpty ? "External" : drive.busProtocol)
                    }
                }
            }

            // Volume name
            HStack {
                Text("Volume Name:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                TextField("WINDOWSUSB", text: $wizardState.volumeName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            Divider()

            // Warning and confirmation
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("All data on the selected USB drive will be permanently erased.")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                HStack {
                    Text("Type")
                        .font(.callout)
                    Text("ERASE")
                        .font(.callout)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("to confirm:")
                        .font(.callout)

                    TextField("", text: $confirmText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: confirmText) { _, newValue in
                            confirmed = (newValue == "ERASE")
                        }
                }

                Button("Create Bootable USB") {
                    wizardState.advance()
                }
                .disabled(!confirmed)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(20)
    }

    // Compact summary card
    private func summarySection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)

            Divider()

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // Key-value row with compact sizing
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}
