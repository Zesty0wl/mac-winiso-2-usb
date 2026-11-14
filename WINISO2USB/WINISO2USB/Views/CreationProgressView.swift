import SwiftUI

// Step 4: Show real-time progress during USB creation: a ring for the whole job, the stages ticking off beside it,
// and the running log beneath in a terminal-style panel.
struct CreationProgressView: View {
    @EnvironmentObject var wizardState: WizardState
    @EnvironmentObject var creationService: USBCreationService

    @State private var hasStarted = false

    private var progress: CreationProgress { creationService.progress }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 28) {
                ring
                stageList
            }
            .padding(.top, 6)

            // What's being worked on right now
            Text(progress.currentFile.isEmpty ? " " : progress.currentFile)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Error message if failed
            if let error = progress.error {
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            log
                .frame(maxHeight: .infinity)

            // Action buttons
            HStack {
                if progress.stage != .complete && progress.stage != .failed {
                    Button("Cancel") {
                        creationService.cancel()
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                Spacer()

                if progress.stage == .complete {
                    Button {
                        wizardState.advance()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(GlowButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }

                if progress.stage == .failed {
                    Button("Start Over") {
                        wizardState.reset()
                    }
                    .buttonStyle(GlowButtonStyle())
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 14)
        .onAppear {
            startCreation()
        }
    }

    // The whole job as a ring, with the percentage in the middle
    private var ring: some View {
        let failed = progress.stage == .failed
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.005, progress.overallProgress))
                .stroke(
                    failed ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(AngularGradient(colors: [Theme.blue, Theme.cyan, Theme.violet, Theme.blue], center: .center)),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (failed ? Color.red : Theme.cyan).opacity(0.55), radius: 9)
                .animation(.easeInOut(duration: 0.5), value: progress.overallProgress)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((progress.overallProgress * 100).rounded()))")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(failed ? "Failed" : progress.stage == .complete ? "Complete" : "Creating")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .padding(8)
    }

    // The pipeline's stages, in order. Splitting only happens (and is only listed) when install.wim is too big.
    private var stages: [(CreationProgress.Stage, String)] {
        var all: [(CreationProgress.Stage, String)] = [
            (.unmounting, "Unmount the drive"),
            (.erasing, "Erase and format (GPT, FAT32)"),
            (.mountingISO, "Mount the ISO"),
            (.copying, "Copy files"),
        ]
        if wizardState.isoMetadata?.needsSplit ?? false { all.append((.splitting, "Split install.wim")) }
        all += [(.syncing, "Flush writes"), (.ejecting, "Eject")]
        return all
    }

    private var stageList: some View {
        let all = stages
        let current = all.firstIndex { $0.0 == progress.stage }
        let allDone = progress.stage == .complete
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, stage in
                let done = allDone || (current.map { index < $0 } ?? false)
                let active = current == index
                HStack(spacing: 9) {
                    ZStack {
                        if done {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.gradient)
                        } else if active {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 15))
                    .frame(width: 18, height: 18)

                    Text(stage.1)
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? .primary : done ? .secondary : .tertiary)
                }
            }
        }
        .frame(width: 250, alignment: .leading)
        .card(radius: 16, padding: 16)
    }

    // The running log, as a terminal
    private var log: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { c in
                    Circle().fill(c.opacity(0.75)).frame(width: 8, height: 8)
                }
                Text("operation log")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 6)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(progress.logLines.enumerated()), id: \.offset) { idx, line in
                            logLine(line)
                                .id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: progress.logLines.count) { _, _ in
                    if let last = progress.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = progress.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    // One log line: steps in green behind a prompt, their detail (indented) dimmer, failures in red
    private func logLine(_ line: String) -> some View {
        let detail = line.hasPrefix("  ")
        let failed = line.hasPrefix("FAILED")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(detail ? " " : "›")
                .foregroundStyle(Theme.cyan)
            Text(detail ? String(line.dropFirst(2)) : line)
                .foregroundStyle(failed ? Color(red: 1, green: 0.45, blue: 0.42) : detail ? Color.white.opacity(0.5) : Color(red: 0.62, green: 0.93, blue: 0.75))
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    // Kick off the USB creation pipeline once
    private func startCreation() {
        // Screenshot mode only shows this screen: it must never erase or write anything.
        guard !hasStarted, !ScreenshotMode.isActive else { return }
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
