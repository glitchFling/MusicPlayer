import AVFoundation
import Foundation

// MARK: - VolumeWarning

/// Detects loud audio passages and provides auto-skip and auto-volume features.
final class VolumeWarningService: ObservableObject {
    static let shared = VolumeWarningService()

    @Published var isEnabled = false
    @Published var autoSkip = true
    @Published var autoWarn = true
    @Published var thresholdDB: Float = 20.0 // 10-200 dB range

    /// Song IDs flagged as loud
    @Published private(set) var loudSongIDs: Set<UUID> = []

    // MARK: - Marking

    func markAsLoud(_ songID: UUID) {
        loudSongIDs.insert(songID)
    }

    func markAsQuiet(_ songID: UUID) {
        loudSongIDs.remove(songID)
    }

    func isLoud(_ songID: UUID) -> Bool {
        loudSongIDs.contains(songID)
    }

    // MARK: - Detection (peak amplitude analysis)

    /// Analyze audio file for peak loudness.
    /// Returns peak dB value for the file.
    static func analyzePeakDB(for url: URL) -> Float? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        let frameCapacity = AVAudioFrameCount(8192)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        var peak: Float = 0
        while true {
            try? audioFile.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            guard let floatData = buffer.floatChannelData else { continue }

            let channelCount = Int(format.channelCount)
            for channel in 0..<channelCount {
                let data = floatData[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let absVal = abs(data[frame])
                    if absVal > peak { peak = absVal }
                }
            }
        }

        guard peak > 0 else { return nil }
        return 20 * log10(peak) // Convert to dB
    }

    /// Check if auto-volume should be applied (reduces volume to 25%)
    static let autoVolumeFactor: Float = 0.25
}