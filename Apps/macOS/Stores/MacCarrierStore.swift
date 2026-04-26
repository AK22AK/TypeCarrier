import AppKit
import Combine
import Foundation
import TypeCarrierCore

@MainActor
final class MacCarrierStore: ObservableObject {
    @Published private(set) var lastPayloadText = ""
    @Published private(set) var lastPasteResult = PasteInjectionResult.idle
    @Published private(set) var accessibilityTrusted = false

    let carrierService: MultipeerCarrierService
    private let pasteInjector = PasteInjector()
    private let permissionChecker = AccessibilityPermissionChecker()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        carrierService = MultipeerCarrierService(role: .receiver, displayName: Host.current().localizedName ?? "TypeCarrier Mac")
        carrierService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refreshAccessibilityStatus()
        start()
    }

    var menuBarSystemImage: String {
        carrierService.connectionState.isConnected ? "keyboard.badge.ellipsis" : "keyboard"
    }

    var connectionState: ConnectionState {
        carrierService.connectionState
    }

    var lastPayloadPreview: String {
        guard !lastPayloadText.isEmpty else {
            return "No payload received"
        }

        return String(lastPayloadText.prefix(160))
    }

    func start() {
        carrierService.start { [weak self] envelope, _ in
            self?.handle(envelope)
        }
    }

    func restart() {
        carrierService.stop()
        start()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = permissionChecker.isTrusted(prompt: true)
        permissionChecker.openAccessibilitySettings()
    }

    func pasteTestText() {
        refreshAccessibilityStatus()
        lastPasteResult = pasteInjector.paste(text: "Hello from TypeCarrier")
    }

    private func handle(_ envelope: CarrierEnvelope) {
        guard envelope.kind == .text, let payload = envelope.payload else {
            return
        }

        refreshAccessibilityStatus()
        lastPayloadText = payload.text
        lastPasteResult = pasteInjector.paste(text: payload.text)
    }
}
