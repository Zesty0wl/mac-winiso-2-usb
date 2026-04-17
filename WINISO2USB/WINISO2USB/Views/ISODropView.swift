import SwiftUI
import UniformTypeIdentifiers

// Step 1: Drag-and-drop target for a Windows ISO file.
// When no ISO is loaded, shows a compact drop zone. Once loaded, the zone
// transforms into a summary card so the user can see the result and proceed.
struct ISODropView: View {
    @EnvironmentObject var wizardState: WizardState
    @State private var isDragOver = false
    @State private var isValidating = false

    private var hasISO: Bool { wizardState.isoMetadata != nil }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if isValidating {
                validatingView
            } else if let meta = wizardState.isoMetadata {
                loadedView(meta)
            } else {
                emptyDropView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .overlay(dragOverlay)
    }

    // Drop zone shown when no ISO is selected
    private var emptyDropView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Drop a Windows .iso file here")
                .font(.headline)

            Text("or")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Browse...") {
                pickLocalISO()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 400)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        )
    }

    // Shown while the ISO is being validated and mounted
    private var validatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Validating ISO...")
                .foregroundColor(.secondary)
        }
    }

    // Summary card after ISO is successfully loaded
    private func loadedView(_ meta: ISOMetadata) -> some View {
        VStack(spacing: 20) {
            // Success header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                Text("ISO Ready")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Details card
            VStack(alignment: .leading, spacing: 6) {
                infoRow("File", meta.sourceDescription)
                infoRow("Size", meta.formattedFileSize)
                infoRow("Install Image", "\(meta.installImageType) (\(meta.formattedInstallImageSize))")
                infoRow("Splitting Required", meta.needsSplit ? "Yes (install.wim > 4 GB)" : "No")
            }
            .padding(16)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Button("Choose a different ISO") {
                wizardState.isoFilePath = nil
                wizardState.isoMetadata = nil
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Click Next to continue.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // Full-window overlay shown when dragging a file over the view
    private var dragOverlay: some View {
        Group {
            if isDragOver {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        )

                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.accentColor)
                        Text("Release to load ISO")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(16)
            }
        }
    }

    // Key-value row for the ISO info card
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }

    // MARK: - Actions

    // Handle a file dropped onto the target
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "iso" else {
                Task { @MainActor in
                    wizardState.showError(
                        .processError("Please drop a file with the .iso extension.")
                    )
                }
                return
            }
            Task { @MainActor in
                await validateAndLoad(url)
            }
        }
        return true
    }

    // Open NSOpenPanel file picker for .iso files
    private func pickLocalISO() {
        let panel = NSOpenPanel()
        panel.title = "Select Windows ISO"
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await validateAndLoad(url)
        }
    }

    // Validate the ISO and extract metadata
    private func validateAndLoad(_ url: URL) async {
        isValidating = true
        defer { isValidating = false }

        do {
            let isoService = ISOService()

            let valid = try isoService.validateISO(at: url)
            guard valid else {
                wizardState.showError(.isoInvalidSignature)
                return
            }

            let mountPoint = try await isoService.mountISO(at: url)
            let metadata = try isoService.extractMetadata(isoPath: url, mountPoint: mountPoint)

            wizardState.isoFilePath = url
            wizardState.isoMetadata = metadata
        } catch {
            if let wfe = error as? WINISO2USBError {
                wizardState.showError(wfe)
            } else {
                wizardState.showError(.processError(error.localizedDescription))
            }
        }
    }
}
