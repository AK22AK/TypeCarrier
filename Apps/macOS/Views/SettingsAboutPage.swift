import SwiftUI

struct SettingsAboutPage: View {
    var body: some View {
        MacManagementForm {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TypeCarrier").font(.system(size: 17, weight: .semibold))
                        Text("手机输入，Mac 接收。").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                LabeledContent("版本", value: appVersionText)
            }
            Section("更多平台") {
                LabeledContent("iOS") { Text("通过 TestFlight 邀请测试").foregroundStyle(.secondary) }
                if let url = URL(string: "https://github.com/AK22AK/TypeCarrier/releases") {
                    Link(destination: url) {
                        LabeledContent("Android / macOS") { Label("GitHub Releases", systemImage: "arrow.up.right") }
                    }
                }
            }
            Section {
                if let url = URL(string: "https://github.com/AK22AK/TypeCarrier") {
                    Link("项目源码", destination: url)
                }
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
