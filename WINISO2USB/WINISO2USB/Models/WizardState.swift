import Foundation

// Represents each step in the USB creation wizard
enum WizardStep: Int, CaseIterable, Sendable {
    case selectISO = 0
    case selectUSB = 1
    case review = 2
    case progress = 3
    case completion = 4

    var title: String {
        switch self {
        case .selectISO: return "Select ISO"
        case .selectUSB: return "Select USB"
        case .review: return "Review"
        case .progress: return "Creating"
        case .completion: return "Complete"
        }
    }

    // Step number shown in the horizontal stage bar (1-based)
    var stepNumber: Int { rawValue + 1 }

    var systemImage: String {
        switch self {
        case .selectISO: return "opticaldisc"
        case .selectUSB: return "externaldrive"
        case .review: return "checklist"
        case .progress: return "gearshape.2"
        case .completion: return "checkmark.seal"
        }
    }
}

// Errors surfaced throughout the app
enum WINISO2USBError: LocalizedError, Sendable {
    case isoNotFound(String)
    case isoInvalidSignature
    case isoMountFailed(String)
    case isoNoInstallImage
    case diskNotFound
    case diskNotRemovable(String)
    case diskIsBoot
    case diskEraseFailed(String)
    case copyFailed(String)
    case wimSplitFailed(String)
    case wimlibNotFound
    case processError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .isoNotFound(let path):
            return "ISO file not found: \(path)"
        case .isoInvalidSignature:
            return "File does not appear to be a valid ISO image (missing ISO 9660 signature)."
        case .isoMountFailed(let reason):
            return "Failed to mount ISO: \(reason)"
        case .isoNoInstallImage:
            return "ISO does not contain install.wim or install.esd in the sources directory."
        case .diskNotFound:
            return "No USB drive selected."
        case .diskNotRemovable(let disk):
            return "Disk \(disk) does not appear to be a removable USB drive."
        case .diskIsBoot:
            return "The selected disk is the boot disk. Operation refused for safety."
        case .diskEraseFailed(let reason):
            return "Failed to erase disk: \(reason)"
        case .copyFailed(let reason):
            return "Failed to copy files: \(reason)"
        case .wimSplitFailed(let reason):
            return "Failed to split install.wim: \(reason)"
        case .wimlibNotFound:
            return "wimlib-imagex not found. Install wimlib (brew install wimlib) or place wimlib-imagex in the app bundle."
        case .processError(let msg):
            return msg
        case .cancelled:
            return "Operation cancelled by user."
        }
    }
}

// Tracks progress of the USB creation pipeline
struct CreationProgress: Sendable {
    enum Stage: String, Sendable {
        case preparing = "Preparing..."
        case unmounting = "Unmounting disk..."
        case erasing = "Erasing and formatting disk..."
        case mountingISO = "Mounting ISO..."
        case copying = "Copying files..."
        case splitting = "Splitting install.wim..."
        case syncing = "Flushing writes..."
        case ejecting = "Ejecting disk..."
        case complete = "Complete"
        case failed = "Failed"
    }

    var stage: Stage = .preparing
    var overallProgress: Double = 0.0
    var currentFile: String = ""
    var logLines: [String] = []
    var error: WINISO2USBError?
}

// Central state for the wizard flow
@MainActor
final class WizardState: ObservableObject {
    @Published var currentStep: WizardStep = .selectISO
    @Published var isoMetadata: ISOMetadata?
    @Published var isoFilePath: URL?
    @Published var selectedDrive: USBDrive?
    @Published var volumeName: String = "WINDOWSUSB"
    @Published var splitSizeMB: Int = 3800
    @Published var creationProgress = CreationProgress()
    @Published var alertError: WINISO2USBError?
    @Published var showAlert: Bool = false

    // Whether the current step has enough data to proceed
    var canAdvance: Bool {
        switch currentStep {
        case .selectISO:
            return isoFilePath != nil && isoMetadata != nil
        case .selectUSB:
            return selectedDrive != nil
        case .review, .progress, .completion:
            // Review is left by its own confirmed "Create Bootable USB" button, never by Next.
            return false
        }
    }

    // Move to the next wizard step
    func advance() {
        guard let next = WizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    // Move to the previous wizard step
    func goBack() {
        guard let prev = WizardStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // Present an error alert to the user
    func showError(_ error: WINISO2USBError) {
        alertError = error
        showAlert = true
    }

    // Reset all state for a fresh session
    func reset() {
        currentStep = .selectISO
        isoMetadata = nil
        isoFilePath = nil
        selectedDrive = nil
        volumeName = "WINDOWSUSB"
        splitSizeMB = 3800
        creationProgress = CreationProgress()
        alertError = nil
        showAlert = false
    }
}
