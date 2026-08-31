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
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents
            .appendingPathComponent("MusicPlayer", isDirectory: true)
            .appendingPathComponent("Presets", isDirectory: true)
        migratePrivatePresetsIfNeeded()
        reload()
    }

    private func migratePrivatePresetsIfNeeded() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicPlayer", isDirectory: true)
            .appendingPathComponent("Presets", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in files where source.pathExtension == "prst" {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }

    func presetsDirectoryURL() -> URL { directory }

    func reload() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { presets = []; return }
        presets = files.filter { $0.pathExtension == "prst" }.compactMap { try? Data(contentsOf: $0) }.compactMap { try? PropertyListDecoder().decode(Preset.self, from: $0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadExternalPreset(from url: URL) throws -> Preset {
        guard url.pathExtension.lowercased() == "prst" else { throw PresetError.invalidFile }
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(Preset.self, from: data)
    }

    enum PresetError: LocalizedError {
        case invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "That file is not a valid MusicPlayer .prst preset."
            }
        }
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
