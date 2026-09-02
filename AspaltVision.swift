import Core
import UIKit
import Vision

/// AspaltVision — on-device artwork ANALYSIS (no generation).
/// Uses Apple's built-in Vision framework: zero download, fully offline.
/// Results are written into the Aspalt telemetry log.
@MainActor
final class AspaltVision {
    static let shared = AspaltVision()

    /// Analyzes a song's artwork (if any) and logs the description.
    /// Gated on the telemetry master switch.
    func analyzeAndLog(song: Song) {
        guard TelemetryAspalt.shared.isEnabled else { return }

        guard let artworkURL = song.artworkURL else {
            TelemetryAspalt.shared.log("vision: \"\(song.title)\" has no artwork")
            return
        }

        Task.detached(priority: .utility) {
            let summary = await Self.describeImage(at: artworkURL)
            await MainActor.run {
                TelemetryAspalt.shared.log("vision: \"\(song.title)\" — \(summary)")
            }
        }
    }

    // MARK: - Analysis

    private nonisolated static func describeImage(at url: URL) async -> String {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            return "unreadable image"
        }

        let pixelInfo = "\(Int(image.size.width))×\(Int(image.size.height))"
        let dominant = dominantColor(of: image)

        let labels: [String] = await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                let confident = observations
                    .filter { $0.confidence > 0.3 }
                    .prefix(5)
                    .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
                continuation.resume(returning: Array(confident))
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .utility).async {
                do {
                    try handler.perform([request])
                    // The request completion handler resumed the continuation.
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }

        let labelPart = labels.isEmpty ? "no confident labels" : labels.joined(separator: ", ")
        return "\(pixelInfo), \(dominant), \(labelPart)"
    }

    /// Downsamples to a single pixel to get an average color, then names it.
    private nonisolated static func dominantColor(of image: UIImage) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
        guard let tiny = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1)) }
            .cgImage,
            let data = tiny.dataProvider?.data,
            let byte = (data as NSData).bytes.assumingMemoryBound(to: UInt8.self) else {
            return "unknown tone"
        }

        let r = CGFloat(byte[0]) / 255
        let g = CGFloat(byte[1]) / 255
        let b = CGFloat(byte[2]) / 255
        let brightness = (r + g + b) / 3

        var hue: CGFloat = 0, saturation: CGFloat = 0, alpha: CGFloat = 0, white: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &white, alpha: &alpha)

        let tone: String
        if saturation < 0.15 {
            tone = brightness > 0.75 ? "light gray" : (brightness < 0.25 ? "near black" : "gray")
        } else {
            let names = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta"]
            let index = Int(round(hue * 8)) % 8
            tone = names[index] + (brightness < 0.35 ? " (dark)" : "")
        }
        return "dominant: \(tone)"
    }
}
