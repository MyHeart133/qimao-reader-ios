import UIKit

/// 阅读排版参数(纯值类型,可持久化、可比较)
struct ReaderTypography: Equatable, Codable {
    /// 字体名("system" 表示系统字体)
    var fontName: String = "PingFangSC-Regular"
    var fontSize: CGFloat = 19
    /// 行距(像素增量)
    var lineSpacing: CGFloat = 7
    /// 段间距
    var paragraphSpacing: CGFloat = 10
    /// 首行缩进(字符数)
    var firstLineIndentChars: CGFloat = 2
    /// 左右页边距
    var horizontalMargin: CGFloat = 22
    /// 上下页边距
    var verticalMargin: CGFloat = 24

    /// 解析实际可用字体(缺失时回退,并保持可用)
    var resolvedFont: UIFont {
        Self.resolveFont(name: fontName, size: fontSize)
    }

    static func resolveFont(name: String, size: CGFloat) -> UIFont {
        if name == "system" {
            return UIFont.systemFont(ofSize: size)
        }
        if let f = UIFont(name: name, size: size) {
            return f
        }
        // 回退链:苹方 → 系统
        if let f = UIFont(name: "PingFangSC-Regular", size: size) {
            return f
        }
        return UIFont.systemFont(ofSize: size)
    }

    static let fontChoices: [(display: String, name: String)] = [
        ("苹方", "PingFangSC-Regular"),
        ("宋体", "Songti SC"),
        ("楷体", "Kaiti SC"),
        ("系统", "system"),
    ]

    /// 精调默认预设
    static let defaultPreset = ReaderTypography()

    static let compactPreset: ReaderTypography = {
        var t = ReaderTypography()
        t.fontSize = 17
        t.lineSpacing = 4
        t.paragraphSpacing = 4
        t.horizontalMargin = 18
        t.verticalMargin = 20
        return t
    }()

    static let relaxedPreset: ReaderTypography = {
        var t = ReaderTypography()
        t.fontSize = 21
        t.lineSpacing = 11
        t.paragraphSpacing = 18
        t.horizontalMargin = 26
        t.verticalMargin = 28
        return t
    }()
}
