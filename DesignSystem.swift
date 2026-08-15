import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DeckIconButtonStyle: ButtonStyle {
    var accent = false
    var accentColor: Color = .deckBrass

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(accent ? .deckCharcoal : .deckBone)
            .frame(width: 52, height: 52)
            .background(accent ? accentColor : Color.deckGraphite)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.deckHairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

struct DeckPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(Color.deckGraphite.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.deckHairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}


extension Color {
    static let deckCharcoal = Color(red: 0.106, green: 0.098, blue: 0.090)
    static let deckGraphite = Color(red: 0.180, green: 0.169, blue: 0.145)
    static let deckBone = Color(red: 0.929, green: 0.902, blue: 0.839)
    static let deckBrass = Color(red: 0.776, green: 0.545, blue: 0.235)
    static let deckEmber = Color(red: 0.651, green: 0.239, blue: 0.200)
    static let deckHairline = Color(red: 0.290, green: 0.267, blue: 0.235)
}

enum ArtworkAccent {
    static let fallback = Color.deckBrass

    static func rgb(for url: URL?) -> (Double, Double, Double)? {
        guard let url, let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else { return nil }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var buckets = Array(repeating: (count: 0, red: 0.0, green: 0.0, blue: 0.0, saturation: 0.0, brightness: 0.0), count: 24)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let maxValue = max(red, green, blue)
            let minValue = min(red, green, blue)
            let delta = maxValue - minValue
            let saturation = maxValue == 0 ? 0 : delta / maxValue
            guard maxValue >= 0.18, saturation >= 0.12 else { continue }
            var hue: Double
            if delta == 0 { hue = 0 }
            else if maxValue == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxValue == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bucketIndex = min(23, max(0, Int(hue * 24)))
            buckets[bucketIndex].count += 1
            buckets[bucketIndex].red += red
            buckets[bucketIndex].green += green
            buckets[bucketIndex].blue += blue
            buckets[bucketIndex].saturation += saturation
            buckets[bucketIndex].brightness += maxValue
        }

        guard let winner = buckets.max(by: { lhs, rhs in
            Double(lhs.count) * (lhs.count == 0 ? 0 : lhs.saturation / Double(lhs.count)) <
            Double(rhs.count) * (rhs.count == 0 ? 0 : rhs.saturation / Double(rhs.count))
        }), winner.count > 0 else { return nil }
        let count = Double(winner.count)
        let red = min(0.9, max(0.35, winner.red / count))
        let green = min(0.9, max(0.35, winner.green / count))
        let blue = min(0.9, max(0.35, winner.blue / count))
        return (red, green, blue)
    }
}

@MainActor
final class ArtworkAccentStore: ObservableObject {
    @Published private(set) var color = ArtworkAccent.fallback
    private var cache: [UUID: Color] = [:]
    private var generation = 0

    func update(for song: Song?) {
        guard let song else {
            color = ArtworkAccent.fallback
            return
        }
        if let cached = cache[song.id] {
            color = cached
            return
        }
        generation += 1
        let currentGeneration = generation
        let artworkURL = song.artworkURL
        Task.detached(priority: .utility) {
            let rgb = ArtworkAccent.rgb(for: artworkURL)
            await MainActor.run {
                let resolved = rgb.map { Color(red: $0.0, green: $0.1, blue: $0.2) } ?? ArtworkAccent.fallback
                self.cache[song.id] = resolved
                guard self.generation == currentGeneration else { return }
                self.color = resolved
            }
        }
    }
}


struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(gradient)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .cornerRadius(7)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct DeckButtonStyle: ButtonStyle {
    var accent = false
    var accentColor: Color = .deckBrass

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundColor(accent ? .deckCharcoal : .deckBone)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(accent ? accentColor : Color.deckGraphite)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.deckHairline, lineWidth: 1))
            .cornerRadius(7)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}


struct ReelView: View {
    var isSpinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(Color.deckHairline, lineWidth: 12)
            Circle().stroke(Color.deckBrass.opacity(0.8), lineWidth: 2)
            ForEach(0..<6, id: \.self) { index in
                Capsule().fill(Color.deckBone.opacity(0.75)).frame(width: 3, height: 22)
                    .offset(y: -28).rotationEffect(.degrees(Double(index) * 60))
            }
            Circle().fill(Color.deckBrass).frame(width: 13, height: 13)
        }
        .rotationEffect(.degrees(rotation))
        .onChange(of: isSpinning) { spinning in
            guard spinning, !reduceMotion else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { rotation += 360 }
        }
        .accessibilityHidden(true)
    }
}
