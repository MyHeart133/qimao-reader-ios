import SwiftUI
import UIKit

/// NovelFlow 设计系统:安静、低饱和、以阅读为中心。
enum NFTheme {
    // 品牌主色:柔和松绿(与暖纸背景搭出安静气质)
    static let accent = Color(red: 0.251, green: 0.412, blue: 0.361)      // #40695C
    static let accentSoft = Color(red: 0.898, green: 0.933, blue: 0.914)  // 浅绿雾

    static let background = Color(red: 0.972, green: 0.964, blue: 0.945)  // 米白 #F8F6F1
    static let surface = Color.white
    static let textPrimary = Color(red: 0.153, green: 0.153, blue: 0.169)
    static let textSecondary = Color(red: 0.52, green: 0.52, blue: 0.55)
    static let separator = Color(red: 0.92, green: 0.91, blue: 0.89)

    static let cornerRadius: CGFloat = 12
}

/// 阅读主题(渲染层需要 UIColor,这里双向提供)
struct ReaderTheme: Identifiable, Equatable {
    let id: Int
    let name: String
    let backgroundHex: UInt32
    let textHex: UInt32

    var background: Color { Color(nfHex: backgroundHex) }
    var text: Color { Color(nfHex: textHex) }
    var uiBackground: UIColor { UIColor(nfHex: backgroundHex) }
    var uiText: UIColor { UIColor(nfHex: textHex) }

    static let all: [ReaderTheme] = [
        ReaderTheme(id: 0, name: "纸白", backgroundHex: 0xFBF7EF, textHex: 0x2A2723),
        ReaderTheme(id: 1, name: "暖黄", backgroundHex: 0xF6EFDF, textHex: 0x3B342A),
        ReaderTheme(id: 2, name: "护眼绿", backgroundHex: 0xE4EEDD, textHex: 0x2C3627),
        ReaderTheme(id: 3, name: "夜间", backgroundHex: 0x141417, textHex: 0x9FA3A9),
    ]

    static func theme(_ i: Int) -> ReaderTheme {
        all[max(0, min(i, all.count - 1))]
    }
}

extension Color {
    init(nfHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((nfHex >> 16) & 0xFF) / 255.0,
            green: Double((nfHex >> 8) & 0xFF) / 255.0,
            blue: Double(nfHex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(nfHex: UInt32) {
        self.init(
            red: CGFloat((nfHex >> 16) & 0xFF) / 255.0,
            green: CGFloat((nfHex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(nfHex & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
