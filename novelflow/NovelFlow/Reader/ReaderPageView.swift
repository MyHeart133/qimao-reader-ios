import SwiftUI
import UIKit
import CoreText

/// 基于 Core Text 的页面渲染视图(绘制指定页范围,与分页结果严格一致)
final class CoreTextPageUIView: UIView {
    var attributedText: NSAttributedString? {
        didSet { setNeedsDisplay() }
    }
    var pageRange: NSRange = NSRange(location: 0, length: 0) {
        didSet { setNeedsDisplay() }
    }
    /// 内容内边距(与分页时扣除的页边距保持一致)
    var contentInsets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let attr = attributedText,
              pageRange.length > 0,
              attr.length > 0 else { return }

        // 翻转坐标系,让 Core Text 以左下原点正常绘制
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        // 翻转后:y=0 是视觉底部
        let contentRect = CGRect(
            x: contentInsets.left,
            y: contentInsets.bottom,
            width: max(1, bounds.width - contentInsets.left - contentInsets.right),
            height: max(1, bounds.height - contentInsets.top - contentInsets.bottom)
        )
        let path = CGPath(rect: contentRect, transform: nil)

        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let safeLocation = min(pageRange.location, attr.length)
        let safeLength = min(pageRange.length, attr.length - safeLocation)
        guard safeLength > 0 else { return }
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: safeLocation, length: safeLength),
            path,
            nil
        )
        CTFrameDraw(frame, ctx)
    }
}

/// SwiftUI 包装
struct ReaderPageView: UIViewRepresentable {
    var attributed: NSAttributedString
    var pageRange: NSRange
    var contentInsets: UIEdgeInsets
    var backgroundColor: UIColor

    func makeUIView(context: Context) -> CoreTextPageUIView {
        let v = CoreTextPageUIView()
        v.backgroundColor = backgroundColor
        v.isOpaque = true
        return v
    }

    func updateUIView(_ uiView: CoreTextPageUIView, context: Context) {
        uiView.backgroundColor = backgroundColor
        uiView.attributedText = attributed
        uiView.contentInsets = contentInsets
        uiView.pageRange = pageRange
    }
}
