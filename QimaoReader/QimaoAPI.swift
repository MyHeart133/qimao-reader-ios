import Foundation
import CryptoKit
import CommonCrypto

enum QimaoError: LocalizedError {
    case api(String)
    case network(String)
    case decrypt

    var errorDescription: String? {
        switch self {
        case .api(let m): return "接口错误：\(m)"
        case .network(let m): return "网络错误：\(m)"
        case .decrypt: return "内容解密失败"
        }
    }
}

// MARK: - 模型

struct QBook: Identifiable, Hashable {
    var id: String
    var title: String
    var author: String
    var intro: String
    var cover: String
    var subTitle: String
    var isOver: Bool
    var latestChapter: String
    var tags: String

    static func fromSearch(_ d: [String: Any]) -> QBook {
        let t = QimaoAPI.cleanHTML(QimaoAPI.str(d["title"]))
        let ot = QimaoAPI.cleanHTML(QimaoAPI.str(d["original_title"]))
        return QBook(
            id: QimaoAPI.str(d["id"]),
            title: t.isEmpty ? ot : t,
            author: QimaoAPI.cleanHTML(QimaoAPI.str(d["author"])),
            intro: QimaoAPI.cleanHTML(QimaoAPI.str(d["intro"])),
            cover: QimaoAPI.str(d["image_link"]),
            subTitle: QimaoAPI.cleanHTML(QimaoAPI.str(d["sub_title"])),
            isOver: QimaoAPI.str(d["is_over"]) == "1",
            latestChapter: "",
            tags: QimaoAPI.cleanHTML(QimaoAPI.str(d["ptags"]))
        )
    }
}

struct QChapter: Identifiable, Hashable {
    var id: String
    var index: Int
    var title: String
    var words: String
}

// MARK: - API

final class QimaoAPI {
    static let shared = QimaoAPI()
    private init() {}

    private let signKey = "d3dGiJc651gSQ8w1"
    private let appVersion = "73720"

