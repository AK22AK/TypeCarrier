import SwiftUI

@main
struct TypeCarrierMacApp: App {
    @StateObject private var store = MacCarrierStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            Label("TypeCarrier", systemImage: store.menuBarSystemImage)
        }
        .menuBarExtraStyle(.menu)

        Window("TypeCarrier Debug", id: "debug") {
            DebugWindowView(store: store)
                .frame(minWidth: 520, minHeight: 520)
        }
        .defaultSize(width: 560, height: 600)
    }
}
