import CoreText
import UIKit

/// 一页:在源文本中的 UTF-16 范围
struct PageSlice: Equatable, Codable {
    var location: Int
    var length: Int
    var range: NSRange { NSRange(location: location, length: length) }
}

struct PaginationResult: Equatable {
    var pages: [PageSlice]
    var sourceLength: Int
}

/// Core Text 分页引擎
///
/// 设计要点:
/// - 基于 CTFramesetter 真实布局分页,不按固定字符数切页
/// - 页范围的并集必须无缝覆盖全部字符(测试保证)
/// - 页码仅用于展示;跨参数恢复使用 `anchorOffset` 稳定锚点
enum PaginationEngine {

    // MARK: 构建富文本

    static func attributedText(
        _ text: String,
        typography: ReaderTypography,
        textColor: UIColor = .label
    ) -> NSAttributedString {
        let font = typography.resolvedFont
        let para = NSMutableParagraphStyle()
        para.lineSpacing = typography.lineSpacing
        para.paragraphSpacing = typography.paragraphSpacing
        let indent = typography.firstLineIndentChars * font.pointSize
        para.firstLineHeadIndent = indent
        para.headIndent = 0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: para,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: 分页

    /// 分页。pageSize 为「内容区尺寸」(已扣除页边距)。
    static func paginate(
        text: String,
        typography: ReaderTypography,
        pageSize: CGSize
    ) -> PaginationResult {
        guard !text.isEmpty, pageSize.width > 1, pageSize.height > 1 else {
            return PaginationResult(pages: [], sourceLength: (text as NSString).length)
        }
        let attr = attributedText(text, typography: typography)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(
            rect: CGRect(origin: .zero, size: pageSize),
            transform: nil
        )
        var pages: [PageSlice] = []
        var location = 0
        let total = attr.length
        var safety = 0

        while location < total && safety < 100_000 {
            safety += 1
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 {
                // 单个字符都放不下:防死循环,停止推进(极端参数下发生)
                break
            }
            pages.append(PageSlice(location: location, length: visible.length))
            location += visible.length
        }

        return PaginationResult(pages: pages, sourceLength: total)
    }

    // MARK: 锚点映射

    /// 查找包含指定文本偏移的页索引(二分)。
    static func pageIndex(containing offset: Int, in result: PaginationResult) -> Int? {
        guard !result.pages.isEmpty else { return nil }
        let clamped = max(0, min(offset, result.sourceLength - 1))
        var lo = 0
        var hi = result.pages.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let p = result.pages[mid]
            if clamped < p.location {
                hi = mid - 1
            } else if clamped >= p.location + max(p.length, 1) {
                lo = mid + 1
            } else {
                return mid
            }
        }
        return min(max(lo, 0), result.pages.count - 1)
    }

    /// 当前页起始锚点 → 阅读进度百分比
    static func progress(ofPage index: Int, in result: PaginationResult) -> Double {
        guard !result.pages.isEmpty, result.sourceLength > 0 else { return 0 }
        let i = max(0, min(index, result.pages.count - 1))
        return Double(result.pages[i].location) / Double(result.sourceLength)
    }
}
