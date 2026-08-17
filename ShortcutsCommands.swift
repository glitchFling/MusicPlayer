import AppIntents
import Foundation

// MARK: - Play Song

struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Song"
    static var description = IntentDescription("Adds an audio file to your current session if it isn't already stored.")

    @Parameter(title: "Audio File")
    var audioFile: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        let library = SongLibrary.shared

        // Copy file data to a stable temp URL before importing
        let data = audioFile.data
        let ext = audioFile.fileURL?.pathExtension ?? "mp3"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tempURL)
        await library.importSong(from: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        if let song = library.songs.first(where: { !SessionModel.shared.contains($0) }) {
            SessionModel.shared.addToSession(song)
        } else if let song = library.songs.first {
            SessionModel.shared.addToSession(song)
        }

        return .result()
    }
}

// MARK: - Clear All Songs

struct ClearAllSongsIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear All Songs"
    static var description = IntentDescription("Clears all songs from your current session.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await requestConfirmation(
            result: .result(),
            dialog: IntentDialog("This will Clear all your songs in the Session, are you sure you want to Clear all songs?")
        )

        SessionModel.shared.clear()

        return .result(dialog: "All songs cleared.")
    }
}

// MARK: - Shortcuts Provider

struct MusicPlayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play a song with \(.applicationName)",
                "Add a song to \(.applicationName)",
                "Import audio into \(.applicationName)"
            ],
            shortTitle: "Play Song",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: ClearAllSongsIntent(),
            phrases: [
                "Clear all songs in \(.applicationName)",
                "Clear the session in \(.applicationName)"
            ],
            shortTitle: "Clear All Songs",
            systemImageName: "trash"
        )
    }
}