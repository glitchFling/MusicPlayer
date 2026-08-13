import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: MusicPlayer
    @ObservedObject var library: SongLibrary
    @Binding var playbackMode: PlaybackMode
    @Binding var speed: Float
    @Binding var reverbAmount: Float
    @Binding var isSelecting: Bool
    @Binding var isScrubbing: Bool
    @Binding var scrubTime: TimeInterval

    let nextPlaybackMode: () -> PlaybackMode
    let skipToPrevious: () -> Void
    let skipToNext: () -> Void
    let playRandomSong: () -> Void
    let exportSongs: ([Song], String?) -> Void

    private var isPlaying: Bool { player.playbackState == .playing }

    var body: some View {
        ZStack {
            Color.deckCharcoal.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    playerPanel
                    soundControls
                }
                .padding(24)
            }
        }
        .navigationTitle("MP3 Player")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: speed) { player.setSpeed($0) }
        .onChange(of: reverbAmount) { player.setReverb(amount: $0) }
    }

    private var playerPanel: some View {
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
                                if let current = player.currentSong { exportSongs([current], nil) }
                            }
                            Button("Select Songs to Share") { isSelecting = true }
                            Button("Share All Songs") { exportSongs(library.songs, "SongArchive.zip") }
                        } label: {
                            Label("EXPORT", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(DeckButtonStyle())
                        .disabled(library.songs.isEmpty)
                    }
                    Spacer(minLength: 0)
                }
                progressView
                transport
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { isScrubbing ? scrubTime : player.currentTime },
                set: { scrubTime = $0 }
            ), in: 0...max(player.duration, 0.01), onEditingChanged: { editing in
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

    private var transport: some View {
        VStack(spacing: 12) {
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
                Button { playbackMode = nextPlaybackMode() } label: { Image(systemName: playbackMode.icon) }
                    .buttonStyle(DeckIconButtonStyle())
                    .accessibilityLabel("Playback mode: \(playbackMode.title)")
                Spacer()
                Text(playbackMode.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.deckBrass)
            }
            HStack(spacing: 12) {
                Button {
                    if player.currentSong == nil { playRandomSong() } else { isPlaying ? player.pause() : player.play() }
                } label: {
                    Label(isPlaying ? "PAUSE" : "PLAY", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(DeckButtonStyle(accent: true))
                .accessibilityLabel(isPlaying ? "Pause playback" : "Play playback")
                Button { playRandomSong() } label: { Image(systemName: "shuffle") }
                    .buttonStyle(DeckButtonStyle())
                    .frame(width: 74)
                    .accessibilityLabel("Play a random song")
                Button { playbackMode = nextPlaybackMode() } label: {
                    Label(playbackMode.title, systemImage: playbackMode.icon)
                }
                .buttonStyle(DeckButtonStyle())
                .accessibilityLabel("Playback mode: \(playbackMode.title)")
                .accessibilityHint("Changes to \(nextPlaybackMode().title)")
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
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
