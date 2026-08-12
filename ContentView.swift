import SwiftUI
import UniformTypeIdentifiers

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
    @StateObject private var library = SongLibrary()
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
        library.songs.filter { selectedSongIDs.contains($0.id) }
    }
    @State private var reverbAmount: Float = 0
    @State private var showingImporter = false
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var showingSettings = false

    private var nextPlaybackMode: PlaybackMode {
        guard let index = PlaybackMode.allCases.firstIndex(of: playbackMode) else { return .shuffle }
        return PlaybackMode.allCases[(index + 1) % PlaybackMode.allCases.count]
    }

    private var isPlaying: Bool { player.playbackState == .playing }

    var body: some View {
        ZStack {
            Color.deckCharcoal.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    island
                    Button { showingImporter = true } label: {
                        Label("IMPORT MUSIC", systemImage: "tray.and.arrow.up.fill")
                    }
                    .buttonStyle(DeckButtonStyle())
                    libraryList
                    transport
                    soundControls
                }
                .padding(24)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { for url in urls { await library.importSong(from: url) } }
            case .failure: library.lastError = .accessDenied
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

    private var island: some View {
        DeckPanel {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ArtworkView(url: player.currentSong?.artworkURL, size: 108)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("NOW PLAYING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.deckBrass)
                        Text(player.currentSong?.title ?? "Select a tape to begin")
                            .font(.system(.title2, design: .serif))
                            .foregroundColor(.deckBone)
                            .lineLimit(2)
                        Text(player.currentSong?.artist ?? (isPlaying ? "PLAYING" : "READY"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.deckBone.opacity(0.62))
                            .lineLimit(1)
                        Menu {
                            Button("Share Current Song") {
                                if let current = player.currentSong { exportSongs([current], archiveName: nil) }
                            }
                            Button("Select Songs to Share") {
                                isSelecting = true
                            }
                            Button("Share All Songs") {
                                exportSongs(library.songs, archiveName: "SongArchive.zip")
                            }
                        } label: {
                            Label("EXPORT", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(DeckButtonStyle())
                        .disabled(library.songs.isEmpty)
                    }
                    Spacer(minLength: 0)
                }
                progressView
                islandTransport
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { isScrubbing ? scrubTime : player.currentTime }, set: { scrubTime = $0 }), in: 0...max(player.duration, 0.01), onEditingChanged: { editing in
                if editing { scrubTime = player.currentTime } else { player.seek(to: scrubTime) }
                isScrubbing = editing
            })
            .tint(.deckBrass)
            .disabled(player.duration <= 0)
            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.deckBone.opacity(0.55))
        }
    }

    private var islandTransport: some View {
        HStack(spacing: 10) {
            Button { skipToPrevious() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(DeckIconButtonStyle())
                .accessibilityLabel("Previous song")
            Button {
                if player.currentSong == nil { playRandomSong() } else if isPlaying { player.pause() } else { player.play() }
            } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(DeckIconButtonStyle(accent: true))
                .accessibilityLabel(isPlaying ? "Pause playback" : "Play playback")
            Button { skipToNext() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(DeckIconButtonStyle())
                .accessibilityLabel("Next song")
            Button { playbackMode = nextPlaybackMode } label: { Image(systemName: playbackMode.icon) }
                .buttonStyle(DeckIconButtonStyle())
                .accessibilityLabel("Playback mode: \(playbackMode.title)")
            Spacer()
            Text(playbackMode.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.deckBrass)
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
            guard let index = library.songs.firstIndex(where: { $0.id == current.id }) else { return }
            player.load(library.songs[(index + 1) % library.songs.count])
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
        library.remove(song)
    }

    private func randomSong(excluding current: Song?) -> Song? {
        guard !library.songs.isEmpty else { return nil }
        let choices = library.songs.count > 1
            ? library.songs.filter { $0.id != current?.id }
            : library.songs
        return choices.randomElement()
    }

    private func advancePlayback() {
        guard !library.songs.isEmpty else { return }
        switch playbackMode {
        case .repeatOne:
            if let current = player.currentSong { player.load(current) }
        case .repeatAll:
            guard let current = player.currentSong,
                  let index = library.songs.firstIndex(where: { $0.id == current.id }) else {
                if let first = library.songs.first { player.load(first) }
                return
            }
            player.load(library.songs[(index + 1) % library.songs.count])
        case .shuffle:
            if let song = randomSong(excluding: player.currentSong) { player.load(song) }
        }
    }

    private func playRandomSong() {
        if let song = randomSong(excluding: player.currentSong) { player.load(song) }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
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
            Text("\(library.songs.count, specifier: "%02d") TAPES").font(.system(size: 11, design: .monospaced)).foregroundColor(.deckBone.opacity(0.6))

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
            Text("LIBRARY").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
            if library.songs.isEmpty {
                Text("Your deck is empty. Import a local audio file above.").font(.system(.subheadline, design: .serif)).foregroundColor(.deckBone.opacity(0.7))
            } else {
                ForEach(library.songs) { song in
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

    private var transport: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { isScrubbing ? scrubTime : player.currentTime },
                    set: { scrubTime = $0 }
                ), in: 0...max(player.duration, 0.01), onEditingChanged: { editing in
                    if editing {
                        scrubTime = player.currentTime
                    } else {
                        player.seek(to: scrubTime)
                    }
                    isScrubbing = editing
                })
                .tint(.deckBrass)
                .disabled(player.duration <= 0)
                .accessibilityLabel("Playback progress")
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.deckBone.opacity(0.6))
            }
            HStack(spacing: 12) {
                Button {
                    if player.currentSong == nil { playRandomSong() }
                    else { isPlaying ? player.pause() : player.play() }
                } label: {
                    Label(isPlaying ? "PAUSE" : "PLAY", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(DeckButtonStyle(accent: true))
                .accessibilityLabel(isPlaying ? "Pause playback" : "Play playback")
                Button { playRandomSong() } label: { Image(systemName: "shuffle") }
                    .buttonStyle(DeckButtonStyle())
                    .frame(width: 74)
                    .accessibilityLabel("Play a random song")
                Button {
                    playbackMode = nextPlaybackMode
                } label: {
                    Label(playbackMode.title, systemImage: playbackMode.icon)
                }
                .buttonStyle(DeckButtonStyle())
                .accessibilityLabel("Playback mode: \(playbackMode.title)")
                .accessibilityHint("Changes to \(nextPlaybackMode.title)")
            }
        }
    }

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SPEED").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
                Spacer()
                Text("\(speed, specifier: "%.2fx")").font(.system(.body, design: .monospaced)).foregroundColor(.deckBrass)
            }
            Slider(value: $speed, in: 0.5...2, step: 0.01).tint(.deckBrass)
            HStack {
                Text("REVERB").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
                Spacer()
                Text("\(reverbAmount, specifier: "%.0f%%")").font(.system(.body, design: .monospaced)).foregroundColor(.deckBrass)
            }
            Slider(value: $reverbAmount, in: 0...100, step: 1).tint(.deckBrass)
                .onChange(of: reverbAmount) { player.setReverb(amount: $0) }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
