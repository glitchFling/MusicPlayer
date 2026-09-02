import Foundation
import MLXLMCommon
import MLXLLM

/// AspaltAI — fully on-device LLM via MLX Swift.
/// No network calls at inference time (model is downloaded once, on explicit request).
/// Nothing the user does ever leaves the device.
@MainActor
public final class AspaltAI: ObservableObject {
    public static let shared = AspaltAI()

    /// The model we ship support for. ~1 GB, 4-bit, from mlx-community.
    public static let modelID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    // MARK: - State

    @Published public private(set) var isModelDownloaded = false
    @Published public private(set) var isPreparing = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var lastError: String?

    private var container: LMContainer?

    private init() {
        isModelDownloaded = Self.modelExistsOnDisk()
    }

    // MARK: - Model storage

    private static var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AspaltAI", isDirectory: true)
    }

    private static func modelExistsOnDisk() -> Bool {
        let marker = modelDirectory.appendingPathComponent("downloaded.marker")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    /// Downloads the model to Documents/AspaltAI. One-time, user-initiated, shows progress.
    public func downloadModel() async {
        guard !isModelDownloaded, !isPreparing else { return }
        isPreparing = true
        lastError = nil
        defer { isPreparing = false }

        do {
            try FileManager.default.createDirectory(
                at: Self.modelDirectory, withIntermediateDirectories: true
            )

            // ModelFactory from MLXLMCommon handles HF download with progress.
            let config = ModelConfiguration(id: Self.modelID)
            _ = try await LLMModelFactory.shared.loadContainer(configuration: config)

            // Mark success so we skip re-download on next launch.
            let marker = Self.modelDirectory.appendingPathComponent("downloaded.marker")
            try Data().write(to: marker)
            isModelDownloaded = true
        } catch {
            lastError = "Model download failed: \(error.localizedDescription)"
        }
    }

    /// Frees model memory when not needed.
    public func unload() {
        container = nil
    }

    // MARK: - Generation

    /// Loads the model (if needed) and generates a completion for the prompt.
    /// Fully local: MLX runs on the Neural Engine / GPU, zero network.
    public func generate(_ prompt: String, maxTokens: Int = 300) async throws -> String {
        if container == nil {
            guard isModelDownloaded else {
                throw AspaltError.modelNotDownloaded
            }
            isPreparing = true
            defer { isPreparing = false }
            let config = ModelConfiguration(id: Self.modelID)
            container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        }

        guard let container else { throw AspaltError.modelUnavailable }

        let messages: [Message] = [
            .system("You are Aspalt, a concise assistant built into a music player app. Answer briefly."),
            .user(prompt)
        ]
        let input = try await container.processor.prepare(input: UserInput(messages: messages))
        let result = try await container.generate(input: input, parameters: .init(maxTokens: maxTokens))
        return result.output
    }

    /// Convenience: summarize an Aspalt telemetry log's contents.
    public func summarizeTelemetryLog(_ logText: String) async throws -> String {
        let trimmed = String(logText.suffix(4000)) // keep within context budget
        return try await generate(
            "Summarize this music player session log in 3 short bullet points. Facts only:\n\n\(trimmed)"
        )
    }
}

public enum AspaltError: LocalizedError {
    case modelNotDownloaded
    case modelUnavailable

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "The Aspalt AI model hasn't been downloaded yet. Enable it in Settings first."
        case .modelUnavailable: return "The AI model could not be loaded."
        }
    }
}
