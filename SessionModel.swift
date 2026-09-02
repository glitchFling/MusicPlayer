import Combine
import Foundation

@MainActor
final class SessionModel: ObservableObject {
    static let shared = SessionModel()

    @Published private(set) var songs: [Song] = []

    func contains(_ song: Song) -> Bool {
        songs.contains { $0.id == song.id }
    }

    func addToSession(_ song: Song) {
        guard !contains(song) else { return }
        songs.append(song)
    }

    func addToSession(_ songs: [Song]) {
        for song in songs { addToSession(song) }
    }

    func removeFromSession(_ song: Song) {
        songs.removeAll { $0.id == song.id }
    }

    func clear() {
        songs.removeAll()
    }

    func replaceAll(with songs: [Song]) {
        self.songs = songs
    }

    /// Populate the session from a persistent library on first launch.
    func populateFromLibrary(_ library: SongLibrary) {
        guard songs.isEmpty else { return }
        songs = library.songs
    }
}
