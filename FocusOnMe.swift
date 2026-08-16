import AVFoundation
import Foundation

// MARK: - FocusOnMe

/// Prevents audio from backgrounding by configuring AVAudioSession to
/// require explicit foreground interaction. When enabled, audio stops
/// when the app enters the background.
final class FocusOnMeService: ObservableObject {
    static let shared = FocusOnMeService()

    @Published var isEnabled = false {
        didSet { apply() }
    }

    private func apply() {
        let session = AVAudioSession.sharedInstance()
        do {
            if isEnabled {
                // .soloAmbient disables background playback
                try session.setCategory(.soloAmbient, mode: .default)
            } else {
                // Restore normal playback category
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Silently fail — session will use previous category
        }
    }
}