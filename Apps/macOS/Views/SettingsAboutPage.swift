import SwiftUI

struct SettingsAboutPage: View {
    var body: some View {
        MacManagementPageContent {
            VStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("TypeCarrier").font(.system(size: 20, weight: .semibold))
                Text("手机输入，Mac 接收。").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
            MacManagementGroup {
                LabeledContent("版本", value: appVersionText).padding(16)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("更多平台").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                MacManagementGroup {
                    LabeledContent("iOS") { Text("通过 TestFlight 邀请测试").foregroundStyle(.secondary) }.padding(16)
                    Divider().padding(.horizontal, 16)
                    if let url = URL(string: "https://github.com/AK22AK/TypeCarrier/releases") {
                        Link(destination: url) {
                            LabeledContent("Android / macOS") { Label("GitHub Releases", systemImage: "arrow.up.right") }
                        }.buttonStyle(.plain).padding(16)
                    }
                }
            }
            if let url = URL(string: "https://github.com/AK22AK/TypeCarrier") {
                Link("项目源码", destination: url)
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
