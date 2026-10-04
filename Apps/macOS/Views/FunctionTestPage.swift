import AppKit
import SwiftUI
import TypeCarrierCore

struct FunctionTestPage: View {
    @ObservedObject var store: MacCarrierStore
    @State private var testText = ""
    @State private var hasPressedReturn = false
    @State private var focusRequest = 0
    @State private var isRunningPasteSelfTest = false
    @State private var pasteSelfTestResult: PasteInjectionResult?
    @State private var lastPasteSelfTestText: String?


    private var didPassPasteSelfTest: Bool {
        guard let lastPasteSelfTestText else {
            return false
        }
        return testText.contains(lastPasteSelfTestText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("点击输入框后，从手机发送一段文本。")
                    .foregroundStyle(.secondary)
                FunctionTestInputView(text: $testText, focusRequest: focusRequest) {
                    hasPressedReturn = true
                }
                .frame(minHeight: 280)
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }
                HStack {
                    Label(hasPressedReturn ? "回车已按下" : "尚未收到回车", systemImage: "return")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("重置", action: reset)
                }
                Divider()
                HStack {
                    Text("检查本机粘贴")
                    Spacer()
                    Button("测试粘贴", action: runPasteSelfTest)
                        .disabled(isRunningPasteSelfTest)
                }
                if isRunningPasteSelfTest {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在把测试输入框设为焦点并发送 Command-V")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let pasteSelfTestResult {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(didPassPasteSelfTest ? "粘贴测试通过" : pasteSelfTestResult.status)
                            Text(pasteSelfTestResult.fullDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    } icon: {
                        Image(systemName: didPassPasteSelfTest ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(didPassPasteSelfTest ? .green : .orange)
                    }
                }

                DisclosureGroup("测试说明") {
                    Text("普通发送应把文本粘贴到输入框；发送后回车应同时更新回车状态。本机测试会主动聚焦此输入框，使用与接收端相同的辅助功能粘贴路径。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 544, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func reset() {
        testText = ""
        hasPressedReturn = false
        pasteSelfTestResult = nil
        lastPasteSelfTestText = nil
        isRunningPasteSelfTest = false
    }

    private func runPasteSelfTest() {
        testText = ""
        hasPressedReturn = false
        pasteSelfTestResult = nil
        isRunningPasteSelfTest = true

        let testText = "TypeCarrier paste test \(Int(Date().timeIntervalSince1970))"
        lastPasteSelfTestText = testText
        focusRequest += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            store.enqueuePaste(text: testText) { result in
                pasteSelfTestResult = result
                isRunningPasteSelfTest = false
            }
        }
    }
}

private struct FunctionTestInputView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = ReturnObservingTextView()
        textView.delegate = context.coordinator
        textView.onReturn = onReturn
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReturnObservingTextView else {
            return
        }

        textView.onReturn = onReturn
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.focusIfNeeded(
            request: focusRequest,
            textView: textView
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private var lastHandledFocusRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }

        func focusIfNeeded(request: Int, textView: NSTextView) {
            guard request != lastHandledFocusRequest else {
                return
            }

            lastHandledFocusRequest = request
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class ReturnObservingTextView: NSTextView {
        var onReturn: (() -> Void)?

        override func insertNewline(_ sender: Any?) {
            onReturn?()
            super.insertNewline(sender)
        }
    }
}

