import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingUpdates = false
    @AppStorage("virtuallist_enabled") private var virtualListEnabled = false
    @AppStorage("bettermusic_enabled") private var betterMusicEnabled = false
    @AppStorage("volumewarning_enabled") private var volumeWarningEnabled = false
    @AppStorage("debyltes_enabled") private var deblytesEnabled = false
    @AppStorage("focusonme_enabled") private var focusOnMeEnabled = false
    @AppStorage("volumewarning_autoskip") private var volumeWarningAutoSkip = true
    @AppStorage("volumewarning_threshold") private var volumeWarningThreshold: Double = 20.0
    @AppStorage("debyltes_speed") private var deblytesSpeed: Double = 10.0

    var body: some View {
        ZStack {
            Color.deckCharcoal.ignoresSafeArea()
            List {
                Section {
                    Button { showingUpdates = true } label: {
                        HStack {
                            Label("Updates", systemImage: "arrow.down.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.deckBone.opacity(0.45))
                        }
                    }
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                } header: {
                    Text("SYSTEM")
                }

                Section {
                    Toggle(isOn: $virtualListEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("VirtualList", systemImage: "list.bullet.indent")
                            Text("Enable multiple playlist support with sub-playlists.")
                                .font(.caption)
                                .foregroundColor(.deckBone.opacity(0.6))
                        }
                    }
                    .tint(.deckBrass)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                    .onChange(of: virtualListEnabled) { newValue in
                        VirtualListStore.shared.isEnabled = newValue
                    }
                    Toggle(isOn: $betterMusicEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("BetterMusic", systemImage: "radio")
                            Text("Audio editing: speed/pitch, bass boost, trim, remove vocals.")
                                .font(.caption)
                                .foregroundColor(.deckBone.opacity(0.6))
                        }
                    }
                    .tint(.deckBrass)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                    .onChange(of: betterMusicEnabled) { BetterMusicProcessor.shared.isEnabled = $0 }
                    Toggle(isOn: $volumeWarningEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("VolumeWarning", systemImage: "exclamationmark.triangle")
                            Text("Loud song detection and auto-volume protection.")
                                .font(.caption)
                                .foregroundColor(.deckBone.opacity(0.6))
                        }
                    }
                    .tint(.deckBrass)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                    .onChange(of: volumeWarningEnabled) { VolumeWarningService.shared.isEnabled = $0 }
                    if volumeWarningEnabled {
                        Toggle(isOn: $volumeWarningAutoSkip) {
                            Text("Automatically skip over loud songs")
                                .font(.subheadline)
                                .foregroundColor(.deckBone.opacity(0.8))
                        }
                        .tint(.deckBrass)
                        .foregroundColor(.deckBone)
                        .listRowBackground(Color.deckGraphite)
                        .onChange(of: volumeWarningAutoSkip) { VolumeWarningService.shared.autoSkip = $0 }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Threshold: \(volumeWarningThreshold, specifier: "%.0f") dB")
                                    .font(.subheadline)
                                    .foregroundColor(.deckBone.opacity(0.8))
                                Spacer()
                            }
                            Slider(value: $volumeWarningThreshold, in: 10...200, step: 1)
                                .tint(.deckBrass)
                                .onChange(of: volumeWarningThreshold) { VolumeWarningService.shared.thresholdDB = Float($0) }
                        }
                        .listRowBackground(Color.deckGraphite)
                    }
                    Toggle(isOn: $deblytesEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("DeBlytes", systemImage: "memorychip")
                            Text("Partial audio caching to save RAM. Slider disabled until fully loaded.")
                                .font(.caption)
                                .foregroundColor(.deckBone.opacity(0.6))
                        }
                    }
                    .tint(.deckBrass)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                    .onChange(of: deblytesEnabled) { DeBlytesService.shared.isEnabled = $0 }
                    if deblytesEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Download speed: \(deblytesSpeed, specifier: "%.0f") MB/s")
                                    .font(.subheadline)
                                    .foregroundColor(.deckBone.opacity(0.8))
                                Spacer()
                            }
                            Slider(value: $deblytesSpeed, in: 1...50, step: 1)
                                .tint(.deckBrass)
                                .onChange(of: deblytesSpeed) { DeBlytesService.shared.downloadSpeedMBs = Float($0) }
                        }
                        .listRowBackground(Color.deckGraphite)
                    }
                    Toggle(isOn: $focusOnMeEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("FocusOnMe", systemImage: "eye")
                            Text("Prevents audio backgrounding. May require app restart.")
                                .font(.caption)
                                .foregroundColor(.deckBone.opacity(0.6))
                        }
                    }
                    .tint(.deckBrass)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                    .onChange(of: focusOnMeEnabled) { FocusOnMeService.shared.isEnabled = $0 }
                } header: {
                    Text("APPLICATIONS")
                } footer: {
                    Text("All modules are built-in. Enable individually above.")
                        .foregroundColor(.deckBone.opacity(0.6))
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundColor(.deckBone)
            .tint(.deckBrass)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("DONE") { dismiss() }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.deckBrass)
            }
        }
        .sheet(isPresented: $showingUpdates) {
            NavigationStack { UpdatesView() }
        }
    }
}

struct UpdatesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var download: DownloadedIPA?

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color.deckCharcoal.ignoresSafeArea()
            List {
                Section {
                    HStack {
                        Text("Installed version")
                        Spacer()
                        Text(appVersion).foregroundColor(.deckBone.opacity(0.6))
                    }
                    .listRowBackground(Color.deckGraphite)
                } header: {
                    Text("THIS DEVICE")
                }

                Section {
                    Button {
                        Task { await getLatestIPA() }
                    } label: {
                        HStack {
                            Label("Get Latest IPA", systemImage: "arrow.down.circle.fill")
                            Spacer()
                            if isWorking { ProgressView().tint(.deckBrass) }
                        }
                    }
                    .disabled(isWorking)
                    .foregroundColor(.deckBone)
                    .listRowBackground(Color.deckGraphite)
                } header: {
                    Text("UPDATES")
                } footer: {
                    Text("Downloads the latest stable GitHub Release and opens the share sheet. It does not install the IPA automatically.")
                        .foregroundColor(.deckBone.opacity(0.6))
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundColor(.deckBone)
            .tint(.deckBrass)
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("DONE") { dismiss() }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.deckBrass)
            }
        }
        .alert("Update unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try again later.")
        }
        .sheet(item: $download) { item in
            ShareSheet(items: [item.url]) {
                try? FileManager.default.removeItem(at: item.url)
                download = nil
            }
        }
        .onDisappear {
            if let url = download?.url { try? FileManager.default.removeItem(at: url) }
            download = nil
        }
    }

    private func getLatestIPA() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            download = try await UpdateService.downloadLatestIPA()
        } catch let error as UpdateService.UpdateError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = UpdateService.UpdateError.downloadFailed.localizedDescription
        }
    }
}
