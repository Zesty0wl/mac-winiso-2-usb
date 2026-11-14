import SwiftUI
import UniformTypeIdentifiers

// Step 1: Drag-and-drop target for a Windows ISO file.
// With no ISO it's a drop zone around a spinning disc; once one is loaded it shows what was found in it.
struct ISODropView: View {
    @EnvironmentObject var wizardState: WizardState
    @State private var isDragOver = false
    @State private var isValidating = false
    @State private var dash: CGFloat = 0

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
    }

    // Drop zone shown when no ISO is selected: its dashed edge creeps round, and lights up when a file is over it
    private var emptyDropView: some View {
        VStack(spacing: 14) {
            DiscArt()
                .padding(.bottom, 6)

            Text(isDragOver ? "Release to load the ISO" : "Drop a Windows ISO here")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Windows 10 or 11, as an .iso file")
                .foregroundStyle(.secondary)

            Button {
                pickLocalISO()
            } label: {
                Label("Browse…", systemImage: "folder")
            }
            .buttonStyle(GlowButtonStyle())
            .padding(.top, 6)
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 34)
        .padding(.horizontal, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.spectrum, style: StrokeStyle(lineWidth: isDragOver ? 3 : 1.5, dash: [9, 7], dashPhase: dash))
                .opacity(isDragOver ? 1 : 0.7)
        )
        .shadow(color: Theme.blue.opacity(isDragOver ? 0.45 : 0.12), radius: isDragOver ? 30 : 16, y: 8)
        .scaleEffect(isDragOver ? 1.02 : 1)
        .animation(.spring(duration: 0.3), value: isDragOver)
        .onAppear {
            guard !ScreenshotMode.isActive else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { dash = -16 }
        }
    }

    // Shown while the ISO is being validated and mounted
    private var validatingView: some View {
        VStack(spacing: 16) {
            DiscArt(size: 96)
            ProgressView()
                .controlSize(.small)
            Text("Checking the ISO…")
                .foregroundStyle(.secondary)
        }
    }

    // What was found, once the ISO is loaded
    private func loadedView(_ meta: ISOMetadata) -> some View {
        VStack(spacing: 16) {
            DiscArt(size: 104, ready: true)

            VStack(spacing: 4) {
                Text("ISO ready")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(meta.sourceDescription)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                statTile("ISO size", meta.formattedFileSize, "internaldrive")
                statTile(meta.installImageType, meta.formattedInstallImageSize, "shippingbox")
                statTile("Splitting", meta.needsSplit ? "Required" : "Not needed", "square.split.2x1")
            }
            .frame(maxWidth: 520)

            if meta.needsSplit {
                Text("install.wim is over FAT32's 4 GB limit, so it will be split into parts on the drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Choose a different ISO") {
                wizardState.isoFilePath = nil
                wizardState.isoMetadata = nil
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.horizontal, 24)
    }

    // One fact about the ISO: a label, its value and an icon
    private func statTile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.gradient)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14, padding: 14)
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
