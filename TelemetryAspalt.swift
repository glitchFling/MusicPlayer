import Combine
import Foundation

/// Local-only session telemetry ("Aspalt").
/// Writes one .log file per app session into Documents/Telemetry/.
/// Never touches the network. Fully disabled when toggled off in Settings.
@MainActor
final class TelemetryAspalt: ObservableObject {
    static let shared = TelemetryAspalt()

    /// Master switch, persisted to UserDefaults. Checked before every write.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "telemetry_enabled") }
    }

    private let fileManager = FileManager.default
    private var logFileURL: URL?
    private var buffer: [String] = []
    private let timestampFormatter: DateFormatter

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "telemetry_enabled")
        // Default to ON on first launch (bool(forKey:) returns false when unset).
        if UserDefaults.standard.object(forKey: "telemetry_enabled") == nil {
            isEnabled = true
        }

        timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    // MARK: - Session lifecycle

    /// Call once at app launch. Begins a fresh .log file for this session.
    func beginSession() {
        guard isEnabled else { return }

        let dir = telemetryDirectory()
        let stamp = DateFormatter().then {
            $0.dateFormat = "yyyy-MM-dd-HHmmss"
        }.string(from: .now)
        let url = dir.appendingPathComponent("session-\(stamp).log")

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let header = """
            # MusicPlayer Telemetry (Aspalt) — local session log
            # Started: \(timestampFormatter.string(from: .now))
            # Nothing in this file leaves your device.
            # Delete any time: Files app → MusicPlayer → Telemetry
            """
            try header.write(to: url, atomically: true, encoding: .utf8)
            logFileURL = url
            log("session began")
        } catch {
            logFileURL = nil
        }
    }

    /// Flushes and closes the current session log. Call when entering background.
    func endSession() {
        guard isEnabled else { return }
        log("session ended")
        flush()
        logFileURL = nil
    }

    // MARK: - Logging

    /// Appends a timestamped event. No-op when telemetry is disabled.
    func log(_ event: String) {
        guard isEnabled else { return }
        let line = "[\(timestampFormatter.string(from: .now))] \(event)"
        buffer.append(line)
        print("🔭 \(line)")

        // Persist in small batches so a crash loses at most a few lines.
        if buffer.count >= 8 { flush() }
    }

    // MARK: - File management

    /// All saved session logs, newest first.
    func savedLogs() -> [URL] {
        let dir = telemetryDirectory()
        let contents = (try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "log" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }
    }

    /// Deletes every session log.
    func clearAllLogs() {
        for url in savedLogs() { try? fileManager.removeItem(at: url) }
    }

    // MARK: - Private

    private func flush() {
        guard !buffer.isEmpty, let url = logFileURL else { return }
        let chunk = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(chunk.utf8))
        }
    }

    private func telemetryDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetry", isDirectory: true)
    }
}

private extension DateFormatter {
    func then(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}
