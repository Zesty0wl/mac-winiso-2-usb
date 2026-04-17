import SwiftUI

@main
struct WINISO2USBApp: App {
    @StateObject private var wizardState = WizardState()
    @StateObject private var diskService = DiskService()
    @StateObject private var creationService: USBCreationService

    init() {
        let ds = DiskService()
        _diskService = StateObject(wrappedValue: ds)
        _creationService = StateObject(wrappedValue: USBCreationService(diskService: ds))
    }

    var body: some Scene {
        WindowGroup {
            WizardContainerView()
                .environmentObject(wizardState)
                .environmentObject(diskService)
                .environmentObject(creationService)
                .frame(minWidth: 750, minHeight: 550)
        }
        .windowResizability(.contentMinSize)
    }
}
