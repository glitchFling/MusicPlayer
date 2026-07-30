import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var player = MusicPlayer()
    @StateObject private var library = SongLibrary()
    @State private var speed: Float = 1
    @State private var reverbOn = false
    @State private var showingImporter = false

    private var isPlaying: Bool { player.playbackState == .playing }

    var body: some View {
        ZStack {
            Color.deckCharcoal.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    HStack(spacing: 18) {
                        ReelView(isSpinning: isPlaying).frame(width: 104, height: 104)
                        ReelView(isSpinning: isPlaying).frame(width: 104, height: 104)
                    }
                    .frame(maxWidth: .infinity)
                    trackInfo
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
            case .success(let urls): urls.forEach(library.importSong(from:))
            case .failure: library.lastError = .accessDenied
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
            Text("\(library.songs.count, specifier: "%02d") TAPES").font(.system(size: 11, design: .monospaced)).foregroundColor(.deckBone.opacity(0.6))
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW PLAYING").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBrass)
            Text(player.currentSong?.title ?? "Select a tape to begin")
                .font(.system(.title2, design: .serif)).foregroundColor(.deckBone).lineLimit(2)
        }
    }

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIBRARY").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55))
            if library.songs.isEmpty {
                Text("Your deck is empty. Import a local audio file above.").font(.system(.subheadline, design: .serif)).foregroundColor(.deckBone.opacity(0.7))
            } else {
                ForEach(library.songs) { song in
                    Button { player.load(song) } label: {
                        HStack {
                            Image(systemName: player.currentSong?.id == song.id ? "waveform" : "music.note")
                            Text(song.title).lineLimit(1)
                            Spacer()
                            if player.currentSong?.id == song.id { Text(isPlaying ? "PLAYING" : "READY").font(.system(size: 10, design: .monospaced)) }
                        }
                    }
                    .foregroundColor(.deckBone)
                    .padding(.vertical, 8)
                    .overlay(Divider().overlay(Color.deckHairline), alignment: .bottom)
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { isPlaying ? player.pause() : player.play() } label: {
                Label(isPlaying ? "PAUSE" : "PLAY", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(DeckButtonStyle(accent: true))
            .accessibilityLabel(isPlaying ? "Pause playback" : "Play playback")
            Button {
                if let song = library.songs.randomElement() { player.load(song) }
            } label: { Image(systemName: "shuffle") }
                .buttonStyle(DeckButtonStyle())
                .frame(width: 74)
                .accessibilityLabel("Shuffle library")
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
            Toggle("TONE / REVERB", isOn: $reverbOn).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.deckBone)
                .tint(.deckBrass)
                .onChange(of: reverbOn) { player.setReverb(enabled: $0) }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
