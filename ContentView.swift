import Core
import Suitcase
import SwiftUI
import UniformTypeIdentifiers
import VirtualList

enum PlaybackMode: String, CaseIterable {
    case repeatOne
    case repeatAll
    case shuffle

    var title: String {
        switch self {
        case .repeatOne: return "LOOP"
        case .repeatAll: return "SEQUENCE"
        case .shuffle: return "SHUFFLE"
        }
    }

    var icon: String {
        switch self {
        case .repeatOne: return "repeat.1"
        case .repeatAll: return "repeat"
        case .shuffle: return "shuffle"
        }
    }
}

struct ContentView: View {
    @StateObject private var player = MusicPlayer()
    @ObservedObject private var library = SongLibrary.shared
    @ObservedObject private var session = SessionModel.shared
    @ObservedObject private var virtualList = VirtualListStore.shared
    @State private var playbackMode: PlaybackMode = .shuffle
    @State private var playHistory: [Song] = []
    @State private var isSelecting = false
    @State private var selectedSongIDs: Set<UUID> = []
    @State private var shareItem: SharePayload?
    @State private var isExporting = false
    @State private var speed: Float = 1

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var selectedSongs: [Song] {
        session.songs.filter { selectedSongIDs.contains($0.id) }
    }
    @State private var reverbAmount: Float = 0
    @State private var showingImporter = false
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var showingSettings = false
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @AppStorage("virtuallist_enabled") private var virtualListEnabled = false
    @State private var isImportingAudio = false
    @State private var importCompleted = 0
    @State private var importTotal = 0

    private var nextPlaybackMode: PlaybackMode {
        guard let index = PlaybackMode.allCases.firstIndex(of: playbackMode) else { return .shuffle }
        return PlaybackMode.allCases[(index + 1) % PlaybackMode.allCases.count]
    }

