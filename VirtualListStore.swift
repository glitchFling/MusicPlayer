import Core
import Foundation

// MARK: - Data Model

/// A standalone playlist value. Create one, then register it with `VirtualListStore.shared.create(playlist:)`.
///
///     let p = Playlist(name: "My Mix")
///     VirtualListStore.shared.create(playlist: p)
public struct Playlist: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var songs: [Song]
    public let dateCreated: Date

    public init(id: UUID = UUID(), name: String, songs: [Song] = [], dateCreated: Date = .now) {
        self.id = id
        self.name = name
        self.songs = songs
        self.dateCreated = dateCreated
    }

    public init(from virtual: VirtualPlaylist, resolvedSongs: [Song]) {
        self.id = virtual.id
        self.name = virtual.name
        self.songs = resolvedSongs
        self.dateCreated = virtual.dateCreated
    }
}

public struct VirtualPlaylist: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var songIDs: [UUID]
    public var parentID: UUID?
    public let dateCreated: Date
}

// MARK: - Store

@MainActor
public final class VirtualListStore: ObservableObject {
    public static let shared = VirtualListStore()

    @Published public var isEnabled = false
    @Published public private(set) var playlists: [VirtualPlaylist] = []
    @Published public var currentPlaylistIndex = 0

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

    public var rootPlaylists: [VirtualPlaylist] {
        playlists
            .filter { $0.parentID == nil }
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    public var hasPlaylists: Bool { !rootPlaylists.isEmpty }

    public var currentPlaylist: VirtualPlaylist? {
        let roots = rootPlaylists
        guard currentPlaylistIndex >= 0, currentPlaylistIndex < roots.count else { return nil }
        return roots[currentPlaylistIndex]
    }

    public var playlistCount: Int { rootPlaylists.count }

    public func subPlaylists(of parentID: UUID) -> [VirtualPlaylist] {
        playlists
            .filter { $0.parentID == parentID }
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    // MARK: - Mutations

    /// Create a playlist from a standalone `Playlist` value.
    /// Equivalent to `createPlaylist(name:playlist.name, ...)` but mirrors
    /// the `virtuallist.create(playlist)` style from the spec.
    @discardableResult
    public func create(playlist p: Playlist, parentID: UUID? = nil) -> VirtualPlaylist {
        let vp = VirtualPlaylist(
            id: p.id,
            name: p.name,
            songIDs: p.songs.map(\.id),
            parentID: parentID,
            dateCreated: p.dateCreated
        )
        playlists.append(vp)
        if parentID == nil {
            currentPlaylistIndex = rootPlaylists.count - 1
        }
        persist()
        return vp
    }

    /// Create a playlist at a slash-delimited path, e.g. `create(at: "playlist/playlist_2")`.
    /// Intermediate playlists are created if they don't exist.
    @discardableResult
    public func create(at path: String) -> VirtualPlaylist {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return createPlaylist(name: "Untitled") }

        var parentID: UUID?
        for (i, name) in components.enumerated() {
            let existing = playlists.filter { $0.parentID == parentID && $0.name == name }
            if let found = existing.first {
                parentID = found.id
            } else {
                let isLeaf = (i == components.count - 1)
                let vp = VirtualPlaylist(
                    id: UUID(),
                    name: name,
                    songIDs: [],
                    parentID: parentID,
                    dateCreated: .now
                )
                playlists.append(vp)
                if isLeaf && parentID == nil {
                    currentPlaylistIndex = rootPlaylists.count - 1
                }
                parentID = vp.id
            }
        }
        persist()
        return playlists.first(where: { $0.id == parentID })!
    }

    @discardableResult
    public func createPlaylist(name: String, parentID: UUID? = nil) -> VirtualPlaylist {
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

    public func deletePlaylist(_ id: UUID) {
        // Delete sub-playlists first
        let children = playlists.filter { $0.parentID == id }
        for child in children { deletePlaylist(child.id) }

        playlists.removeAll { $0.id == id }
        if currentPlaylistIndex >= rootPlaylists.count, !rootPlaylists.isEmpty {
            currentPlaylistIndex = rootPlaylists.count - 1
        }
        persist()
    }

    public func addSong(_ songID: UUID, to playlistID: UUID) {
        guard var playlist = playlists.first(where: { $0.id == playlistID }),
              !playlist.songIDs.contains(songID) else { return }
        playlist.songIDs.append(songID)
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index] = playlist
        }
        persist()
    }

    public func removeSong(_ songID: UUID, from playlistID: UUID) {
        guard var playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        playlist.songIDs.removeAll { $0 == songID }
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index] = playlist
        }
        persist()
    }

    public func moveToPrevious() {
        guard !rootPlaylists.isEmpty else { return }
        currentPlaylistIndex = (currentPlaylistIndex - 1 + rootPlaylists.count) % rootPlaylists.count
    }

    public func moveToNext() {
        guard !rootPlaylists.isEmpty else { return }
        currentPlaylistIndex = (currentPlaylistIndex + 1) % rootPlaylists.count
    }

    public func renamePlaylist(_ id: UUID, to name: String) {
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
    public func resolveSongs(_ songIDs: [UUID], from library: SongLibrary) -> [Song] {
        songIDs.compactMap { id in library.songs.first { $0.id == id } }
    }

    /// Return all root-level playlists as `Playlist` values with resolved songs.
    public func display() -> [Playlist] {
        rootPlaylists.map { vp in
            let songs = resolveSongs(vp.songIDs, from: SongLibrary.shared)
            return Playlist(from: vp, resolvedSongs: songs)
        }
    }
}