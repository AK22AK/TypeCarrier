import SwiftUI

extension View {
    /// Keep the native soft edge local to a scrolling navigation page.
    func softTopScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
