import Combine
import Foundation

// MARK: - Data model

struct SuperPresetSong: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let artist: String?
    let audioData: Data
    let artworkData: Data?
    let fileExtension: String
}

struct SuperPreset: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let speed: Float
    let reverb: Float
    let currentSongID: UUID?
    let currentTime: TimeInterval
    let songs: [SuperPresetSong]
    let timestamp: Date
}

// MARK: - Error type

enum SuperPresetError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case applyFailed(String)
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "Could not read super preset: \(msg)"
        case .saveFailed(let msg): return "Could not save super preset: \(msg)"
        case .applyFailed(let msg): return "Could not apply super preset: \(msg)"
        case .invalidFile: return "That file is not a valid .sprst super preset."
        }
    }
}

// MARK: - Store

@MainActor
final class SuperPresetStore: ObservableObject {
    static let shared = SuperPresetStore()

    @Published private(set) var presets: [SuperPreset] = []

    private let fileManager = FileManager.default
    private let directory: URL
    private let libraryDirectory: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents
            .appendingPathComponent("MusicPlayer", isDirectory: true)
            .appendingPathComponent("Super Presets", isDirectory: true)
        libraryDirectory = documents
            .appendingPathComponent("MusicPlayer", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        reload()
    }

    // MARK: - Listing

    func reload() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            presets = []
            return
        }
        presets = files
            .filter { $0.pathExtension.lowercased() == "sprst" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? PropertyListDecoder().decode(SuperPreset.self, from: $0) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Saving

    func save(name: String, speed: Float, reverb: Float, currentSong: Song?, currentTime: TimeInterval, sessionSongs: [Song]) throws {
        let sanitizedName = Self.sanitized(name)
        guard !sanitizedName.isEmpty else { throw SuperPresetError.saveFailed("Preset name is empty.") }

        var snapshotSongs: [SuperPresetSong] = []
        snapshotSongs.reserveCapacity(sessionSongs.count)

        for song in sessionSongs {
            guard let audioData = try? Data(contentsOf: song.fileURL) else { continue }
            let artworkData: Data? = song.artworkURL.flatMap { try? Data(contentsOf: $0) }
            let ext = song.fileURL.pathExtension
            snapshotSongs.append(SuperPresetSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                audioData: audioData,
                artworkData: artworkData,
                fileExtension: ext
            ))
        }

        let preset = SuperPreset(
            id: UUID(),
            name: name,
            speed: speed,
            reverb: reverb,
            currentSongID: currentSong?.id,
            currentTime: currentTime,
            songs: snapshotSongs,
            timestamp: .now
        )

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListEncoder().encode(preset)
        let filename = sanitizedName + ".sprst"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        reload()
    }

    // MARK: - Applying

    /// Extracts a Super Preset's songs into the Library directory and returns the restored Song objects
    /// with the original IDs preserved. Does NOT modify the session.
    func extractSongs(from preset: SuperPreset) throws -> [Song] {
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        var restored: [Song] = []
        restored.reserveCapacity(preset.songs.count)

        for ss in preset.songs {
            let fileURL = libraryDirectory.appendingPathComponent("\(ss.id.uuidString).\(ss.fileExtension)")
            try? fileManager.removeItem(at: fileURL)
            try ss.audioData.write(to: fileURL, options: .atomic)

            var artworkURL: URL?
            if let data = ss.artworkData {
                artworkURL = libraryDirectory.appendingPathComponent("\(ss.id.uuidString).jpg")
                try? fileManager.removeItem(at: artworkURL!)
                try data.write(to: artworkURL!, options: .atomic)
            }

            restored.append(Song(
                id: ss.id,
                title: ss.title,
                artist: ss.artist,
                fileURL: fileURL,
                artworkURL: artworkURL,
                dateAdded: .now
            ))
        }
        return restored
    }

    /// Applies a Super Preset: replaces the session songs, loads the current song at position,
    /// and returns the speed/reverb values to apply.
    @discardableResult
    func apply(
        _ preset: SuperPreset,
        to session: SessionModel,
        player: MusicPlayer,
        speed: inout Float,
        reverb: inout Float
    ) throws -> (songs: [Song], currentSongID: UUID?) {
        guard !preset.songs.isEmpty else { throw SuperPresetError.applyFailed("No songs in this super preset.") }

        // 1. Snapshot current session for rollback
        let rollbackSongs = session.songs

        // 2. Extract songs
        let restoredSongs: [Song]
        do {
            restoredSongs = try extractSongs(from: preset)
        } catch {
            throw SuperPresetError.applyFailed("Could not restore song files: \(error.localizedDescription)")
        }

        // 3. Apply to session
        session.replaceAll(with: restoredSongs)
        speed = min(max(preset.speed, 0.5), 2)
        reverb = min(max(preset.reverb, 0), 100)

        // 4. Load current song if it exists in restored songs
        if let targetID = preset.currentSongID,
           let targetSong = restoredSongs.first(where: { $0.id == targetID }) {
            player.load(targetSong)
            // Seek to saved position (must happen after load completes)
            if preset.currentTime > 0 {
                player.seek(to: min(preset.currentTime, player.duration))
            }
        } else if let first = restoredSongs.first {
            player.load(first)
        }

        return (restoredSongs, preset.currentSongID)
    }

    // MARK: - External loading (for deep links)

    func loadExternalPreset(from url: URL) throws -> SuperPreset {
        guard url.pathExtension.lowercased() == "sprst" else { throw SuperPresetError.invalidFile }
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(SuperPreset.self, from: data)
    }

    // MARK: - Helpers

    func delete(_ preset: SuperPreset) throws {
        let filename = Self.sanitized(preset.name) + ".sprst"
        try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
        reload()
    }

    func presetsDirectoryURL() -> URL { directory }
    func libraryDirectoryURL() -> URL { libraryDirectory }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
