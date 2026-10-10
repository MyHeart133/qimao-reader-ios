import Foundation

/// 最小 ZIP 写入器(STORE 模式,零依赖,用于生成 EPUB)
struct ZipWriter {
    private struct Entry {
        let name: String
        let data: Data
    }

    private var entries: [Entry] = []

    mutating func add(_ name: String, _ data: Data) {
        entries.append(Entry(name: name, data: data))
    }

    mutating func add(_ name: String, text: String) {
        add(name, Data(text.utf8))
    }

    func finalize() -> Data {
        var out = Data()
        var central = Data()

        for e in entries {
            let nameData = Data(e.name.utf8)
            let crc = CRC32.checksum(e.data)
            let size = UInt32(e.data.count)
            let offset = UInt32(out.count)

            // local file header
            out.appendLE32(0x04034b50)
            out.appendLE16(20)          // version needed
            out.appendLE16(0x0800)      // UTF-8 flag
            out.appendLE16(0)           // method: stored
            out.appendLE16(0)           // mod time
            out.appendLE16(0x21)        // mod date (1980-01-01)
            out.appendLE32(crc)
            out.appendLE32(size)
            out.appendLE32(size)
            out.appendLE16(UInt16(nameData.count))
            out.appendLE16(0)           // extra len
            out.append(nameData)
            out.append(e.data)

            // central directory entry
            central.appendLE32(0x02014b50)
            central.appendLE16(20)      // made by
            central.appendLE16(20)      // needed
            central.appendLE16(0x0800)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0x21)
            central.appendLE32(crc)
            central.appendLE32(size)
            central.appendLE32(size)
            central.appendLE16(UInt16(nameData.count))
            central.appendLE16(0)       // extra
            central.appendLE16(0)       // comment
            central.appendLE16(0)       // disk
            central.appendLE16(0)       // int attrs
            central.appendLE32(0)       // ext attrs
            central.appendLE32(offset)
            central.append(nameData)
        }

        let cdOffset = UInt32(out.count)
        out.append(central)
        let cdSize = UInt32(central.count)

        // end of central directory
        out.appendLE32(0x06054b50)
        out.appendLE16(0)
        out.appendLE16(0)
        out.appendLE16(UInt16(entries.count))
        out.appendLE16(UInt16(entries.count))
        out.appendLE32(cdSize)
        out.appendLE32(cdOffset)
        out.appendLE16(0)

        return out
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data {
            c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendLE16(_ v: UInt16) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    mutating func appendLE32(_ v: UInt32) {
        append(contentsOf: [
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF),
        ])
    }
}
