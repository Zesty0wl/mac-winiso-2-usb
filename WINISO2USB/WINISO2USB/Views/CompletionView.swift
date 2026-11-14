import SwiftUI

// Step 5: Success screen with post-creation actions
struct CompletionView: View {
    @EnvironmentObject var wizardState: WizardState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // A tick in rings that spread out behind it
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Theme.success, lineWidth: 1.5)
                        .frame(width: 104 + CGFloat(i) * 44, height: 104 + CGFloat(i) * 44)
                        .opacity(appeared ? 0.34 - Double(i) * 0.1 : 0)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .animation(.spring(duration: 0.7).delay(0.08 * Double(i)), value: appeared)
                }
                Circle()
                    .fill(Theme.success)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.green.opacity(0.5), radius: 22, y: 6)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .animation(.spring(duration: 0.5, bounce: 0.4), value: appeared)
            .frame(height: 200)

            VStack(spacing: 6) {
                Text("Bootable USB ready")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("\(wizardState.volumeName) is ready to boot on any UEFI PC.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    ejectDrive()
                } label: {
                    Label("Eject Drive", systemImage: "eject.fill")
                }
                .buttonStyle(GlowButtonStyle())

                Button {
                    openInFinder()
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(GhostButtonStyle())

                Button {
                    wizardState.reset()
                } label: {
                    Label("Create Another", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding()
        .onAppear {
            appeared = true
        }
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
