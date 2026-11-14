import SwiftUI

// Main container: a soft gradient backdrop, the five stages across the top, the active step in the middle and
// Back/Next at the bottom until the creation step begins.
struct WizardContainerView: View {
    @EnvironmentObject var wizardState: WizardState

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 0) {
                // Stands in for the hidden title bar (the window's buttons sit at its left).
                Text("WINISO2USB")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
                    .padding(.top, 2)

                stageBar
                    .padding(.horizontal, 36)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // The last two steps have their own buttons, and want the room.
                if wizardState.currentStep != .progress && wizardState.currentStep != .completion {
                    navigationBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }
            }
        }
        .alert("Error", isPresented: $wizardState.showAlert) {
            Button("OK") { wizardState.showAlert = false }
        } message: {
            if let error = wizardState.alertError {
                Text(error.localizedDescription)
            }
        }
    }

    // The five stages, joined by a track that fills as they're completed
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

    // A stage's icon in a circle, with its name beneath
    private func stepIndicator(_ step: WizardStep) -> some View {
        let state = stepState(step)

        return VStack(spacing: 7) {
            ZStack {
                if state == .current {
                    Circle()
                        .stroke(Theme.gradient, lineWidth: 2)
                        .frame(width: 46, height: 46)
                        .opacity(0.45)
                }

                Circle()
                    .fill(state == .upcoming ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Theme.gradient))
                    .frame(width: 36, height: 36)
                    .shadow(color: state == .current ? Theme.blue.opacity(0.6) : .clear, radius: 10, y: 3)

                Image(systemName: state == .complete ? "checkmark" : step.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state == .upcoming ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            }
            .frame(width: 46, height: 46)

            Text(step.title)
                .font(.caption)
                .foregroundStyle(state == .current ? .primary : .secondary)
                .fontWeight(state == .current ? .semibold : .regular)
        }
        .frame(width: 84)
        .animation(.spring(duration: 0.4), value: wizardState.currentStep)
    }

    // The track between two stages
    private func stepConnector(before step: WizardStep) -> some View {
        let reached = step.rawValue <= wizardState.currentStep.rawValue

        return Capsule()
            .fill(reached ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.quaternary))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -14)
            .padding(.bottom, 22)
            .animation(.easeInOut(duration: 0.4), value: wizardState.currentStep)
    }

    // Bottom navigation with Back and Next buttons
    private var navigationBar: some View {
        HStack {
            // Back button -- visible on steps 2 and 3
            if wizardState.currentStep.rawValue > 0
                && wizardState.currentStep != .progress
                && wizardState.currentStep != .completion {
                Button {
                    wizardState.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(GhostButtonStyle())
            }

            Spacer()

            // Next button -- visible on steps 1-2. The Review step has no Next: the only way on from there is its own
            // "Erase and Create" button, which stays disabled until ERASE has been typed.
            if wizardState.currentStep != .review
                && wizardState.currentStep != .progress
                && wizardState.currentStep != .completion {
                Button {
                    wizardState.advance()
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(!wizardState.canAdvance)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(height: 36)
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
}

// MARK: - Look and feel, shared by every step

enum Theme {
    static var blue: Color { Color(red: 0.0, green: 0.47, blue: 0.95) }
    static var cyan: Color { Color(red: 0.18, green: 0.80, blue: 0.95) }
    static var violet: Color { Color(red: 0.52, green: 0.36, blue: 0.98) }
    static var gradient: LinearGradient { LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var danger: LinearGradient { LinearGradient(colors: [Color(red: 0.93, green: 0.22, blue: 0.24), Color(red: 0.98, green: 0.48, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var success: LinearGradient { LinearGradient(colors: [Color(red: 0.13, green: 0.72, blue: 0.45), cyan], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var spectrum: AngularGradient { AngularGradient(colors: [blue, cyan, violet, blue], center: .center) }
}

// The window's background: the system colour, lit by three soft colours that drift very slowly.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        let strength = scheme == .dark ? 0.42 : 0.22
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle().fill(Theme.blue.opacity(strength)).frame(width: 520).blur(radius: 130)
                .offset(x: drift ? -300 : -240, y: drift ? -230 : -190)
            Circle().fill(Theme.cyan.opacity(strength * 0.8)).frame(width: 460).blur(radius: 130)
                .offset(x: drift ? 300 : 250, y: drift ? 250 : 200)
            Circle().fill(Theme.violet.opacity(strength * 0.7)).frame(width: 320).blur(radius: 120)
                .offset(x: drift ? 250 : 300, y: drift ? -260 : -220)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !ScreenshotMode.isActive else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// A frosted panel
struct Card: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

extension View {
    func card(radius: CGFloat = 16, padding: CGFloat = 16) -> some View { modifier(Card(radius: radius, padding: padding)) }
}

// An SF Symbol on a gradient tile
struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 44
    var style: LinearGradient = Theme.gradient

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(style)
            .frame(width: size, height: size)
            .overlay(Image(systemName: systemImage).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: Theme.blue.opacity(0.35), radius: 8, y: 3)
    }
}

// A small rounded label, e.g. "USB" or "/dev/disk4"
struct Pill: View {
    let text: String
    var mono = false

    var body: some View {
        Text(text)
            .font(mono ? .system(.caption, design: .monospaced) : .caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

// The main action: a glowing gradient capsule (`danger` for the one that erases)
struct GlowButtonStyle: ButtonStyle {
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        GlowLabel(configuration: configuration, danger: danger)
    }

    private struct GlowLabel: View {
        let configuration: ButtonStyleConfiguration
        let danger: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(danger ? Theme.danger : Theme.gradient, in: Capsule())
                .shadow(color: (danger ? Color.red : Theme.blue).opacity(isEnabled ? 0.45 : 0), radius: 10, y: 4)
                .saturation(isEnabled ? 1 : 0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// A quieter action: frosted capsule
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// A slowly spinning disc: the ISO
struct DiscArt: View {
    var size: CGFloat = 132
    var ready = false
    @State private var turn = 0.0

    var body: some View {
        ZStack {
            Circle().fill(Theme.spectrum).frame(width: size, height: size).blur(radius: size * 0.2).opacity(0.55)
            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0.95), Theme.cyan, Theme.blue, Theme.violet, .white.opacity(0.95)], center: .center))
                .frame(width: size * 0.9, height: size * 0.9)
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1).padding(size * 0.14))
                .rotationEffect(.degrees(turn))
            Circle().fill(.ultraThinMaterial).frame(width: size * 0.34, height: size * 0.34)
            Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: size * 0.12, height: size * 0.12)
            if ready {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white, Theme.success)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .offset(x: size * 0.33, y: size * 0.33)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !ScreenshotMode.isActive else { turn = 35; return }
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { turn = 360 }
        }
    }
}
