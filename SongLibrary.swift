import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

final class SongLibrary: ObservableObject {
    enum LibraryError: LocalizedError, Identifiable {
        case accessDenied
        case unsupportedFormat
        case importFailed

        var id: String { errorDescription ?? "library-error" }

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Music file access was denied. Choose the file again to continue."
            case .unsupportedFormat: return "That file could not be read as audio. Try an MP3, M4A, WAV, or AIFF file."
            case .importFailed: return "The music file could not be copied into the library."
            }
        }
    }

    @Published private(set) var songs: [Song] = []
    @Published var lastError: LibraryError?

    private let fileManager = FileManager.default
    private let directory: URL
    private let manifestURL: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Songs", isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")
        loadManifest()
    }

    func importSong(from pickedURL: URL) {
        let hasAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { pickedURL.stopAccessingSecurityScopedResource() } }
        guard hasAccess else { lastError = .accessDenied; return }

        do {
            _ = try AVAudioFile(forReading: pickedURL)
        } catch {
            lastError = .unsupportedFormat
            return
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID()
            let destination = directory.appendingPathComponent("\(id.uuidString).\(pickedURL.pathExtension)")
            try fileManager.copyItem(at: pickedURL, to: destination)
            songs.insert(Song(id: id, title: pickedURL.deletingPathExtension().lastPathComponent, fileURL: destination), at: 0)
            persist()
        } catch {
            lastError = .importFailed
        }
    }

    func remove(_ song: Song) {
        try? fileManager.removeItem(at: song.fileURL)
        songs.removeAll { $0.id == song.id }
        persist()
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let stored = try? JSONDecoder().decode([Song].self, from: data) else { return }
        songs = stored.filter { fileManager.fileExists(atPath: $0.fileURL.path) }
        if songs.count != stored.count { persist() }
    }

    private func persist() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(songs) { try? data.write(to: manifestURL, options: .atomic) }
    }
}
