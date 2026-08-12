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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(accent ? .deckCharcoal : .deckBone)
            .frame(width: 52, height: 52)
            .background(accent ? Color.deckBrass : Color.deckGraphite)
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

struct DeckButtonStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundColor(accent ? .deckCharcoal : .deckBone)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(accent ? Color.deckBrass : Color.deckGraphite)
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
