import Foundation

// MARK: - Data Model

struct VirtualPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songIDs: [UUID]
    var parentID: UUID?
    let dateCreated: Date
}

// MARK: - Store

@MainActor
final class VirtualListStore: ObservableObject {
    static let shared = VirtualListStore()

    @Published var isEnabled = false
    @Published private(set) var playlists: [VirtualPlaylist] = []
    @Published var currentPlaylistIndex = 0

    private let fileManager = FileManager.default
    private let url: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents
            .appendingPathComponent("MusicPlayer", isDirectory: true)
            .appendingPathComponent("VirtualList", isDirectory: true)
            .appendingPathComponent("playlists.json")
        load()
    }

    // MARK: - Accessors

    var rootPlaylists: [VirtualPlaylist] {
        playlists
            .filter { $0.parentID == nil }
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    var hasPlaylists: Bool { !rootPlaylists.isEmpty }

    var currentPlaylist: VirtualPlaylist? {
        let roots = rootPlaylists
        guard currentPlaylistIndex >= 0, currentPlaylistIndex < roots.count else { return nil }
        return roots[currentPlaylistIndex]
    }

    var playlistCount: Int { rootPlaylists.count }

    func subPlaylists(of parentID: UUID) -> [VirtualPlaylist] {
        playlists
            .filter { $0.parentID == parentID }
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    // MARK: - Mutations

    @discardableResult
    func createPlaylist(name: String, parentID: UUID? = nil) -> VirtualPlaylist {
        let playlist = VirtualPlaylist(
            id: UUID(),
            name: name,
            songIDs: [],
            parentID: parentID,
            dateCreated: .now
        )
        playlists.append(playlist)
        if parentID == nil {
            currentPlaylistIndex = rootPlaylists.count - 1
        }
        persist()
        return playlist
    }

    func deletePlaylist(_ id: UUID) {
        // Delete sub-playlists first
        let children = playlists.filter { $0.parentID == id }
        for child in children { deletePlaylist(child.id) }

        playlists.removeAll { $0.id == id }
        if currentPlaylistIndex >= rootPlaylists.count, !rootPlaylists.isEmpty {
            currentPlaylistIndex = rootPlaylists.count - 1
        }
        persist()
    }

    func addSong(_ songID: UUID, to playlistID: UUID) {
        guard var playlist = playlists.first(where: { $0.id == playlistID }),
              !playlist.songIDs.contains(songID) else { return }
        playlist.songIDs.append(songID)
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index] = playlist
        }
        persist()
    }

    func removeSong(_ songID: UUID, from playlistID: UUID) {
        guard var playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        playlist.songIDs.removeAll { $0 == songID }
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index] = playlist
        }
        persist()
    }

    func moveToPrevious() {
        guard !rootPlaylists.isEmpty else { return }
        currentPlaylistIndex = (currentPlaylistIndex - 1 + rootPlaylists.count) % rootPlaylists.count
    }

    func moveToNext() {
        guard !rootPlaylists.isEmpty else { return }
        currentPlaylistIndex = (currentPlaylistIndex + 1) % rootPlaylists.count
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([VirtualPlaylist].self, from: data) else { return }
        playlists = stored
    }

    /// Load songs from the library by ID. Missing IDs are silently skipped.
    func resolveSongs(_ songIDs: [UUID], from library: SongLibrary) -> [Song] {
        songIDs.compactMap { id in library.songs.first { $0.id == id } }
    }
}