    private let apiSearch = "https://api-bc.wtzw.com/search/v1/words"
    private let apiDetail = "https://api-bc.wtzw.com/api/v1/reader/detail"
    private let apiCatalog = "https://api-ks.wtzw.com/api/v1/chapter/chapter-list"
    private let apiContent = "https://api-ks.wtzw.com/api/v1/chapter/content"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        return URLSession(configuration: cfg)
    }()

    // MARK: 工具

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(Int(d)) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func cleanHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "&amp;", with: "&")
        t = t.replacingOccurrences(of: "&quot;", with: "\"")
        t = t.replacingOccurrences(of: "&#39;", with: "'")
        t = t.replacingOccurrences(of: "&lt;", with: "<")
        t = t.replacingOccurrences(of: "&gt;", with: ">")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func signedParams(_ params: [String: String]) -> [String: String] {
        var out = params
        let raw = params.keys.sorted().map { "\($0)=\(params[$0]!)" }.joined() + signKey
        out["sign"] = md5Hex(raw)
        return out
    }

    private var requestHeaders: [String: String] {
        var h: [String: String] = [
            "AUTHORIZATION": "",
            "app-version": appVersion,
            "application-id": "com.kmxs.reader",
            "channel": "unknown",
            "net-env": "1",
            "platform": "android",
            "qm-params": "",
            "reg": "0",
        ]
        let raw = h.keys.sorted().map { "\($0)=\(h[$0]!)" }.joined() + signKey
        h["sign"] = md5Hex(raw)
        h["User-Agent"] = "okhttp/4.9.3"
        return h
    }

    private func getJSON(_ url: String, _ params: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(string: url)!
        comps.queryItems = signedParams(params).map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        for (k, v) in requestHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, _) = try await session.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw QimaoError.api("响应格式异常")
            }
            if let err = obj["errors"] as? [String: Any] {
                throw QimaoError.api("\(QimaoAPI.str(err["code"])) \(QimaoAPI.str(err["title"]))")
            }
            return (obj["data"] as? [String: Any]) ?? [:]
        } catch let e as QimaoError {
            throw e
        } catch {
            throw QimaoError.network(error.localizedDescription)
        }
    }

    // MARK: 接口

    func search(_ keyword: String, page: Int = 1) async throws -> [QBook] {
        let d = try await getJSON(apiSearch, [
            "extend": "", "tab": "0", "gender": "0", "refresh_state": "8",
            "page": "\(page)", "wd": keyword, "is_short_story_user": "0",
        ])
        let books = d["books"] as? [[String: Any]] ?? []
        return books.map { QBook.fromSearch($0) }
    }

    func detail(_ bookID: String) async throws -> QBook {
        let d = try await getJSON(apiDetail, ["id": bookID])
        return QBook(
            id: QimaoAPI.str(d["id"]),
            title: QimaoAPI.cleanHTML(QimaoAPI.str(d["title"])),
            author: QimaoAPI.cleanHTML(QimaoAPI.str(d["author"])),
            intro: QimaoAPI.cleanHTML(QimaoAPI.str(d["intro"])),
            cover: QimaoAPI.str(d["image_link"]),
            subTitle: "",
            isOver: QimaoAPI.str(d["is_over"]) == "1",
            latestChapter: QimaoAPI.cleanHTML(QimaoAPI.str(d["latest_chapter_title"])),
            tags: QimaoAPI.cleanHTML(QimaoAPI.str(d["label"]))
        )
    }

    func catalog(_ bookID: String) async throws -> [QChapter] {
        let d = try await getJSON(apiCatalog, ["chapter_ver": "0", "id": bookID])
        let list = d["chapter_lists"] as? [[String: Any]] ?? []
        return list.enumerated().map { (i, c) in
            QChapter(id: QimaoAPI.str(c["id"]), index: i + 1,
                     title: QimaoAPI.str(c["title"]), words: QimaoAPI.str(c["words"]))
        }
    }

    func chapterText(_ bookID: String, chapterID: String) async throws -> String {
        let d = try await getJSON(apiContent, ["id": bookID, "chapterId": chapterID])
        guard let b64 = d["content"] as? String, !b64.isEmpty else {
            throw QimaoError.api("该章暂无内容")
        }
        return try decryptContent(b64)
    }

    // MARK: 解密(base64 -> hex(前32为IV) -> AES-128-CBC/PKCS7)

    func decryptContent(_ b64: String) throws -> String {
        guard let raw = Data(base64Encoded: b64) else { throw QimaoError.decrypt }
        let hex = raw.map { String(format: "%02x", $0) }.joined()
        guard hex.count > 32 else { throw QimaoError.decrypt }
        guard let iv = dataFromHex(String(hex.prefix(32))),
              let ct = dataFromHex(String(hex.dropFirst(32))),
              let key = dataFromHex("32343263636238323330643730396531") else {
            throw QimaoError.decrypt
        }
        guard let pt = aesCBCDecrypt(ct, key: key, iv: iv),
              let s = String(data: pt, encoding: .utf8) else {
            throw QimaoError.decrypt
        }
        return s
    }

    private func dataFromHex(_ h: String) -> Data? {
        guard h.count % 2 == 0 else { return nil }
        var d = Data(capacity: h.count / 2)
        var i = h.startIndex
        while i < h.endIndex {
            let j = h.index(i, offsetBy: 2)
            guard let b = UInt8(h[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        return d
    }

    private func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        let da = [UInt8](data)
        let ka = [UInt8](key)
        let iva = [UInt8](iv)
        var out = [UInt8](repeating: 0, count: da.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCDecrypt),
                             CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding),
                             ka, ka.count,
                             iva,
                             da, da.count,
                             &out, out.count,
                             &moved)
        guard status == kCCSuccess, moved > 0 else { return nil }
        return Data(out.prefix(moved))
    }
}
