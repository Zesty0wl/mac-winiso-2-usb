import SwiftUI

// Step 4: Show real-time progress during USB creation.
// Kept compact so the stage bar and nav buttons remain visible.
struct CreationProgressView: View {
    @EnvironmentObject var wizardState: WizardState
    @EnvironmentObject var creationService: USBCreationService

    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Creating Bootable USB")
                .font(.title2)
                .fontWeight(.bold)

            // Current stage indicator
            HStack(spacing: 8) {
                stageIcon
                Text(creationService.progress.stage.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: creationService.progress.overallProgress)
                    .progressViewStyle(.linear)

                HStack {
                    Text(String(format: "%.1f%%", creationService.progress.overallProgress * 100))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Spacer()
                    if !creationService.progress.currentFile.isEmpty {
                        Text(creationService.progress.currentFile)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            // Error message if failed
            if let error = creationService.progress.error {
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            // Operation log fills remaining space
            VStack(alignment: .leading, spacing: 4) {
                Text("Operation Log")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(
                                Array(creationService.progress.logLines.enumerated()),
                                id: \.offset
                            ) { idx, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .id(idx)
                            }
                        }
                        .padding(6)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .onChange(of: creationService.progress.logLines.count) { _, _ in
                        if let last = creationService.progress.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Action buttons
            HStack {
                if creationService.progress.stage != .complete
                    && creationService.progress.stage != .failed {
                    Button("Cancel") {
                        creationService.cancel()
                    }
                }

                Spacer()

                if creationService.progress.stage == .complete {
                    Button("Done") {
                        wizardState.advance()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if creationService.progress.stage == .failed {
                    Button("Start Over") {
                        wizardState.reset()
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            startCreation()
        }
    }

    // Icon for the current stage
    @ViewBuilder
    private var stageIcon: some View {
        if creationService.progress.stage == .failed {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        } else if creationService.progress.stage == .complete {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // Kick off the USB creation pipeline once
    private func startCreation() {
        guard !hasStarted else { return }
        hasStarted = true

        guard let isoPath = wizardState.isoFilePath,
              let drive = wizardState.selectedDrive else {
            wizardState.showError(.diskNotFound)
            return
        }

        Task {
            do {
                try await creationService.createBootableUSB(
                    isoPath: isoPath,
                    drive: drive,
                    volumeName: wizardState.volumeName,
                    splitSizeMB: wizardState.splitSizeMB
                )
                wizardState.creationProgress = creationService.progress
            } catch {
                wizardState.creationProgress = creationService.progress
            }
        }
    }
}
