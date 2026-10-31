import SwiftUI
import UIKit

extension View {
    /// 推入时让大标题保持展开。
    ///
    /// iOS 26 上大标题页同时设置了 `navigationSubtitle` 时，推入后导航栏会按收起状态布局
    /// （只剩小标题，列表的顶部 inset 也只算了小标题），要手动下拉一次才会展开。
    /// 这里在推入动画渲染第一帧前，把滚动视图拉过顶部再放回顶部，
    /// 让导航栏按“大标题 + 副标题”重新布局。只在首次出现时做，从子页面返回不动用户的滚动位置。
    func expandsLargeTitleOnPush() -> some View {
        background(LargeTitleExpansion())
    }
}

private struct LargeTitleExpansion: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var link: CADisplayLink?
        private var handled = false

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.backgroundColor = .clear }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            guard !handled else { return }
            // viewIsAppearing 里改偏移会被随后的转场布局覆盖，放到下一帧渲染前处理。
            link?.invalidate()
            link = CADisplayLink(target: self, selector: #selector(expand))
            link?.add(to: .main, forMode: .common)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            link?.invalidate()
            link = nil
        }

        @objc private func expand() {
            link?.invalidate()
            link = nil
            guard let nav = navigationController ?? parent?.navigationController,
                  let scroll = Self.firstScrollView(in: nav.topViewController?.view) else { return }
            handled = true
            let top = -scroll.adjustedContentInset.top
            guard scroll.contentOffset.y <= top + 0.5 else { return }
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top - 200), animated: false)
            nav.view.layoutIfNeeded()
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false)
        }

        private static func firstScrollView(in view: UIView?) -> UIScrollView? {
            guard let view else { return nil }
            if let scroll = view as? UIScrollView { return scroll }
            for child in view.subviews { if let found = firstScrollView(in: child) { return found } }
            return nil
        }
    }
}
