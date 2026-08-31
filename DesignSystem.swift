import Core
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
        let size = 48
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var candidates: [(score: Double, red: Double, green: Double, blue: Double)] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard saturation >= 0.18, luminance >= 0.12, luminance <= 0.78 else { continue }
            let score = saturation * 0.7 + (1 - abs(luminance - 0.42)) * 0.3
            candidates.append((score, red, green, blue))
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.score > $1.score }
        let sample = candidates.prefix(max(1, candidates.count / 12))
        let count = Double(sample.count)
        let red = sample.reduce(0) { $0 + $1.red } / count
        let green = sample.reduce(0) { $0 + $1.green } / count
        let blue = sample.reduce(0) { $0 + $1.blue } / count
        return (red, green, blue)
    }
}

struct ArtworkPalette {
    let accent: Color
    let background: Color
    let secondary: Color
}

extension ArtworkPalette {
    static let fallback = ArtworkPalette(accent: .deckBrass, background: .deckCharcoal, secondary: .deckGraphite)
}

func artworkPalette(from rgb: (Double, Double, Double)?) -> ArtworkPalette {
    guard let rgb else { return .fallback }
    let base = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    return ArtworkPalette(accent: base, background: base.opacity(0.52), secondary: base.opacity(0.22))
}

@MainActor
final class ArtworkAccentStore: ObservableObject {
    @Published private(set) var palette = ArtworkPalette.fallback
    var color: Color { palette.accent }
    private var cache: [UUID: ArtworkPalette] = [:]
    private var generation = 0

    func update(for song: Song?) {
        guard let song else {
            palette = .fallback
            return
        }
        if let cached = cache[song.id] {
            palette = cached
            return
        }
        generation += 1
        let currentGeneration = generation
        let artworkURL = song.artworkURL
        Task.detached(priority: .utility) {
            let rgb = ArtworkAccent.rgb(for: artworkURL)
            await MainActor.run {
                let resolved = artworkPalette(from: rgb)
                self.cache[song.id] = resolved
                guard self.generation == currentGeneration else { return }
                self.palette = resolved
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
