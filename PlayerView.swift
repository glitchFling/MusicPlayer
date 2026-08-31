import Core
import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: MusicPlayer
    @ObservedObject var session: SessionModel
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

    @StateObject private var accents = ArtworkAccentStore()
    @State private var showingPresets = false
    @State private var presetName = ""
    @State private var showingSavePreset = false
    @State private var overwritePreset: PresetStore.Preset?
    @State private var presetError: String?
    @State private var showingSuperPresets = false
    @State private var showingSaveSuperPreset = false
    @State private var superPresetName = ""
    @State private var applyingSuperPreset: SuperPreset?
    @State private var showSuperPresetWarning = false
    @State private var superPresetError: String?

    private var isPlaying: Bool { player.playbackState == .playing }
    private var accent: Color { accents.color }
    private var controlGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.05, green: 0.10, blue: 0.25), Color(red: 0.25, green: 0.10, blue: 0.38), Color(red: 0.06, green: 0.55, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: accents.palette.background.opacity(0.35), location: 0),
                .init(color: accents.palette.secondary.opacity(0.72), location: 0.24),
                .init(color: accents.palette.background, location: 0.54),
                .init(color: accents.palette.secondary.opacity(0.62), location: 0.8),
                .init(color: .deckCharcoal, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    artworkAndDetails
                    primaryTransport
                    progressView
                    secondaryControls
                    soundControls
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("MP3 Player")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: player.currentSong?.id) { accents.update(for: player.currentSong) }
        .onChange(of: speed) { player.setSpeed($0) }
        .onChange(of: reverbAmount) { player.setReverb(amount: $0) }
        .sheet(isPresented: $showingPresets) { presetsSheet }
        .alert("Save preset", isPresented: $showingSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("SAVE") { savePreset() }
            Button("CANCEL", role: .cancel) {}
        }
        .alert("Overwrite preset?", isPresented: Binding(get: { overwritePreset != nil }, set: { if !$0 { overwritePreset = nil } })) {
            Button("OVERWRITE", role: .destructive) { if let preset = overwritePreset { writePreset(preset) } }
            Button("CANCEL", role: .cancel) { overwritePreset = nil }
        } message: { Text("A preset with this name already exists.") }
        .alert("Preset unavailable", isPresented: Binding(get: { presetError != nil }, set: { if !$0 { presetError = nil } })) {
            Button("OK") { presetError = nil }
        } message: { Text(presetError ?? "") }
        .alert("Save Super Preset", isPresented: $showingSaveSuperPreset) {
            TextField("Super Preset name", text: $superPresetName)
            Button("SAVE") { saveSuperPreset() }
            Button("CANCEL", role: .cancel) {}
        }
        .alert("Apply Super Preset?", isPresented: $showSuperPresetWarning) {
            Button("APPLY", role: .destructive) { confirmApplySuperPreset() }
            Button("CANCEL", role: .cancel) { applyingSuperPreset = nil }
        } message: {
            Text("WARNING: applying this .sprst will overwrite your current playlist.")
        }
        .alert("Super Preset error", isPresented: Binding(get: { superPresetError != nil }, set: { if !$0 { superPresetError = nil } })) {
            Button("OK") { superPresetError = nil }
        } message: { Text(superPresetError ?? "") }
        .sheet(isPresented: $showingSuperPresets) { superPresetsSheet }
    }

    private var artworkAndDetails: some View {
        VStack(spacing: 14) {
            ArtworkView(url: player.currentSong?.artworkURL, size: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: accent.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 5) {
                Text("NOW PLAYING").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(accent)
                Text(player.currentSong?.title ?? "Select a tape to begin").font(.system(.title2, design: .serif)).foregroundColor(.deckBone).multilineTextAlignment(.center).lineLimit(2)
                Text(player.currentSong?.artist ?? (isPlaying ? "PLAYING" : "READY")).font(.system(size: 11, design: .monospaced)).foregroundColor(.deckBone.opacity(0.62)).lineLimit(1)
            }
        }
    }

    private var primaryTransport: some View {
        HStack(spacing: 18) {
            Button { skipToPrevious() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(DeckIconButtonStyle(accentColor: accent))
                .accessibilityLabel("Previous song")
            Button { if player.currentSong == nil { playRandomSong() } else if isPlaying { player.pause() } else { player.play() } } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(GradientIconButtonStyle(gradient: controlGradient))
                .accessibilityLabel(isPlaying ? "Pause playback" : "Play playback")
            Button { skipToNext() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(DeckIconButtonStyle(accentColor: accent))
                .accessibilityLabel("Next song")
        }
    }

    private var progressView: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { isScrubbing ? scrubTime : player.currentTime }, set: { scrubTime = $0 }), in: 0...max(player.duration, 0.01), onEditingChanged: { editing in if editing { scrubTime = player.currentTime } else { player.seek(to: scrubTime) }; isScrubbing = editing }).tint(accent).disabled(player.duration <= 0)
            HStack { Text(formatTime(player.currentTime)); Spacer(); Text(formatTime(player.duration)) }.font(.system(size: 10, design: .monospaced)).foregroundColor(.deckBone.opacity(0.55))
        }
    }

    private var secondaryControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { playbackMode = nextPlaybackMode() } label: { Label(playbackMode.title, systemImage: playbackMode.icon) }
                    .buttonStyle(DeckButtonStyle(accent: true, accentColor: accent))
                    .accessibilityLabel("Playback mode: \(playbackMode.title)")
                Menu {
                    Button("Share Current Song") { if let current = player.currentSong { exportSongs([current], nil) } }
                    Button("Select Songs to Share") { isSelecting = true }
                    Button("Share All Songs") { exportSongs(session.songs, "SongArchive.zip") }
                } label: {
                    Label("EXPORT", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(DeckButtonStyle(accent: true, accentColor: accent))
                .disabled(session.songs.isEmpty)
            }
            HStack(spacing: 10) {
                Button("PRESETS") { showingPresets = true }
                    .buttonStyle(DeckButtonStyle(accent: true, accentColor: accent))
                Button("SAVE PRESET") { presetName = ""; showingSavePreset = true }
                    .buttonStyle(DeckButtonStyle())
            }
            HStack(spacing: 10) {
                Button("SUPER PRESETS") { showingSuperPresets = true }
                    .buttonStyle(DeckButtonStyle(accent: true, accentColor: accent))
                Button("SAVE SUPER PRESET") { superPresetName = ""; showingSaveSuperPreset = true }
                    .buttonStyle(DeckButtonStyle())
            }
        }
    }

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("SPEED").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55)); Spacer(); Text("\(speed, specifier: "%.2fx")").font(.system(.body, design: .monospaced)).foregroundColor(accent) }
            Slider(value: $speed, in: 0.5...2, step: 0.01).tint(accent)
            HStack { Text("REVERB").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(.deckBone.opacity(0.55)); Spacer(); Text("\(reverbAmount, specifier: "%.0f%%")").font(.system(.body, design: .monospaced)).foregroundColor(accent) }
            Slider(value: $reverbAmount, in: 0...100, step: 1).tint(accent)
        }
    }

    private var presetsSheet: some View {
        NavigationStack {
            ZStack { Color.deckCharcoal.ignoresSafeArea(); List { ForEach(PresetStore.shared.presets) { preset in Button { apply(preset) } label: { HStack { Text(preset.name); Spacer(); Text("\(preset.speed, specifier: "%.2fx")").foregroundColor(.deckBone.opacity(0.55)) } }.listRowBackground(Color.deckGraphite) } }.scrollContentBackground(.hidden).foregroundColor(.deckBone) }
            .navigationTitle("Presets").toolbar { ToolbarItem(placement: .confirmationAction) { Button("DONE") { showingPresets = false } } }
            .task { PresetStore.shared.reload() }
        }
    }

    private func savePreset() { let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; let preset = PresetStore.Preset(name: name, speed: speed, reverb: reverbAmount); if PresetStore.shared.presets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { overwritePreset = preset } else { writePreset(preset) } }
    private func writePreset(_ preset: PresetStore.Preset) { do { try PresetStore.shared.save(preset); showingPresets = true; overwritePreset = nil } catch { presetError = error.localizedDescription } }
    private func apply(_ preset: PresetStore.Preset) { speed = preset.speed; reverbAmount = preset.reverb; showingPresets = false }
    private func formatTime(_ time: TimeInterval) -> String { guard time.isFinite else { return "0:00" }; let total = max(0, Int(time.rounded(.down))); return "\(total / 60):\(String(format: "%02d", total % 60))" }

    private func saveSuperPreset() {
        let name = superPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try SuperPresetStore.shared.save(
                name: name,
                speed: speed,
                reverb: reverbAmount,
                currentSong: player.currentSong,
                currentTime: player.currentTime,
                sessionSongs: session.songs
            )
            showingSaveSuperPreset = false
            showingSuperPresets = true
        } catch { superPresetError = error.localizedDescription }
    }

    private func applySuperPreset(_ preset: SuperPreset) {
        applyingSuperPreset = preset
        showSuperPresetWarning = true
    }

    private func confirmApplySuperPreset() {
        guard let preset = applyingSuperPreset else { return }
        do {
            try SuperPresetStore.shared.apply(preset, to: session, player: player, speed: &speed, reverb: &reverbAmount)
            applyingSuperPreset = nil
            showingSuperPresets = false
        } catch {
            superPresetError = error.localizedDescription
            applyingSuperPreset = nil
        }
    }

    private var superPresetsSheet: some View {
        NavigationStack {
            ZStack {
                Color.deckCharcoal.ignoresSafeArea()
                if SuperPresetStore.shared.presets.isEmpty {
                    VStack(spacing: 12) {
                        Text("No super presets saved yet.")
                            .font(.system(.headline, design: .serif))
                            .foregroundColor(.deckBone.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(SuperPresetStore.shared.presets) { preset in
                            Button { applySuperPreset(preset) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.system(.body, design: .serif))
                                            .foregroundColor(.deckBone)
                                        Text("\(preset.songs.count) songs \u{00B7} \(preset.speed, specifier: "%.2fx") \u{00B7} \(preset.reverb, specifier: "%.0f%%") reverb")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.deckBone.opacity(0.55))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.deckBone.opacity(0.35))
                                }
                            }
                            .listRowBackground(Color.deckGraphite)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    try? SuperPresetStore.shared.delete(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Super Presets")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("DONE") { showingSuperPresets = false }
                }
            }
            .task { SuperPresetStore.shared.reload() }
        }
    }
}

struct GradientIconButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 18, weight: .semibold)).foregroundColor(.white).frame(width: 64, height: 64).background(gradient).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)).scaleEffect(configuration.isPressed ? 0.92 : 1) }
}
