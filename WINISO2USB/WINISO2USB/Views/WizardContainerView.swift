import SwiftUI

// Main container with a horizontal numbered stage bar across the top and
// content area below. Back/Next buttons at the bottom allow moving between
// steps until the creation step begins.
struct WizardContainerView: View {
    @EnvironmentObject var wizardState: WizardState

    var body: some View {
        VStack(spacing: 0) {
            stageBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .alert("Error", isPresented: $wizardState.showAlert) {
            Button("OK") { wizardState.showAlert = false }
        } message: {
            if let error = wizardState.alertError {
                Text(error.localizedDescription)
            }
        }
    }

    // Horizontal numbered stage indicators connected by lines
    private var stageBar: some View {
        HStack(spacing: 0) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                if step.rawValue > 0 {
                    stepConnector(before: step)
                }
                stepIndicator(step)
            }
        }
    }

    // Numbered circle with step label beneath it
    private func stepIndicator(_ step: WizardStep) -> some View {
        let state = stepState(step)

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state.backgroundColor)
                    .frame(width: 32, height: 32)

                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(step.stepNumber)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(state.numberColor)
                }
            }

            Text(step.title)
                .font(.caption)
                .foregroundColor(state == .current ? .primary : .secondary)
                .fontWeight(state == .current ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity)
    }

    // Line connecting two adjacent step circles
    private func stepConnector(before step: WizardStep) -> some View {
        let previousComplete = step.rawValue <= wizardState.currentStep.rawValue

        return Rectangle()
            .fill(previousComplete ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: 60)
            .padding(.bottom, 20)
    }

    // Bottom navigation with Back and Next buttons
    private var navigationBar: some View {
        HStack {
            // Back button -- visible on steps 2 and 3
            if wizardState.currentStep.rawValue > 0
                && wizardState.currentStep != .progress
                && wizardState.currentStep != .completion {
                Button("Back") {
                    wizardState.goBack()
                }
            }

            Spacer()

            // Next button -- visible on steps 1-2. The Review step has no Next: the only way on from there is its own
            // "Create Bootable USB" button, which stays disabled until ERASE has been typed.
            if wizardState.currentStep != .review
                && wizardState.currentStep != .progress
                && wizardState.currentStep != .completion {
                Button("Next") {
                    wizardState.advance()
                }
                .disabled(!wizardState.canAdvance)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // Content area for the active step
    @ViewBuilder
    private var stepContent: some View {
        switch wizardState.currentStep {
        case .selectISO:
            ISODropView()
        case .selectUSB:
            USBDriveSelectView()
        case .review:
            ReviewView()
        case .progress:
            CreationProgressView()
        case .completion:
            CompletionView()
        }
    }

    // Determine visual state of a step indicator
    private func stepState(_ step: WizardStep) -> StepState {
        if step.rawValue < wizardState.currentStep.rawValue { return .complete }
        if step == wizardState.currentStep { return .current }
        return .upcoming
    }
}

// Visual states for a step indicator
private enum StepState {
    case complete, current, upcoming

    var backgroundColor: Color {
        switch self {
        case .complete: return .accentColor
        case .current: return .accentColor
        case .upcoming: return Color.secondary.opacity(0.2)
        }
    }

    var numberColor: Color {
        switch self {
        case .complete, .current: return .white
        case .upcoming: return .secondary
        }
    }
}
