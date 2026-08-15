import Combine
import Foundation

@MainActor
final class PresetStore: ObservableObject {
    struct Preset: Identifiable, Codable, Equatable {
        let name: String
        let speed: Float
        let reverb: Float
        var id: String { name }
    }

    static let shared = PresetStore()
    @Published private(set) var presets: [Preset] = []
    private let fileManager = FileManager.default
    private let directory: URL

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("MusicPlayer", isDirectory: true).appendingPathComponent("Presets", isDirectory: true)
        reload()
    }

    func reload() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { presets = []; return }
        presets = files.filter { $0.pathExtension == "prst" }.compactMap { try? Data(contentsOf: $0) }.compactMap { try? PropertyListDecoder().decode(Preset.self, from: $0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ preset: Preset) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = Self.sanitized(preset.name) + ".prst"
        let data = try PropertyListEncoder().encode(preset)
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        reload()
    }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
