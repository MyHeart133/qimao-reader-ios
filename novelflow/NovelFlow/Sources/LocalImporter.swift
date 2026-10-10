import CoreFoundation
import Foundation

/// 本地导入结果(统一内部文本:章节标题行 + 正文,交给 ChapterParser 统一管线)
struct ImportedBook: Equatable {
    var id: String
    var title: String
    var author: String
    var text: String
    var format: String
    var originalFileName: String
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case emptyBook
    case decodeFailed
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "暂不支持 .\(ext) 格式(当前支持 TXT / EPUB)"
        case .emptyBook:
            return "文件内容为空"
        case .decodeFailed:
            return "无法识别文件编码或解析失败"
        case .tooLarge(let bytes):
            return "文件过大(\(bytes / 1024 / 1024) MB),当前上限 64 MB"
        }
    }
}

/// 本地文件导入器:TXT / EPUB → ImportedBook
///
/// 原则:
/// - 无损规范化(CRLF→LF、去 BOM),不改动其余文本
/// - 编码自动探测(UTF-8 / UTF-16 / GB18030 / Latin-1 兜底),不静默破坏原文
/// - 全流程纯函数,便于单元测试
enum LocalImporter {
    static let maxBytes = 64 * 1024 * 1024

    static func importFile(at url: URL) throws -> ImportedBook {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.decodeFailed
        }
        guard !data.isEmpty else { throw ImportError.emptyBook }
        guard data.count <= maxBytes else { throw ImportError.tooLarge(data.count) }

        let name = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "txt", "text":
            return try importTXT(data: data, name: name)
        case "epub":
            return try importEPUB(data: data, name: name)
        default:
            throw ImportError.unsupportedFormat(url.pathExtension.lowercased())
        }
    }

    // MARK: - TXT

    static func importTXT(data: Data, name: String) throws -> ImportedBook {
        var text = try decodeText(data)
        text = ChapterParser.normalize(text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyBook
        }
        let base = (name as NSString).deletingPathExtension
        return ImportedBook(
            id: UUID().uuidString,
            title: base.isEmpty ? "未命名" : base,
            author: "",
            text: text,
            format: "txt",
            originalFileName: name
        )
    }

    // MARK: - EPUB

    static func importEPUB(data: Data, name: String) throws -> ImportedBook {
        let epub: EPUBBook
        do {
            epub = try EPUBParser.parse(data: data)
        } catch let e as EPUBError {
            throw ImportError.unsupportedFormat(e.localizedDescription)
        } catch {
            throw ImportError.decodeFailed
        }

        var parts: [String] = []
        for chapter in epub.chapters {
            parts.append(chapter.title + "\n\n" + chapter.text)
        }
        let merged = ChapterParser.normalize(parts.joined(separator: "\n\n"))
        guard !merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyBook
        }

        let base = (name as NSString).deletingPathExtension
        let title = epub.title.isEmpty ? (base.isEmpty ? "未命名" : base) : epub.title
        return ImportedBook(
            id: UUID().uuidString,
            title: title,
            author: epub.author,
            text: merged,
            format: "epub",
            originalFileName: name
        )
    }

    // MARK: - 编码探测

    static func decodeText(_ data: Data) throws -> String {
        let bytes = data

        // 1. UTF-8 BOM
        if bytes.count >= 3, bytes.prefix(3) == Data([0xEF, 0xBB, 0xBF]) {
            let rest = bytes.dropFirst(3)
            if let s = String(data: rest, encoding: .utf8) {
                return s
            }
        }
        // 2. UTF-16 BOM(FF FE / FE FF)
        if bytes.count >= 2 {
            let head = bytes.prefix(2)
            if head == Data([0xFF, 0xFE]) || head == Data([0xFE, 0xFF]) {
                if let s = String(data: bytes, encoding: .utf16) {
                    return s
                }
            }
        }
        // 3. 严格 UTF-8
        if let s = String(data: bytes, encoding: .utf8) {
            return s
        }
        // 4. UTF-16 无 BOM 启发:偶数长度且 NUL 分布明显
        if bytes.count >= 4, bytes.count % 2 == 0 {
            let sampleCount = min(bytes.count, 1024)
            var nulCount = 0
            for i in 0..<sampleCount where bytes[bytes.startIndex + i] == 0 {
                nulCount += 1
            }
            if nulCount * 4 > sampleCount {
                if let s = String(data: bytes, encoding: .utf16LittleEndian) {
                    return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
                }
            }
        }
        // 5. GB18030(覆盖 GBK / GB2312,中文文本主力)
        let gbRaw = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let s = String(data: bytes, encoding: String.Encoding(rawValue: gbRaw)) {
            return s
        }
        // 6. UTF-16 双端序兜底
        if let s = String(data: bytes, encoding: .utf16LittleEndian) {
            return s
        }
        if let s = String(data: bytes, encoding: .utf16BigEndian) {
            return s
        }
        // 7. Latin-1 终极兜底(任何字节流可读,不崩)
        if let s = String(data: bytes, encoding: .isoLatin1) {
            return s
        }
        throw ImportError.decodeFailed
    }
}
