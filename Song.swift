import Foundation

import Foundation

public struct Song: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String?
    public let fileURL: URL
    public let artworkURL: URL?
    public let dateAdded: Date

    public init(id: UUID = UUID(), title: String, artist: String? = nil, fileURL: URL, artworkURL: URL? = nil, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileURL = fileURL
        self.artworkURL = artworkURL
        self.dateAdded = dateAdded
    }

    public init(fileURL: URL) {
        self.init(title: fileURL.deletingPathExtension().lastPathComponent, fileURL: fileURL)
    }
}
