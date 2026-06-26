import Foundation
import AppKit
import SwiftUI

@MainActor
class UpdateManager: ObservableObject {
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?
    @Published var hasUpdate = false

    @AppStorage("checkForUpdates") var checkForUpdates = true

    static let currentVersion = "1.6.2"
    private let repo = "neko1chau/Spotoast"

    func checkForUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            latestVersion = remote
            releaseNotes = release.body
            hasUpdate = isNewer(remote: remote, local: Self.currentVersion)

            if hasUpdate {
                let arch = currentArch()
                downloadURL = release.assets
                    .first { $0.name.contains(arch) }
                    .map { URL(string: $0.browserDownloadUrl) } ?? nil
            }
        } catch {
            self.error = "Failed to check for updates: \(error.localizedDescription)"
        }
    }

    func downloadAndInstall() async {
        guard let url = downloadURL else { return }
        isDownloading = true
        downloadProgress = 0
        error = nil
        defer { isDownloading = false }

        do {
            let (localURL, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Spotoast-update.dmg")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: localURL, to: dest)
            NSWorkspace.shared.open(dest)
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
        }
    }

    private func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "universal"
        #endif
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

private struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}
