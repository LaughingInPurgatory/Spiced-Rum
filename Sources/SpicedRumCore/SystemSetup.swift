import Foundation

public enum SystemSetup {
    public static func rosettaAvailable() async -> Bool {
        do { _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"]); return true }
        catch { return false }
    }

    public static func downloadHomebrewInstaller(into folder: URL) async throws -> URL {
        struct Release: Decodable { let assets: [EngineAsset] }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")!)
        request.setValue("Spiced-Rum/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("Cannot fetch Homebrew's installer. Retry or use the official Homebrew installation page.") }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") && $0.verifiedDownload }), let digest = asset.digest,
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com", asset.browser_download_url.path.hasPrefix("/Homebrew/brew/releases/download/") else {
            throw RumError.message("Homebrew has no checksum-backed .pkg installer in its current release. Follow docs.brew.sh/Installation, then return to Spiced-Rum.")
        }
        let (download, downloadResponse) = try await URLSession.shared.download(from: asset.browser_download_url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("Homebrew installer download failed. Retry when the connection is available.") }
        try EngineInstaller.verify(download, digest: digest)
        let destination = folder.appendingPathComponent("Homebrew-" + UUID().uuidString + ".pkg")
        try FileManager.default.copyItem(at: download, to: destination)
        return destination
    }
}
