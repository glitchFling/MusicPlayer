import Compression
import Foundation
import UniformTypeIdentifiers

// MARK: - ZIP Entry

private struct ZIPEntry {
    let fileName: String
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let compressionMethod: UInt16
    let localHeaderOffset: UInt32
    let crc32: UInt32
}

// MARK: - Suitcase Extractor

public enum SuitcaseError: LocalizedError {
    case invalidArchive
    case corruptedEntry(String)
    case extractionFailed(String)
    case noAudioFiles

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: return "That file is not a valid ZIP archive."
        case .corruptedEntry(let name): return "Entry \"\(name)\" in the ZIP is corrupted."
        case .extractionFailed(let msg): return "Could not extract audio: \(msg)"
        case .noAudioFiles: return "No audio files found in the ZIP archive."
        }
    }
}

public struct SuitcaseService {

    /// Audio extensions Suitcase recognises
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "wma", "ogg", "flac", "aac"]

    /// Extract audio files from a ZIP archive and return extracted file URLs.
    public static func extractAudio(from zipURL: URL) throws -> [URL] {
        let data = try Data(contentsOf: zipURL)
        let entries = try parseCentralDirectory(data)
        guard !entries.isEmpty else { throw SuitcaseError.invalidArchive }

        let audioEntries = entries.filter { entry in
            let ext = (entry.fileName as NSString).pathExtension.lowercased()
            return audioExtensions.contains(ext)
        }

        guard !audioEntries.isEmpty else { throw SuitcaseError.noAudioFiles }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Suitcase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var extracted: [URL] = []
        for entry in audioEntries {
            guard let entryData = try? extractEntry(entry, from: data) else { continue }
            let safeName = sanitized(entry.fileName)
            let targetURL = tempDir.appendingPathComponent(safeName)
            try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? entryData.write(to: targetURL, options: .atomic)
            extracted.append(targetURL)
        }
        return extracted
    }

    // MARK: - ZIP Parsing

    /// Parse the end-of-central-directory record to find the central directory offset,
    /// then walk the central directory to build entry metadata.
    private static func parseCentralDirectory(_ data: Data) throws -> [ZIPEntry] {
        let count = data.count
        // Scan backwards for EOCD signature (0x06054b50)
        var eocdStart = count - 22
        guard eocdStart >= 0 else { throw SuitcaseError.invalidArchive }
        while eocdStart >= 0 {
            let sig = readUInt32(data, eocdStart)
            if sig == 0x06054b50 { break }
            eocdStart -= 1
        }
        guard eocdStart >= 0 else { throw SuitcaseError.invalidArchive }

        let diskNumber = readUInt16(data, eocdStart + 4)
        let cdStartDisk = readUInt16(data, eocdStart + 6)
        let cdEntries = readUInt16(data, eocdStart + 10)
        let cdSize = readUInt32(data, eocdStart + 12)
        let cdOffset = readUInt32(data, eocdStart + 16)

        guard diskNumber == 0, cdStartDisk == 0, cdEntries > 0 else {
            throw SuitcaseError.invalidArchive
        }

        let cdEnd = Int(cdOffset + cdSize)
        guard cdOffset <= count, cdEnd <= count else { throw SuitcaseError.invalidArchive }

        var entries: [ZIPEntry] = []
        var pos = Int(cdOffset)
        for _ in 0..<cdEntries {
            guard pos + 46 <= count else { throw SuitcaseError.invalidArchive }
            let sig = readUInt32(data, pos)
            guard sig == 0x02014b50 else { throw SuitcaseError.invalidArchive }

            let compressionMethod = readUInt16(data, pos + 10)
            let crc32 = readUInt32(data, pos + 16)
            let compressedSize = readUInt32(data, pos + 20)
            let uncompressedSize = readUInt32(data, pos + 24)
            let fileNameLength = readUInt16(data, pos + 28)
            let extraFieldLength = readUInt16(data, pos + 30)
            let localHeaderOffset = readUInt32(data, pos + 42)

            guard pos + 46 + Int(fileNameLength) <= count else { throw SuitcaseError.invalidArchive }
            let fileNameData = data.subdata(in: pos + 46 ..< pos + 46 + Int(fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8) ??
                    String(data: fileNameData, encoding: .ascii) else {
                pos += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLength(pos: pos, data: data, count: count))
                continue
            }

            // Skip directories
            if fileName.hasSuffix("/") || fileName.isEmpty {
                pos += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLength(pos: pos, data: data, count: count))
                continue
            }

            entries.append(ZIPEntry(
                fileName: fileName,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset,
                crc32: crc32
            ))

            let commentLen = Int(readUInt16(data, pos + 32))
            pos += 46 + Int(fileNameLength) + Int(extraFieldLength) + commentLen
        }

        return entries
    }

    private static func commentLength(pos: Int, data: Data, count: Int) -> UInt16 {
        guard pos + 34 <= count else { return 0 }
        return readUInt16(data, pos + 32)
    }

    // MARK: - Entry Extraction

    private static func extractEntry(_ entry: ZIPEntry, from data: Data) throws -> Data {
        let pos = Int(entry.localHeaderOffset)
        guard pos + 30 <= data.count else { throw SuitcaseError.corruptedEntry(entry.fileName) }

        let sig = readUInt32(data, pos)
        guard sig == 0x04034b50 else { throw SuitcaseError.corruptedEntry(entry.fileName) }

        let fileNameLength = Int(readUInt16(data, pos + 26))
        let extraFieldLength = Int(readUInt16(data, pos + 28))
        let dataStart = pos + 30 + fileNameLength + extraFieldLength
        let compressed = data.subdata(in: dataStart ..< dataStart + Int(entry.compressedSize))

        switch entry.compressionMethod {
        case 0: // Stored
            return compressed
        case 8: // Deflated
            return try decompressDeflate(compressed, uncompressedSize: Int(entry.uncompressedSize))
        default:
            throw SuitcaseError.extractionFailed("Unsupported compression method in entry \"\(entry.fileName)\".")
        }
    }

    /// Decompress raw deflate (RFC 1951) using Apple's Compression framework.
    /// Wraps the data in a zlib header + footer so COMPRESSION_ZLIB can handle it.
    private static func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        // Prepend minimal zlib header (deflate, window=512)
        var zlibData = Data([0x78, 0x01])
        zlibData.append(data)
        // Append dummy adler32 — decoder expects exactly 4 bytes after deflate stream
        zlibData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        var result = Data(count: uncompressedSize)
        let status = result.withUnsafeMutableBytes { destBuf in
            zlibData.withUnsafeBytes { srcBuf in
                guard let destPtr = destBuf.baseAddress, let srcPtr = srcBuf.baseAddress else {
                    return -1
                }
                return compression_decode_buffer(
                    destPtr.assumingMemoryBound(to: UInt8.self),
                    uncompressedSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    zlibData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard status == uncompressedSize else {
            throw SuitcaseError.extractionFailed("Decompression produced \(status) bytes, expected \(uncompressedSize).")
        }
        return result
    }

    // MARK: - Helpers

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { ptr in
            guard offset + 2 <= ptr.count else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { ptr in
            guard offset + 4 <= ptr.count else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
    }

    private static func sanitized(_ path: String) -> String {
        // Keep directory structure but sanitize problematic characters
        let cleaned = (path as NSString).pathComponents
            .filter { $0 != "." && $0 != ".." }
            .map { $0.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-") }
            .joined(separator: "/")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}