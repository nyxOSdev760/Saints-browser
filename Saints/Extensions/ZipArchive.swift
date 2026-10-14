import Foundation
import Compression

enum ZipError: LocalizedError {
    case notAnArchive
    case corrupt(String)
    case unsupportedMethod(UInt16)

    var errorDescription: String? {
        switch self {
        case .notAnArchive: return "The file is not a ZIP/XPI/CRX archive."
        case .corrupt(let what): return "The archive is damaged (\(what))."
        case .unsupportedMethod(let m): return "Unsupported compression method \(m)."
        }
    }
}

/// Minimal ZIP reader supporting stored and deflated entries, plus Chrome's CRX2/CRX3 wrappers.
struct ZipArchive {
    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    let data: Data
    private(set) var entries: [Entry] = []

    init(data raw: Data) throws {
        data = try Self.stripCRXHeader(raw)
        entries = try readCentralDirectory()
    }

    private static func stripCRXHeader(_ raw: Data) throws -> Data {
        let bytes = [UInt8](raw.prefix(16))
        guard bytes.count >= 4 else { throw ZipError.notAnArchive }
        if bytes[0] == 0x43, bytes[1] == 0x72, bytes[2] == 0x32, bytes[3] == 0x34 { // "Cr24"
            let version = raw.u32(at: 4)
            var offset: Int
            if version == 3 {
                offset = 12 + Int(raw.u32(at: 8))
            } else {
                offset = 16 + Int(raw.u32(at: 8)) + Int(raw.u32(at: 12))
            }
            guard offset < raw.count else { throw ZipError.corrupt("crx header") }
            offset += raw.startIndex
            return Data(raw[offset...])
        }
        return Data(raw)
    }

    private func readCentralDirectory() throws -> [Entry] {
        // Find End Of Central Directory record (0x06054b50), scanning backwards.
        let minEOCD = 22
        guard data.count >= minEOCD else { throw ZipError.notAnArchive }
        var eocd = -1
        let lowerBound = max(0, data.count - 0xFFFF - minEOCD)
        var i = data.count - minEOCD
        while i >= lowerBound {
            if data.u32(at: i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAnArchive }

        let count = Int(data.u16(at: eocd + 10))
        var offset = Int(data.u32(at: eocd + 16))
        var result: [Entry] = []
        result.reserveCapacity(count)

        for _ in 0..<count {
            guard offset + 46 <= data.count, data.u32(at: offset) == 0x02014b50 else {
                throw ZipError.corrupt("central directory")
            }
            let method = data.u16(at: offset + 10)
            let compSize = Int(data.u32(at: offset + 20))
            let uncompSize = Int(data.u32(at: offset + 24))
            let nameLen = Int(data.u16(at: offset + 28))
            let extraLen = Int(data.u16(at: offset + 30))
            let commentLen = Int(data.u16(at: offset + 32))
            let localOffset = Int(data.u32(at: offset + 42))
            guard offset + 46 + nameLen <= data.count else { throw ZipError.corrupt("file name") }
            let nameData = data.subdata(in: (data.startIndex + offset + 46)..<(data.startIndex + offset + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            result.append(Entry(path: name, method: method, compressedSize: compSize,
                                uncompressedSize: uncompSize, localHeaderOffset: localOffset))
            offset += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    func extract(_ entry: Entry) throws -> Data {
        let h = entry.localHeaderOffset
        guard h + 30 <= data.count, data.u32(at: h) == 0x04034b50 else { throw ZipError.corrupt("local header") }
        let nameLen = Int(data.u16(at: h + 26))
        let extraLen = Int(data.u16(at: h + 28))
        let start = h + 30 + nameLen + extraLen
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("entry bounds") }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var capacity = max(expectedSize, 64)
        for _ in 0..<4 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                    guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                          let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(d, capacity, s, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 && written < capacity || written == expectedSize {
                output.count = written
                return output
            }
            capacity *= 4
        }
        throw ZipError.corrupt("deflate stream")
    }

    /// Extracts every file into `directory`, refusing paths that escape it.
    func extractAll(to directory: URL) throws {
        let fm = FileManager.default
        let root = directory.standardizedFileURL.path
        for entry in entries where !entry.isDirectory {
            let clean = entry.path.replacingOccurrences(of: "\\", with: "/")
            let target = directory.appendingPathComponent(clean).standardizedFileURL
            guard target.path.hasPrefix(root + "/") else { continue }
            if clean.hasPrefix("__MACOSX/") || clean.hasPrefix("_metadata/") { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try extract(entry).write(to: target)
        }
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    func u32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | (UInt32(self[i + 1]) << 8) | (UInt32(self[i + 2]) << 16) | (UInt32(self[i + 3]) << 24)
    }
}
