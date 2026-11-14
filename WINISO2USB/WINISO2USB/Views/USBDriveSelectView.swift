import SwiftUI

// Step 2: Select a USB drive from the list of connected removable drives
struct USBDriveSelectView: View {
    @EnvironmentObject var wizardState: WizardState
    @EnvironmentObject var diskService: DiskService

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Choose the USB drive")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Everything on the drive you choose will be erased.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)

            if diskService.availableDrives.isEmpty {
                emptyState
            } else {
                driveList
            }

            HStack {
                Spacer()
                Button {
                    diskService.refreshDrives()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .onAppear {
            diskService.refreshDrives()
        }
    }

    // Shown when no USB drives are detected
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 46))
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.pulse)

            Text("No USB drives found")
                .font(.headline)

            Text("Plug one in. It will appear here by itself.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 20, padding: 36)
    }

    // List of detected USB drives
    private var driveList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(diskService.availableDrives) { drive in
                    driveRow(drive)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
    }

    // Single drive row, selectable
    private func driveRow(_ drive: USBDrive) -> some View {
        let isSelected = wizardState.selectedDrive?.id == drive.id

        return Button {
            wizardState.selectedDrive = drive
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: "externaldrive.fill")
                    .saturation(isSelected ? 1 : 0.15)

                VStack(alignment: .leading, spacing: 5) {
                    Text(drive.name.isEmpty ? "Untitled" : drive.name)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Pill(text: drive.busProtocol.isEmpty ? "External" : drive.busProtocol)
                        Pill(text: "/dev/\(drive.id)", mono: true)
                    }
                }

                Spacer()

                Text(drive.formattedSize)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Theme.blue.opacity(0.35) : .black.opacity(0.1), radius: isSelected ? 14 : 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}
