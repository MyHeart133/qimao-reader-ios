import SwiftUI

/// 阅读偏好存储键
enum ReaderPreferenceKeys {
    static let readingMode = "nf.reader.readingMode"
    static let tapZone = "nf.reader.tapZone"
}

/// 翻页方式:分页 / 连续滚动
enum ReadingMode: String, CaseIterable, Identifiable {
    case paged
    case scroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paged: return "翻页"
        case .scroll: return "滚动"
        }
    }
}

/// 点按分区预设
enum TapZonePreset: String, CaseIterable, Identifiable {
    case standard
    case leftHanded
    case wide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准"
        case .leftHanded: return "左手"
        case .wide: return "宽区"
        }
    }

    /// 两侧点击区占屏宽比例
    var edgeFraction: CGFloat {
        self == .wide ? 0.35 : 0.28
    }

    /// 左右是否互换(左手模式:左侧 = 下一页)
    var swapsSides: Bool {
        self == .leftHanded
    }

    /// 点击分区 -> 动作(zone: 0 = 左, 1 = 中, 2 = 右)
    func command(for zone: Int) -> ReaderTapCommand {
        switch zone {
        case 0:
            return swapsSides ? .nextPage : .previousPage
        case 2:
            return swapsSides ? .previousPage : .nextPage
        default:
            return .toggleMenu
        }
    }
}

/// 点击分区的目标动作
enum ReaderTapCommand: Equatable {
    case previousPage
    case nextPage
    case toggleMenu
}
