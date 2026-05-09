import SwiftUI

@main
struct TypeCarrierMacApp: App {
    @StateObject private var coordinator = MacAppCoordinator()

    var body: some Scene {
        WindowGroup("TypeCarrier", id: "main") {
            MainWindowView(store: coordinator.store)
        }
        .defaultSize(width: 780, height: 560)
        .defaultLaunchBehavior(.presented)

        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            Label("TypeCarrier", systemImage: coordinator.store.menuBarSystemImage)
        }
        .menuBarExtraStyle(.menu)
    }
}
