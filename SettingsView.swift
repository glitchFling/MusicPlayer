import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingUpdates = false
    @AppStorage("virtuallist_enabled") private var virtualListEnabled = false

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
                } header: {
                    Text("APPLICATIONS")
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
