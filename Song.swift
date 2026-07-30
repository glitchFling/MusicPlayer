import Foundation

struct Song: Identifiable {
    let id = UUID()
    let fileName: String // e.g., "song1.mp3"
    var title: String {
        return fileName.replacingOccurrences(of: ".mp3", with: "").capitalized
    }
}
