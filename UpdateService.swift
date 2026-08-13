import Foundation
import Combine
import UIKit

struct DownloadedIPA: Identifiable {
    let id = UUID()
    let url: URL
}

struct UpdateService {
    enum UpdateError: LocalizedError {
        case invalidResponse
        case noRelease
        case missingIPA
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "GitHub returned an invalid update response. Try again later."
            case .noRelease: return "No stable GitHub Release is available yet."
            case .missingIPA: return "The latest Release does not include MusicPlayer.ipa."
            case .downloadFailed: return "The latest IPA could not be downloaded. Check your connection and try again."
            }
        }
    }

    struct Release: Decodable {
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    static let repository = "glitchFling/MusicPlayer"
    static let assetName = "MusicPlayer.ipa"

    static func downloadLatestIPA() async throws -> DownloadedIPA {
        let release = try await latestStableRelease()
        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            throw UpdateError.missingIPA
        }
        let (temporaryURL, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicPlayer-\(UUID().uuidString).ipa")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return DownloadedIPA(url: destination)
    }

    private static func latestStableRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases") else {
            throw UpdateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MusicPlayer/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            throw UpdateError.noRelease
        }
        return release
    }
}
