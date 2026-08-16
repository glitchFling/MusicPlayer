import AppIntents
import Foundation

// MARK: - Play Song

struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Song"
    static var description = IntentDescription("Adds an audio file to your current session if it isn't already stored.")

    @Parameter(title: "Audio File", supportedContentTypes: [.fileURL])
    var audioFile: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let fileURL = audioFile.fileURL else {
            return .result()
        }

        let library = SongLibrary.shared
        await library.importSong(from: fileURL)

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
    func perform() async throws -> some ProvidesDialog {
        try await requestConfirmation(
            result: .result(),
            dialog: "This will Clear all your songs in the Session, are you sure you want to Clear all songs?"
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