import SwiftUI
import UIKit

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.32)).foregroundColor(.deckBrass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.deckGraphite)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.deckHairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
