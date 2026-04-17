import SwiftUI

// Step 5: Success screen with post-creation actions
struct CompletionView: View {
    @EnvironmentObject var wizardState: WizardState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Bootable USB Ready")
                .font(.title)
                .fontWeight(.bold)

            Text("Your Windows USB installation drive (\(wizardState.volumeName)) has been created successfully and is ready for UEFI boot.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                Button {
                    ejectDrive()
                } label: {
                    Label("Eject Drive", systemImage: "eject")
                        .frame(maxWidth: 200)
                }
                .controlSize(.large)

                Button {
                    openInFinder()
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                        .frame(maxWidth: 200)
                }
                .controlSize(.large)

                Button {
                    wizardState.reset()
                } label: {
                    Label("Create Another", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: 200)
                }
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
    }

    // Eject the USB drive
    private func ejectDrive() {
        guard let drive = wizardState.selectedDrive else { return }
        Task {
            let diskService = DiskService()
            try? await diskService.ejectDisk(drive)
        }
    }

    // Open the USB volume in Finder
    private func openInFinder() {
        let volumePath = "/Volumes/\(wizardState.volumeName)"
        NSWorkspace.shared.open(URL(fileURLWithPath: volumePath))
    }
}
