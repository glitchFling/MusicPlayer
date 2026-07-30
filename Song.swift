import Foundation

struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let fileURL: URL
    let dateAdded: Date

    init(id: UUID = UUID(), title: String, fileURL: URL, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.dateAdded = dateAdded
    }

    init(fileURL: URL) {
        self.init(
            title: fileURL.deletingPathExtension().lastPathComponent,
            fileURL: fileURL
        )
    }
}
