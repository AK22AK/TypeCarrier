import SwiftUI
import UIKit

extension View {
    /// 推入时让大标题保持展开。
    ///
    /// iOS 26 上大标题页同时设置了 `navigationSubtitle` 时，系统先按“不含副标题”的高度摆好列表，
    /// 副标题生效后大标题区变高，列表看起来就像往上滚了一截，导航栏于是被判定为收起状态。
    /// 等第一帧再把列表拉回去虽然能展开，但推入动画已经按收起状态开始，顶部会闪一下小标题。
    ///
    /// 这里在页面即将出现时（推入动画开始前）先把列表放到顶部之上一点，副标题生效时导航栏仍判定为展开；
    /// 渲染第一帧前再把列表放回真正的顶部。只在首次出现且列表停在顶部时处理，从子页面返回不动用户的滚动位置。
    func expandsLargeTitleOnPush() -> some View {
        background(LargeTitleExpansion())
    }
}

private struct LargeTitleExpansion: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        /// 需要大于副标题带来的额外高度（约 20pt）。
        private static let overshoot: CGFloat = 100

        private var link: CADisplayLink?
        private weak var scrollView: UIScrollView?
        private var handled = false

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.backgroundColor = .clear }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            guard !handled else { return }
            handled = true
            guard let nav = navigationController ?? parent?.navigationController,
                  let scroll = Self.firstScrollView(in: nav.topViewController?.view) else { return }
            let top = -scroll.adjustedContentInset.top
            guard scroll.contentOffset.y <= top + 0.5 else { return }
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top - Self.overshoot), animated: false)
            scrollView = scroll
            link = CADisplayLink(target: self, selector: #selector(settle))
            link?.add(to: .main, forMode: .common)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            settle()
        }

        @objc private func settle() {
            link?.invalidate()
            link = nil
            guard let scroll = scrollView else { return }
            scrollView = nil
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
