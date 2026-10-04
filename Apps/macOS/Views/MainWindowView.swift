import AppKit
import SwiftUI
import TypeCarrierCore

struct MainWindowView: View {
    @ObservedObject var coordinator: MacAppCoordinator
    @ObservedObject private var store: MacCarrierStore
    @State private var selectedRecordID: UUID?

    init(coordinator: MacAppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            content
                .navigationTitle(activePage.title)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 860, idealWidth: 1000, minHeight: 600, idealHeight: 700)
        .font(.system(size: 13))
        .onAppear {
            store.refreshAccessibilityStatus()
            ensureSelectedRecord()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshAccessibilityStatus()
        }
        .onChange(of: store.records) { _, _ in ensureSelectedRecord() }
    }

    private var activePage: MacManagementPage { coordinator.selectedPage ?? .received }
    private var selectedRecord: CarrierRecord? { store.receivedHistory.first { $0.id == selectedRecordID } }

    private var sidebar: some View {
        List(selection: Binding(
            get: { (coordinator.selectedPage ?? .received).sidebarPage as MacManagementPage? },
            set: { coordinator.selectedPage = $0 }
        )) {
            Section {
                sidebarRow(.received)
                    .badge(store.receivedHistory.count)
                    .tag(MacManagementPage.received)
                sidebarRow(.connections)
            }
            Section("设置") {
                sidebarRow(.receiving)
                sidebarRow(.diagnostics)
                sidebarRow(.about)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 4) {
            Label { Text("TypeCarrier") } icon: { Image(systemName: "waveform").font(.system(size: 14)) }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        }
    }

    private func sidebarRow(_ page: MacManagementPage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: page.symbol)
                .font(.system(size: 16))
                .frame(width: 20)
            Text(page.title).font(.system(size: 13, weight: .regular))
            Spacer(minLength: 0)
            if page == .connections, store.receiverStatusSummary.overallHealth != .ok {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else if page == .diagnostics, !store.accessibilityTrusted {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
        .tag(page)
        .simultaneousGesture(TapGesture().onEnded { coordinator.selectedPage = page })
    }

    @ViewBuilder private var content: some View {
        switch activePage {
        case .received:
            HSplitView {
                ReceivedRecordsListPane(records: store.receivedHistory, selectedRecordID: $selectedRecordID, store: store)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                    .frame(maxHeight: .infinity)
                if let selectedRecord {
                    ReceivedRecordDetail(record: selectedRecord, store: store,
                                         showsSourceIdentity: hasDuplicateSourceName(selectedRecord))
                        .id(selectedRecord.id)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("暂无接收文本", systemImage: "tray", description: Text("从手机发送后，文本会保存在这里。"))
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .connections:
            ReceiverStatusPage(store: store) { coordinator.selectedPage = .diagnostics }
        case .receiving:
            SettingsReceivingPage(store: store)
        case .diagnostics:
            SettingsDiagnosticsPage(store: store) { coordinator.selectedPage = .functionTest }
        case .functionTest:
            FunctionTestPage(store: store)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { coordinator.selectedPage = .diagnostics } label: { Label("诊断与测试", systemImage: "chevron.left") }
                    }
                }
        case .about:
            SettingsAboutPage()
        }
    }

    private func hasDuplicateSourceName(_ record: CarrierRecord) -> Bool {
        let identities = store.receivedHistory.filter { $0.sourceDeviceName == record.sourceDeviceName }.compactMap(\.sourceDeviceID)
        return Set(identities).count > 1
    }

    private func ensureSelectedRecord() {
        if store.receivedHistory.isEmpty { selectedRecordID = nil }
        else if selectedRecord == nil { selectedRecordID = store.receivedHistory.first?.id }
    }
}

/// A constrained native management page; padding scrolls with the content.
struct MacManagementForm<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


struct MacManagementPageContent<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 552, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct MacManagementGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MacManagementHeader: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .secondary
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MacManagementActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
