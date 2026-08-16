import Foundation

// MARK: - DeBlytes Audio Cache

/// Partially loads large audio files so you can save RAM and GPU.
/// Playback slider is disabled until fully downloaded.
final class DeBlytesService: ObservableObject {
    static let shared = DeBlytesService()

    @Published var isEnabled = false
    @Published var downloadSpeedMBs: Float = 10.0 // 1-50 MB/s configurable

    private let fileManager = FileManager.default

    /// Represents the download state of a cached audio file.
    struct CachedFile {
        let id: UUID
        let sourceURL: URL
        let cacheURL: URL
        let totalSize: UInt64
        let downloadedSize: UInt64
        let isComplete: Bool
    }

    @Published private(set) var cacheProgress: [UUID: Double] = [:] // 0.0 - 1.0

    // MARK: - Cache Management

    /// Returns a cached URL for a song file.
    /// If the file is already fully cached, returns the cache URL immediately.
    /// Otherwise starts a background download and returns nil until complete.
    func cacheURL(for song: Song) -> URL? {
        guard isEnabled else { return song.fileURL }

        let cacheDir = cacheDirectory()
        let cacheURL = cacheDir.appendingPathComponent("\(song.id.uuidString).cache")
        let metaURL = cacheDir.appendingPathComponent("\(song.id.uuidString).meta")

        // Check if fully cached
        if fileManager.fileExists(atPath: cacheURL.path) {
            let meta = loadMeta(metaURL)
            if meta?.isComplete == true {
                return cacheURL
            }
        }

        // Start caching
        startCaching(song: song, cacheURL: cacheURL, metaURL: metaURL)
        return nil // Not ready yet
    }

    func isFullyCached(_ songID: UUID) -> Bool {
        let cacheDir = cacheDirectory()
        let metaURL = cacheDir.appendingPathComponent("\(songID.uuidString).meta")
        return loadMeta(metaURL)?.isComplete == true
    }

    func clearCache() {
        let cacheDir = cacheDirectory()
        try? fileManager.removeItem(at: cacheDir)
        cacheProgress.removeAll()
    }

    // MARK: - Private

    private func cacheDirectory() -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("DeBlytes", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func startCaching(song: Song, cacheURL: URL, metaURL: URL) {
        let songID = song.id
        guard cacheProgress[songID] == nil else { return } // Already caching

        cacheProgress[songID] = 0
        let bytesPerSecond = Int64(downloadSpeedMBs * 1024 * 1024)

        Task.detached(priority: .background) {
            do {
                let sourceData = try Data(contentsOf: song.fileURL)
                let totalSize = sourceData.count
                var offset = 0

                // Stream write in chunks
                let handle = try FileHandle(forWritingTo: cacheURL)
                defer { try? handle.close() }

                while offset < totalSize {
                    let chunkSize = min(bytesPerSecond, Int64(totalSize - offset))
                    let chunk = sourceData[offset..<offset + Int(chunkSize)]
                    try handle.write(Data(chunk))
                    offset += Int(chunkSize)

                    let progress = offset
                    await MainActor.run {
                        self.cacheProgress[songID] = Double(progress) / Double(totalSize)
                    }

                    // Rate limit: sleep 1 second between chunks
                    if offset < totalSize {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }

                // Write metadata
                let meta = CacheMeta(id: songID, isComplete: true, totalSize: UInt64(totalSize))
                if let metaData = try? JSONEncoder().encode(meta) {
                    try? metaData.write(to: metaURL)
                }
            } catch {
                await MainActor.run {
                    self.cacheProgress.removeValue(forKey: songID)
                }
            }
        }
    }

    private struct CacheMeta: Codable {
        let id: UUID
        let isComplete: Bool
        let totalSize: UInt64
    }

    private func loadMeta(_ url: URL) -> CacheMeta? {
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(CacheMeta.self, from: data) else { return nil }
        return meta
    }
}