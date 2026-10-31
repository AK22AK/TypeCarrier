enum MacManagementPage: String, Hashable, CaseIterable, Identifiable {
    case received, connections, receiving, diagnostics, functionTest, about
    var id: Self { self }
    var sidebarPage: Self { self == .functionTest ? .diagnostics : self }
    var title: String {
        switch self {
        case .received: "接收列表"
        case .connections: "连接管理"
        case .receiving: "接收设置"
        case .diagnostics: "诊断与测试"
        case .functionTest: "功能测试"
        case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .received: "tray.and.arrow.down"
        case .connections: "antenna.radiowaves.left.and.right"
        case .receiving: "slider.horizontal.3"
        case .diagnostics, .functionTest: "stethoscope"
        case .about: "info.circle"
        }
    }
}

