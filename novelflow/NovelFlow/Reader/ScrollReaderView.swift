import SwiftUI
import UIKit

/// 滚动阅读控制器:供页面层发起「按屏滚动」
final class ScrollReaderController: ObservableObject {
    weak var textView: UITextView?

    /// 按视口比例滚动;返回是否发生了滚动(false 表示已到边缘)
    @discardableResult
    func scroll(byFraction fraction: CGFloat) -> Bool {
        guard let textView else { return false }
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        if fraction < 0, textView.contentOffset.y <= 1 { return false }
        if fraction > 0, textView.contentOffset.y >= maxY - 1 { return false }
        let target = min(max(0, textView.contentOffset.y + textView.bounds.height * fraction), maxY)
        textView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        return true
    }
}

/// 连续滚动阅读视图
///
/// 与分页模式共享排版参数与「章内字符偏移」锚点;
/// 位置换算通过 TextKit 完成,恢复/上报互为逆运算。
struct ScrollReaderView: UIViewRepresentable {
    var text: String
    var typography: ReaderTypography
    var textColor: UIColor
    var backgroundColor: UIColor
    var startOffset: Int
    /// 内容版本号:变化时强制按 startOffset 重新定位(同章跳转同样生效)
    var token: Int
    var edgeFraction: CGFloat
    var controller: ScrollReaderController
    var onTapZone: (Int) -> Void
    var onPositionChange: (Int) -> Void
    var onReachBottom: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = backgroundColor
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = contentInsets
        textView.delegate = context.coordinator
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        textView.addGestureRecognizer(tap)
        context.coordinator.textView = textView
        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.backgroundColor = backgroundColor
        context.coordinator.applyIfNeeded()
    }

    private var contentInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: typography.verticalMargin,
            left: typography.horizontalMargin,
            bottom: typography.verticalMargin + 72,
            right: typography.horizontalMargin
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScrollReaderView
        weak var textView: UITextView?

        private var lastText: String?
        private var lastToken: Int?
        private var lastTypography: ReaderTypography?
        private var lastTextColor: UIColor?
        private var didFireBottom = false

        init(_ parent: ScrollReaderView) {
            self.parent = parent
        }

        /// 文本 / 排版 / 配色变化时重建内容,并保持位置
        func applyIfNeeded() {
            guard let textView else { return }
            let insets = UIEdgeInsets(
                top: parent.typography.verticalMargin,
                left: parent.typography.horizontalMargin,
                bottom: parent.typography.verticalMargin + 72,
                right: parent.typography.horizontalMargin
            )
            if textView.textContainerInset != insets {
                textView.textContainerInset = insets
            }

            let textChanged = lastText != parent.text
            let tokenChanged = lastToken != parent.token
            let needsRebuild = textChanged
                || tokenChanged
                || lastTypography != parent.typography
                || lastTextColor != parent.textColor
            guard needsRebuild else { return }

            // 换章 / 显式跳转(含同章)-> 用入参锚点;仅排版变化 -> 保持当前滚动位置
            let keepOffset: Int
            if lastText == nil || textChanged || tokenChanged {
                keepOffset = parent.startOffset
            } else {
                keepOffset = currentTopOffset() ?? 0
            }

            lastText = parent.text
            lastToken = parent.token
            lastTypography = parent.typography
            lastTextColor = parent.textColor
            didFireBottom = false

            textView.attributedText = PaginationEngine.attributedText(
                parent.text,
                typography: parent.typography,
                textColor: parent.textColor
            )
            textView.setContentOffset(.zero, animated: false)
            restore(scrollToOffset: keepOffset)
        }

        // MARK: 位置换算(文本容器坐标系)

        private func currentTopOffset() -> Int? {
            guard let textView else { return nil }
            // contentOffset → 文本容器坐标(容器原点相对内容区偏移 textContainerInset)
            let y = max(0, textView.contentOffset.y + 2 - textView.textContainerInset.top)
            let point = CGPoint(x: 2, y: y)
            let index = textView.layoutManager.characterIndex(
                for: point,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            return index == NSNotFound ? nil : index
        }

        private func restore(scrollToOffset offset: Int, attempt: Int = 0) {
            guard let textView else { return }
            let length = ((textView.text ?? "") as NSString).length
            guard length > 0 else { return }
            let clamped = max(0, min(offset, length - 1))
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                // 视图尚未完成布局时,等一次尺寸再定位(最多重试 20 次)
                guard textView.bounds.width > 1, textView.bounds.height > 1 else {
                    guard attempt < 20 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.restore(scrollToOffset: clamped, attempt: attempt + 1)
                    }
                    return
                }
                let layoutManager = textView.layoutManager
                layoutManager.ensureLayout(for: textView.textContainer)
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: clamped, length: 1),
                    actualCharacterRange: nil
                )
                let rect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textView.textContainer
                )
                guard !rect.isNull, !rect.isInfinite, rect.minY.isFinite else { return }
                let maxY = max(0, textView.contentSize.height - textView.bounds.height)
                let target = clamped == 0 ? 0 : rect.minY + textView.textContainerInset.top
                let y = min(max(0, target), maxY)
                textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
        }

        // MARK: 滚动回调

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                reportPosition()
                checkBottom()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportPosition()
            checkBottom()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            reportPosition()
        }

        private func reportPosition() {
            guard let offset = currentTopOffset() else { return }
            parent.onPositionChange(offset)
        }

        private func checkBottom() {
            guard let textView, !didFireBottom else { return }
            let maxY = max(0, textView.contentSize.height - textView.bounds.height)
            guard maxY > 1, textView.contentOffset.y >= maxY - 24 else { return }
            didFireBottom = true
            parent.onReachBottom()
        }

        // MARK: 点击分区

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView else { return }
            let x = gesture.location(in: textView).x
            let width = max(1, textView.bounds.width)
            let zone: Int
            if x < width * parent.edgeFraction {
                zone = 0
            } else if x > width * (1 - parent.edgeFraction) {
                zone = 2
            } else {
                zone = 1
            }
            parent.onTapZone(zone)
        }
    }
}