    private var isPlaying: Bool { player.playbackState == .playing }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.deckCharcoal.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        NavigationLink {
                            PlayerView(
                                player: player,
                                session: session,
                                playbackMode: $playbackMode,
                                speed: $speed,
                                reverbAmount: $reverbAmount,
                                isSelecting: $isSelecting,
                                isScrubbing: $isScrubbing,
                                scrubTime: $scrubTime,
                                nextPlaybackMode: { nextPlaybackMode },
                                skipToPrevious: skipToPrevious,
                                skipToNext: skipToNext,
                                playRandomSong: playRandomSong,
                                exportSongs: { songs, archiveName in exportSongs(songs, archiveName: archiveName) }
                            )
                        } label: {
                            Label("MP3 PLAYER", systemImage: "music.note.list")
                        }
                        .buttonStyle(DeckButtonStyle(accent: true))
                        Button { showingImporter = true } label: {
                            Label("IMPORT MUSIC", systemImage: "tray.and.arrow.up.fill")
                        }
                        .buttonStyle(DeckButtonStyle())
                        Button { showingImporter = true } label: {
                            Label("IMPORT ZIP", systemImage: "shippingbox")
                        }
                        .buttonStyle(DeckButtonStyle(accent: true))
                        .disabled(isImportingAudio)
                        libraryList
                    }
                    .padding(24)
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .archive], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importTotal = urls.count
                importCompleted = 0
                isImportingAudio = !urls.isEmpty
                Task {
                    for url in urls {
                        let ext = url.pathExtension.lowercased()
                        if ext == "zip" {
                            await importZIP(url)
                        } else {
                            if let song = await library.importSong(from: url) {
                                session.addToSession(song)
                            }
                            importCompleted += 1
                        }
                    }
                    await MainActor.run { isImportingAudio = false }
                }
            case .failure: library.lastError = .accessDenied
            }
        } .disabled(isImportingAudio)
        .overlay {
            if isImportingAudio {
                ZStack { Color.deckCharcoal.opacity(0.82).ignoresSafeArea(); ProgressView().tint(.deckBrass).scaleEffect(1.35) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Importing audio")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }

        .sheet(item: $shareItem) { payload in
            ShareSheet(items: [payload.url]) {
                try? FileManager.default.removeItem(at: payload.url)
                shareItem = nil
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .overlay {
            if isExporting {
                ProgressView("Preparing export…")
                    .tint(.deckBrass)
                    .padding(24)
                    .background(Color.deckGraphite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onOpenURL { url in
            handlePresetURL(url)
        }
        .onAppear { session.populateFromLibrary(library); VirtualListStore.shared.isEnabled = virtualListEnabled }
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("CREATE") { createPlaylist() }
            Button("CANCEL", role: .cancel) {}
        }
        .alert("Playback note", isPresented: errorPresented) {
            Button("OK") {
                library.lastError = nil
                player.lastError = nil
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: speed) { player.setSpeed($0) }
        .onChange(of: player.playbackState) { state in
            guard state == .finished else { return }
            advancePlayback()
        }
    }

    private func exportSongs(_ songs: [Song], archiveName: String?) {
        guard !songs.isEmpty else { library.lastError = .exportFailed; return }
        isExporting = true
        Task.detached(priority: .userInitiated) {
            do {
                let url: URL
                if let archiveName {
                    url = try SongLibrary.exportArchive(for: songs, named: archiveName)
                } else {
                    let source = songs[0]
                    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(source.title).appendingPathExtension(source.fileURL.pathExtension)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: source.fileURL, to: destination)
                    url = destination
                }
                await MainActor.run {
                    isExporting = false
                    shareItem = SharePayload(url: url)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    library.lastError = .exportFailed
                }
            }
        }
    }

    private func skipToNext() {
        guard let current = player.currentSong else { playRandomSong(); return }
        playHistory.append(current)
        if playHistory.count > 20 { playHistory.removeFirst() }
        switch playbackMode {
        case .shuffle: playRandomSong()
        case .repeatOne, .repeatAll:
            guard let index = session.songs.firstIndex(where: { $0.id == current.id }) else { return }
            player.load(session.songs[(index + 1) % session.songs.count])
        }
    }

    private func skipToPrevious() {
        if player.currentTime > 3 { player.seek(to: 0); return }
        guard let previous = playHistory.popLast() else { return }
        player.load(previous)
    }

    private func removeSong(_ song: Song) {
        if player.currentSong?.id == song.id {
            player.pause()
        }
        playHistory.removeAll { $0.id == song.id }
        selectedSongIDs.remove(song.id)
        session.removeFromSession(song)
    }

    private func randomSong(excluding current: Song?) -> Song? {
        guard !session.songs.isEmpty else { return nil }
        let choices = session.songs.count > 1
            ? session.songs.filter { $0.id != current?.id }
            : session.songs
        return choices.randomElement()
    }

    private func advancePlayback() {
        guard !session.songs.isEmpty else { return }
        switch playbackMode {
        case .repeatOne:
            if let current = player.currentSong { player.load(current) }
        case .repeatAll:
            guard let current = player.currentSong,
                  let index = session.songs.firstIndex(where: { $0.id == current.id }) else {
                if let first = session.songs.first { player.load(first) }
                return
            }
            player.load(session.songs[(index + 1) % session.songs.count])
        case .shuffle:
            if let song = randomSong(excluding: player.currentSong) { player.load(song) }
        }
    }

    private func playRandomSong() {
        if let song = randomSong(excluding: player.currentSong) { player.load(song) }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { library.lastError != nil || player.lastError != nil }, set: { presented in
            if !presented {
                library.lastError = nil
                player.lastError = nil
            }
        })
    }

    private var errorMessage: String {
        library.lastError?.localizedDescription ?? player.lastError?.localizedDescription ?? "Something went wrong."
    }

    private func handlePresetURL(_ url: URL) {
        guard url.scheme?.lowercased() == "musicplayer" else { return }
        let rawPath = url.host.map { "/" + $0 + url.path } ?? url.path
        let presetURL = URL(fileURLWithPath: rawPath.removingPercentEncoding ?? rawPath)
        do {
            let hasAccess = presetURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { presetURL.stopAccessingSecurityScopedResource() } }
            let preset = try PresetStore.shared.loadExternalPreset(from: presetURL)
            speed = min(max(preset.speed, 0.5), 2)
            reverbAmount = min(max(preset.reverb, 0), 100)
        } catch {
            library.lastError = .importFailed
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        VirtualListStore.shared.createPlaylist(name: name)
        newPlaylistName = ""
        showingNewPlaylist = false
        loadPlaylistSongs()
    }

    private func loadPlaylistSongs() {
        guard let playlist = VirtualListStore.shared.currentPlaylist else { return }
        let songs = VirtualListStore.shared.resolveSongs(playlist.songIDs, from: library)
        session.replaceAll(with: songs)
    }

    private func importZIP(_ zipURL: URL) async {
        do {
            let hasAccess = zipURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { zipURL.stopAccessingSecurityScopedResource() } }
            let extracted = try SuitcaseService.extractAudio(from: zipURL)
            for extractedURL in extracted {
                if let song = await library.importSong(from: extractedURL) {
                    await MainActor.run { session.addToSession(song) }
                }
            }
            await MainActor.run { importCompleted += extracted.count }
        } catch {
            await MainActor.run { library.lastError = .importFailed }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NIGHT SHIFT").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3).foregroundColor(.deckBrass)
                Text("Tape deck").font(.system(.largeTitle, design: .serif)).foregroundColor(.deckBone)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(DeckIconButtonStyle())
            .frame(width: 42, height: 42)
            .accessibilityLabel("Settings")
            Text("\(session.songs.count, specifier: "%02d") TAPES").font(.system(size: 11, design: .monospaced)).foregroundColor(.deckBone.opacity(0.6))

        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW PLAYING").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBrass)
            HStack(spacing: 14) {
                ArtworkView(url: player.currentSong?.artworkURL, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.currentSong?.title ?? "Select a tape to begin")
                        .font(.system(.title2, design: .serif)).foregroundColor(.deckBone).lineLimit(2)
                    if let artist = player.currentSong?.artist, !artist.isEmpty {
                        Text(artist).font(.system(.subheadline, design: .monospaced)).foregroundColor(.deckBone.opacity(0.65))
                    }
                }
            }
        }
    }

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if virtualListEnabled && virtualList.hasPlaylists {
                playlistNavigation
            } else {
                Text("SESSION").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
            }
            if session.songs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No tapes in the session yet.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.deckBone.opacity(0.5))
                    Text("Import music or a ZIP above to get started.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.deckBone.opacity(0.35))
                }
                .padding(.vertical, 12)
            }
            ForEach(session.songs) { song in
                    Button {
                        if isSelecting {
                            if selectedSongIDs.contains(song.id) { selectedSongIDs.remove(song.id) } else { selectedSongIDs.insert(song.id) }
                        } else {
                            player.load(song)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isSelecting {
                                Image(systemName: selectedSongIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedSongIDs.contains(song.id) ? .deckBrass : .deckBone.opacity(0.5))
                            }
                            ArtworkView(url: song.artworkURL, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                if let artist = song.artist, !artist.isEmpty {
                                    Text(artist).font(.system(size: 10, design: .monospaced)).foregroundColor(.deckBone.opacity(0.55)).lineLimit(1)
                                }
                            }
                            Spacer()
                            if player.currentSong?.id == song.id { Text(isPlaying ? "PLAYING" : "READY").font(.system(size: 10, design: .monospaced)) }
                        }
                    }
                    .foregroundColor(.deckBone)
                    .padding(.vertical, 8)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            removeSong(song)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            removeSong(song)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                    .overlay(Divider().overlay(Color.deckHairline), alignment: .bottom)
                }
                if isSelecting {
                    HStack {
                        Button("CANCEL") {
                            isSelecting = false
                            selectedSongIDs.removeAll()
                        }
                        .buttonStyle(DeckButtonStyle())
                        Button("SHARE \(selectedSongs.count)") {
                            exportSongs(selectedSongs, archiveName: "SongArchive-Selected.zip")
                            isSelecting = false
                            selectedSongIDs.removeAll()
                        }
                        .buttonStyle(DeckButtonStyle(accent: true))
                        .disabled(selectedSongs.isEmpty)
                    }
                }
            }
        }
    }

    private var playlistNavigation: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { virtualList.moveToPrevious(); loadPlaylistSongs() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(DeckIconButtonStyle())
                .frame(width: 36, height: 36)
                .accessibilityLabel("Previous playlist")

                VStack(spacing: 2) {
                    Text("PLAYLIST").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
                    if let playlist = virtualList.currentPlaylist {
                        Text(playlist.name)
                            .font(.system(.body, design: .serif))
                            .foregroundColor(.deckBone)
                            .lineLimit(1)
                        Text("\(playlist.songIDs.count) songs")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.deckBone.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity)

                Button { virtualList.moveToNext(); loadPlaylistSongs() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(DeckIconButtonStyle())
                .frame(width: 36, height: 36)
                .accessibilityLabel("Next playlist")
            }

            if virtualListEnabled {
                HStack(spacing: 10) {
                    Button("NEW PLAYLIST") { showingNewPlaylist = true }
                        .buttonStyle(DeckButtonStyle())
                    if virtualList.hasPlaylists {
                        Button("DELETE") {
                            if let playlist = virtualList.currentPlaylist {
                                session.clear()
                                virtualList.deletePlaylist(playlist.id)
                            }
                        }
                        .buttonStyle(DeckButtonStyle(accent: true, accentColor: .deckEmber))
                    }
                }
            }
        }
    }

    }

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
