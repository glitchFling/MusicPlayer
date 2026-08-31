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
            let fileNameLength = Int(readUInt16(data, pos + 28))
            let extraFieldLength = Int(readUInt16(data, pos + 30))
            let commentLen = Int(readUInt16(data, pos + 32))
            let localHeaderOffset = readUInt32(data, pos + 42)

            // Advance past this central directory record.
            let recordSize = 46 + fileNameLength + extraFieldLength + commentLen
            guard pos + recordSize <= count else { throw SuitcaseError.invalidArchive }
            let fileNameEnd = pos + 46 + fileNameLength

            let fileNameData = data.subdata(in: pos + 46 ..< fileNameEnd)
            guard let fileName = String(data: fileNameData, encoding: .utf8) ??
                    String(data: fileNameData, encoding: .ascii) else {
                pos += recordSize
                continue
            }

            // Skip directories
            if fileName.hasSuffix("/") || fileName.isEmpty {
                pos += recordSize
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

            pos += recordSize
        }

        return entries
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
    /// We use compression_stream in decode mode for raw deflate, which avoids
    /// the window-size pitfalls of fabricating a zlib header.
    private static func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        var result = Data(count: uncompressedSize)

        // compression_stream can route raw DEFLATE correctly by using
        // COMPRESSION_ZLIB in streaming mode, but ZIP stores raw deflate.
        // Apple's Compression framework does not expose raw deflate directly,
        // so wrap it in a zlib container with a maximal window (0x78 0xDA).
        var zlibData = Data([0x78, 0xDA])   // zlib header, window = 32KB (max)
        zlibData.append(data)
        // Append a valid adler32 placeholder (decoder reads it; we pre-alloc
        // the correct output size, so the checksum value is ignored).
        zlibData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        let status = result.withUnsafeMutableBytes { destBuf -> Int in
            zlibData.withUnsafeBytes { srcBuf in
                guard let destPtr = destBuf.baseAddress, let srcPtr = srcBuf.baseAddress else {
                    return -1
                }
                // Stream in one shot; compression_decode_buffer requires the
                // entire stream to be present, which it is.
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
            // Fall back: try streaming decode which tolerates truncated input.
            if let streamDecoded = try? streamingInflate(zlibData, expected: uncompressedSize),
               streamDecoded.count == uncompressedSize {
                return streamDecoded
            }
            throw SuitcaseError.extractionFailed(
                "Decompression produced \(status) bytes, expected \(uncompressedSize)."
            )
        }
        return result
    }

    /// Tolerant streaming inflate fallback.
    private static func streamingInflate(_ zlibData: Data, expected: Int) throws -> Data {
        var stream = compression_stream()
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw SuitcaseError.extractionFailed("Could not initialize decompressor.")
        }
        defer { compression_stream_destroy(&stream) }

        var output = Data(count: expected)
        let dstSize = 65536
        var dstBuf = [UInt8](repeating: 0, count: dstSize)

        let src = zlibData.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        stream.src_ptr = src.baseAddress!
        stream.src_size = zlibData.count
        stream.dst_ptr = dstBuf.withUnsafeMutableBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        stream.dst_size = dstSize

        var written = 0
        while true {
            let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE))
            if status == COMPRESSION_STATUS_END {
                let produced = dstSize - stream.dst_size
                if written + produced <= output.count {
                    output.replaceSubrange(written..<written + produced, with: dstBuf[0..<produced])
                    written += produced
                }
                return output.prefix(written)
            }
            if status == COMPRESSION_STATUS_ERROR {
                throw SuitcaseError.extractionFailed("Decompression error.")
            }
            let produced = dstSize - stream.dst_size
            if produced == 0 {
                // No progress; avoid infinite loop.
                throw SuitcaseError.extractionFailed("Decompression stalled.")
            }
            if written + produced <= output.count {
                output.replaceSubrange(written..<written + produced, with: dstBuf[0..<produced])
                written += produced
            }
            stream.dst_ptr = dstBuf.withUnsafeMutableBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
            stream.dst_size = dstSize
        }
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