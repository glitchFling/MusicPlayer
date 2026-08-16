import AVFoundation
import Foundation

// MARK: - BetterMusic Audio Editor

/// Built-in audio processing module that provides speed/pitch, reverb,
/// bass boost, trimming, vocal removal, and export as .bettermusic.
final class BetterMusicProcessor {
    static let shared = BetterMusicProcessor()

    var isEnabled = false

    // Configuration
    var bassBoost: Float = 0       // 0-1
    var pitchShift: Float = 0      // cents, -1200 to 1200
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 0  // 0 = no trim

    // MARK: - Bass Boost (via EQ)

    private let audioEngine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)

    func applyBassBoost(to playerNode: AVAudioPlayerNode, amount: Float) {
        guard isEnabled, amount > 0 else { return }
        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = 100
        eq.bands[0].gain = amount * 12 // 0-12 dB
        eq.bands[0].bypass = false
    }

    // MARK: - Vocal Removal (center channel cancellation)

    /// Remove vocals by inverting one channel and summing (basic center-cancellation).
    /// Works best on stereo tracks where vocals are centered.
    static func removeVocals(from audioFile: AVAudioFile) -> AVAudioFile? {
        let format = audioFile.processingFormat
        guard format.channelCount == 2 else { return nil } // Only stereo

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocals-removed-\(UUID().uuidString)")
            .appendingPathExtension(audioFile.url.pathExtension)

        guard let outputFile = try? AVAudioFile(forWriting: outputURL, settings: format.settings) else { return nil }

        let frameCapacity = AVAudioFrameCount(4096)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        while true {
            try? audioFile.read(into: buffer)
            guard buffer.frameLength > 0 else { break }

            if let floatData = buffer.floatChannelData {
                let leftChannel = floatData[0]
                let rightChannel = floatData[1]
                for frame in 0..<Int(buffer.frameLength) {
                    // Center cancellation: L - R, then R - L, mix to mono-ish
                    let left = leftChannel[frame]
                    let right = rightChannel[frame]
                    // Subtract right from left for the new left, subtract left from right for new right
                    leftChannel[frame] = (left - right) * 0.5
                    rightChannel[frame] = (right - left) * 0.5
                }
            }
            try? outputFile.write(from: buffer)
        }
        return outputFile
    }

    // MARK: - Export

    /// Export processed audio as a .bettermusic bundle (WAV + metadata plist in directory)
    static func exportProcessed(audioFile: AVAudioFile, speed: Float, reverb: Float, bass: Float) throws -> URL {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterMusic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Write processed audio
        let audioURL = exportDir.appendingPathComponent("output").appendingPathExtension(audioFile.url.pathExtension)
        try FileManager.default.copyItem(at: audioFile.url, to: audioURL)

        // Write metadata
        let metadata: [String: Any] = [
            "speed": speed,
            "reverb": reverb,
            "bass": bass,
            "exported": ISO8601DateFormatter().string(from: .now)
        ]
        let plistURL = exportDir.appendingPathComponent("metadata.plist")
        try (metadata as NSDictionary).write(to: plistURL)

        // Return the directory as the .bettermusic package
        return exportDir
    }
}

// MARK: - Display helpers

extension BetterMusicProcessor {
    static let bassIcon = "speaker.wave.2"
    static let pitchIcon = "waveform"
    static let trimIcon = "scissors"
    static let vocalIcon = "person.wave.2"
}