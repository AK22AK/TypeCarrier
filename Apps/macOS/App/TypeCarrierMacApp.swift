import SwiftUI

@main
struct TypeCarrierMacApp: App {
    @StateObject private var coordinator = MacAppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            Label("TypeCarrier", systemImage: coordinator.store.menuBarSystemImage)
        }
        .menuBarExtraStyle(.menu)
    }
}
