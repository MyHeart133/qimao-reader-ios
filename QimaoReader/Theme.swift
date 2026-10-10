import SwiftUI

/// 七猫风主题:橙红主色 + 阅读器四主题
enum QTheme {
    // 主色(七猫橙红)
    static let primary = Color(red: 1.00, green: 0.36, blue: 0.16)
    static let primaryDark = Color(red: 0.91, green: 0.29, blue: 0.10)
    static let primarySoft = Color(red: 1.00, green: 0.95, blue: 0.92)

    static let bg = Color(red: 0.968, green: 0.968, blue: 0.976)
    static let card = Color.white
    static let textMain = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let textSub = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let separator = Color(red: 0.93, green: 0.93, blue: 0.94)

    // 阅读器主题
    struct ReaderTheme: Identifiable {
        let id: Int
        let name: String
        let bg: Color
        let text: Color
        let panel: Color
        let isDark: Bool
    }

    static let readerThemes: [ReaderTheme] = [
        .init(id: 0, name: "羊皮纸",
              bg: Color(red: 0.965, green: 0.937, blue: 0.874),
              text: Color(red: 0.24, green: 0.21, blue: 0.16),
              panel: Color(red: 0.90, green: 0.87, blue: 0.80),
              isDark: false),
        .init(id: 1, name: "白色",
              bg: Color.white,
              text: Color(red: 0.17, green: 0.17, blue: 0.17),
              panel: Color(red: 0.95, green: 0.95, blue: 0.96),
              isDark: false),
        .init(id: 2, name: "护眼",
              bg: Color(red: 0.847, green: 0.910, blue: 0.812),
              text: Color(red: 0.18, green: 0.25, blue: 0.15),
              panel: Color(red: 0.78, green: 0.86, blue: 0.74),
              isDark: false),
        .init(id: 3, name: "夜间",
              bg: Color(red: 0.086, green: 0.086, blue: 0.098),
              text: Color(red: 0.62, green: 0.64, blue: 0.68),
              panel: Color(red: 0.16, green: 0.16, blue: 0.18),
              isDark: true),
    ]

    static func readerTheme(_ index: Int) -> ReaderTheme {
        readerThemes[max(0, min(index, readerThemes.count - 1))]
    }
}

extension View {
    /// 白色圆角卡片
    func qCard() -> some View {
        self
            .background(QTheme.card)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}
