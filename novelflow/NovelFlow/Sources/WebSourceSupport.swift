import Foundation

/// 网页书源通用工具:HTTP、内嵌 JSON 状态提取、HTML 清理、正则捕获
enum WebSourceSupport {

    /// 移动端浏览器 UA(起点/番茄网页按 UA 分流,移动版页面结构更稳定)
    static let mobileBrowserUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func session(timeout: TimeInterval = 20) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 3
        config.httpAdditionalHeaders = ["Accept-Language": "zh-CN,zh;q=0.9"]
        return URLSession(configuration: config)
    }

    // MARK: - 网络

    static func fetchData(
        _ url: URL,
        session: URLSession,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let e as SourceError {
            throw e
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
    }

    static func fetchHTML(
        _ url: URL,
        session: URLSession,
        headers: [String: String] = [:]
    ) async throws -> String {
        var all = headers
        all["User-Agent"] = all["User-Agent"] ?? mobileBrowserUA
        let data = try await fetchData(url, session: session, headers: all)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func fetchJSON(
        _ url: URL,
        session: URLSession,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        var all = headers
        all["User-Agent"] = all["User-Agent"] ?? mobileBrowserUA
        let data = try await fetchData(url, session: session, headers: all)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.decode("响应不是有效 JSON")
        }
        return obj
    }

    // MARK: - 内嵌 JSON 状态(SSR)

    /// 从 HTML 中提取 `marker` 之后的第一段完整 JSON 对象
    /// (用于解析 `window.__INITIAL_STATE__=` 这类服务端渲染状态)
    static func extractState(
        from html: String,
        marker: String = "__INITIAL_STATE__="
    ) -> [String: Any]? {
        guard let range = html.range(of: marker) else { return nil }
        guard let slice = balancedJSONSlice(in: html, from: range.upperBound) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }

    /// 从 `from` 开始扫描第一个 `{` 到配对的 `}`(跳过字符串内的括号)
    static func balancedJSONSlice(in text: String, from start: String.Index) -> Substring? {
        guard let open = text[start...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return text[open...index]
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - HTML 清理

    /// 去除标签、解码实体,并把块级标签转换为换行;段落逐行输出
    static func plainText(fromHTML html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = EPUBParser.decodeEntities(s)
        let lines = s.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 单行文本清理(标题/作者等):去标签 + 实体 + 压缩空白
    static func cleanInline(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = EPUBParser.decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去除字符串中的所有空白(用于书名比对)
    static func normalizedKey(_ s: String) -> String {
        let stripped = s.replacingOccurrences(
            of: "[\\s·・、,，.。:：!！?？\"'“”‘’《》()()【】\\[\\]-]+",
            with: "",
            options: .regularExpression
        )
        return stripped.lowercased()
    }

    // MARK: - 正则

    static func firstCapture(pattern: String, in text: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func allCaptures(pattern: String, in text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - JSON 取值助手

    static func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
    static func array(_ v: Any?) -> [Any]? { v as? [Any] }

    static func string(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(Int(d)) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    /// "1" / 1 / true 都视为真
    static func flag(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        if let n = v as? NSNumber { return n.intValue != 0 }
        if let s = v as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }
}
