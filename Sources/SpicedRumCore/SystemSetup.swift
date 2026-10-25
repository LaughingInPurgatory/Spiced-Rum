import Foundation

private struct HomebrewGPTKInfo: Decodable {
    struct Cask: Decodable {
        let full_token: String
        let version: String
        let installed: String?
        let url: URL
    }
    let casks: [Cask]
}

public struct HomebrewGPTKPackage: Sendable {
    public let version: String
    public let installedVersion: String?
}

private struct HomebrewTrustInfo: Decodable {
    let taps: [String]
    let casks: [String]
}

public enum HomebrewGPTK {
    public static let cask = "gcenx/wine/game-porting-toolkit"
    // Keep aligned with the current major version linked from Apple's GPTK page.
    public static let currentAppleMajorVersion = 4

    public static func isTrusted(using brew: URL) async throws -> Bool {
        let output = try await ProcessRunner.capture(brew, ["trust", "--json=v1"], environment: Dependencies.hostEnvironment)
        guard let data = output.data(using: .utf8),
              let trust = try? JSONDecoder().decode(HomebrewTrustInfo.self, from: data) else {
            throw RumError.message("Homebrew could not report its trusted taps. Update Homebrew, then try again.")
        }
        return trust.casks.contains(cask) || trust.taps.contains("gcenx/wine")
    }

    public static func trust(using brew: URL, directory: URL, log: URL) async throws {
        try await ProcessRunner.run(brew, ["trust", "--cask", cask], environment: Dependencies.hostEnvironment,
                                   directory: directory, log: log, label: "Trusting Gcenx GPTK cask")
    }

    public static func packageInfo(using brew: URL) async throws -> HomebrewGPTKPackage {
        let output = try await ProcessRunner.capture(brew, ["info", "--json=v2", "--cask", cask], environment: Dependencies.hostEnvironment)
        guard let data = output.data(using: .utf8),
              let info = try? JSONDecoder().decode(HomebrewGPTKInfo.self, from: data),
              let package = info.casks.first,
              package.full_token == cask,
              package.url.host?.lowercased() == "github.com",
              package.url.path.lowercased().hasPrefix("/gcenx/game-porting-toolkit/releases/download/"),
              !package.version.isEmpty else {
            throw RumError.message("Homebrew did not return a valid Gcenx Game Porting Toolkit package. Check the Homebrew tap and try again.")
        }
        return HomebrewGPTKPackage(version: package.version, installedVersion: package.installed)
    }

    public static func matchesAppleEvaluation(_ homebrewVersion: String, evaluationVersion: String?) -> Bool {
        guard let evaluationVersion else { return false }
        return sameVersion(homebrewVersion, evaluationVersion: evaluationVersion)
            && isCurrentAppleVersion(homebrewVersion)
            && isCurrentAppleVersion(evaluationVersion)
    }

    public static func sameVersion(_ lhs: String, evaluationVersion: String) -> Bool {
        lhs.localizedStandardCompare(evaluationVersion) == .orderedSame
    }

    public static func isCurrentAppleVersion(_ version: String) -> Bool {
        let major = Int(version.prefix(while: { $0.isNumber }))
        return major == currentAppleMajorVersion
    }
}

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
