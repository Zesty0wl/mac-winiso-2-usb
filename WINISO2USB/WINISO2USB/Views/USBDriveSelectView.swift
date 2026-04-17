import SwiftUI

// Step 2: Select a USB drive from the list of connected removable drives
struct USBDriveSelectView: View {
    @EnvironmentObject var wizardState: WizardState
    @EnvironmentObject var diskService: DiskService

    var body: some View {
        VStack(spacing: 20) {
            Text("Select USB Drive")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose the USB drive to use for the Windows installer. All data on the selected drive will be erased.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

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
            }

            Spacer()
        }
        .padding()
        .onAppear {
            diskService.refreshDrives()
        }
    }

    // Shown when no USB drives are detected
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No USB drives detected")
                .font(.headline)

            Text("Connect a USB drive and click Refresh.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // List of detected USB drives
    private var driveList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(diskService.availableDrives) { drive in
                    driveRow(drive)
                }
            }
        }
    }

    // Single drive row, selectable
    private func driveRow(_ drive: USBDrive) -> some View {
        let isSelected = wizardState.selectedDrive?.id == drive.id

        return Button {
            wizardState.selectedDrive = drive
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.displayName)
                        .font(.headline)
                    Text("\(drive.formattedSize) - \(drive.busProtocol.isEmpty ? "External" : drive.busProtocol)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("/dev/\(drive.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
