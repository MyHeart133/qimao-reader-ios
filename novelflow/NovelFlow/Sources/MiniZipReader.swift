import Compression
import Foundation

/// 最小 ZIP 读取器(只读;支持 STORE 与 DEFLATE;不支持 ZIP64/加密)
///
/// 用于 EPUB 容器解析。恶意或损坏的归档会得到 nil/抛错,不会越界。
struct MiniZipReader {
    enum ZipError: LocalizedError {
        case invalidArchive

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "无效的 ZIP 归档"
            }
        }
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = data
        try parseCentralDirectory()
        if entries.isEmpty {
            throw ZipError.invalidArchive
        }
    }

    var paths: [String] { Array(entries.keys) }

    func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    func read(_ path: String) -> Data? {
        guard let entry = entries[path] else { return nil }
        guard readU32(at: entry.localHeaderOffset) == 0x04034b50 else { return nil }
        guard let nameLen = readU16(at: entry.localHeaderOffset + 26),
              let extraLen = readU16(at: entry.localHeaderOffset + 28) else { return nil }
        let dataStart = entry.localHeaderOffset + 30 + Int(nameLen) + Int(extraLen)
        guard dataStart >= 0, entry.compressedSize >= 0,
              dataStart + entry.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: dataStart..<(dataStart + entry.compressedSize))

        switch entry.method {
        case 0:
            return raw
        case 8:
            return Self.inflateRaw(raw, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    // MARK: - Central Directory

    private mutating func parseCentralDirectory() throws {
        // EOCD 签名从尾部往回找(最多扫 64KB + 22)
        let scanLimit = min(data.count, 65_558)
        var eocdOffset: Int?
        var i = data.count - 22
        let lower = data.count - scanLimit
        while i >= max(0, lower) {
            if readU32(at: i) == 0x06054b50 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdOffset,
              let entryCount = readU16(at: eocd + 10),
              let cdSize = readU32(at: eocd + 12),
              let cdOffset = readU32(at: eocd + 16) else {
            throw ZipError.invalidArchive
        }

        var offset = Int(cdOffset)
        let cdEnd = min(data.count, Int(cdOffset) + Int(cdSize))
        var parsed = 0
        while parsed < Int(entryCount) {
            guard offset + 46 <= data.count, offset < cdEnd else { break }
            guard readU32(at: offset) == 0x02014b50 else { break }
            guard let method = readU16(at: offset + 10),
                  let compSize = readU32(at: offset + 20),
                  let uncompSize = readU32(at: offset + 24),
                  let nameLen = readU16(at: offset + 28),
                  let extraLen = readU16(at: offset + 30),
                  let commentLen = readU16(at: offset + 32),
                  let localOffset = readU32(at: offset + 42) else {
                throw ZipError.invalidArchive
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLen)
            guard nameEnd <= data.count else { throw ZipError.invalidArchive }
            if let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8),
               !name.hasSuffix("/") {
                entries[name] = Entry(
                    method: method,
                    compressedSize: Int(compSize),
                    uncompressedSize: Int(uncompSize),
                    localHeaderOffset: Int(localOffset)
                )
            }
            offset = nameEnd + Int(extraLen) + Int(commentLen)
            parsed += 1
        }
    }

    // MARK: - Deflate

    private static func inflateRaw(_ src: Data, expectedSize: Int) -> Data? {
        guard !src.isEmpty else { return Data() }
        let capacity = max(expectedSize, src.count * 3, 4096)
        var output = Data(count: capacity)
        var written = 0

        src.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) in
            output.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) in
                guard let srcPtr = srcRaw.bindMemory(to: UInt8.self).baseAddress,
                      let dstPtr = dstRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                written = compression_decode_buffer(
                    dstPtr, capacity,
                    srcPtr, src.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - 字节读取(小端)

    private func readU16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        return b0 | (b1 << 8)
    }

    private func readU32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
