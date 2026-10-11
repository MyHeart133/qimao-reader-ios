import Foundation

/// 链接 / ID 识别:把用户粘贴的分享链接解析为对应书源的书籍标识
enum WebLinkResolver {
    enum Resolved: Equatable {
        case fanqieBook(String)
        case fanqieChapter(String)
        case qidianBook(String)
    }

    static func resolve(_ input: String) -> Resolved? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.contains("fanqienovel.com") {
            if let id = WebSourceSupport.firstCapture(pattern: "/page/(\\d{10,25})", in: s) {
                return .fanqieBook(id)
            }
            if let id = WebSourceSupport.firstCapture(pattern: "/reader/(\\d{10,25})", in: s) {
                return .fanqieChapter(id)
            }
            return nil
        }

        if s.contains("qidian.com") {
            if let id = WebSourceSupport.firstCapture(pattern: "/book/(\\d{5,12})", in: s) {
                return .qidianBook(id)
            }
            if let id = WebSourceSupport.firstCapture(pattern: "/chapter/(\\d{5,12})/", in: s) {
                return .qidianBook(id)
            }
            return nil
        }

        // 裸 ID:番茄为 19 位上下,起点为 7~10 位
        if WebSourceSupport.matches("^\\d{15,25}$", in: s) {
            return .fanqieBook(s)
        }
        if WebSourceSupport.matches("^\\d{5,12}$", in: s) {
            return .qidianBook(s)
        }
        return nil
    }
}
