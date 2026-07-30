import Foundation

struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let artist: String?
    let fileURL: URL
    let artworkURL: URL?
    let dateAdded: Date

    init(id: UUID = UUID(), title: String, artist: String? = nil, fileURL: URL, artworkURL: URL? = nil, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileURL = fileURL
        self.artworkURL = artworkURL
        self.dateAdded = dateAdded
    }

    init(fileURL: URL) {
        self.init(title: fileURL.deletingPathExtension().lastPathComponent, fileURL: fileURL)
    }
}
