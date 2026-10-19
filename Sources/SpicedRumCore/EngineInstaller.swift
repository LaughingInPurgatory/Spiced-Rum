import Foundation
import CryptoKit

public struct EngineAsset: Decodable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let size: Int64
    public var digest: String?
    public let browser_download_url: URL
    public var created_at: String? = nil
    public var releaseTag: String? = nil
    public var releaseName: String? = nil
    public var releaseNotes: String? = nil
    public var verifiedDownload: Bool { digest?.hasPrefix("sha256:") == true }
    public var requiresSikarugirLauncher: Bool { name.contains("WineSikarugir11.") }

    public func displayName(in feed: EngineFeed) -> String {
        guard feed == .whisky else { return name }
        return releaseName ?? releaseTag ?? name
    }

    public func installedName(in feed: EngineFeed) -> String {
        guard feed == .whisky else {
            return name.replacingOccurrences(of: ".tar.xz", with: "").replacingOccurrences(of: ".tar.gz", with: "")
        }
        return "Whisky community runtime \(releaseTag ?? name)"
    }

    public var reportsSteamLoginIssue: Bool {
        let notes = releaseNotes?.lowercased() ?? ""
        return notes.contains("steam's login stalls") || notes.contains("steam login stalls")
    }

    public var requiresAppleGPTKPayload: Bool {
        releaseName?.localizedCaseInsensitiveContains("GPTK") == true
    }
}

struct EngineRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let assets: [EngineAsset]
}

public struct EngineReleasePage {
    public let assets: [EngineAsset]
    public let nextPage: Int?
}

public struct DXVKPackage: Identifiable, Hashable {
    public let title: String
    public let folder: URL
    public let releaseTag: String?
    public var id: String { folder.path }
}

private struct DXVKPackageReceipt: Codable {
    let asset: EngineAsset
    let sha256: String
    let publisherChecksumVerified: Bool
}

public enum EngineFeed: String, CaseIterable, Identifiable {
    case wineHQ = "Wine Staging / Stable / Devel"
    case sikarugir = "Sikarugir engines"
    case whisky = "Whisky community Wine Libraries"
    public var id: String { rawValue }
    public var repository: String {
        switch self {
        case .wineHQ: return "Gcenx/macOS_Wine_builds"
        case .sikarugir: return "Sikarugir-App/Engines"
        case .whisky: return "frankea/Whisky"
        }
    }
}

public enum EngineInstaller {
    public static func releases(_ feed: EngineFeed, page: Int = 1) async throws -> EngineReleasePage {
        guard page > 0 else { throw RumError.message("Invalid engine history page.") }
        let url = URL(string: "https://api.github.com/repos/\(feed.repository)/releases?per_page=12&page=\(page)")!
        var request = URLRequest(url: url); request.setValue("Spiced-Rum/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("Cannot load engine releases. GitHub may be unavailable or rate limiting requests. Try again later.") }
        let releases = try JSONDecoder().decode([EngineRelease].self, from: data)
        return releasePage(releaseAssets(from: releases, feed: feed), feed: feed, page: page, link: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link"))
    }

    public static func dxvkReleases(page: Int = 1) async throws -> EngineReleasePage {
        guard page > 0 else { throw RumError.message("Invalid DXVK release history page.") }
        let url = URL(string: "https://api.github.com/repos/Gcenx/DXVK-macOS/releases?per_page=12&page=\(page)")!
        var request = URLRequest(url: url)
        request.setValue("Spiced-Rum/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RumError.message("Cannot load macOS DXVK releases. GitHub may be unavailable or rate limiting requests. Try again later.")
        }
        let releases = try JSONDecoder().decode([EngineRelease].self, from: data)
        let assets = releases.flatMap { release in
            release.assets.map { original -> EngineAsset in
                var asset = original
                asset.releaseTag = release.tag_name
                asset.releaseName = release.name
                asset.releaseNotes = release.body
                return asset
            }
        }
        return dxvkReleasePage(assets, page: page, link: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link"))
    }

    public static func supportsMacOSDXVK(_ runtime: Runtime) -> Bool {
        guard runtime.useRosetta, runtime.managedRoot != nil else { return false }
        let wineRoot = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: wineRoot.appendingPathComponent("lib/libMoltenVK.dylib").path)
    }

    static func isMacOSDXVKAsset(_ asset: EngineAsset) -> Bool {
        let name = asset.name.lowercased()
        let path = asset.browser_download_url.path.lowercased()
        return asset.browser_download_url.host?.lowercased() == "github.com"
            && path.hasPrefix("/gcenx/dxvk-macos/releases/download/")
            && name.contains("dxvk-macos") && name.hasSuffix(".tar.gz")
            && !name.contains("source") && !name.contains("linux")
    }

    static func dxvkReleasePage(_ assets: [EngineAsset], page: Int, link: String?) -> EngineReleasePage {
        let pageResult = releasePage(assets, page: page, link: link)
        return EngineReleasePage(assets: pageResult.assets.filter(isMacOSDXVKAsset), nextPage: pageResult.nextPage)
    }

    public static func installedDXVKPackages(for runtime: Runtime) -> [DXVKPackage] {
        guard let managedRoot = runtime.managedRoot else { return [] }
        let graphics = managedRoot.appendingPathComponent("graphics", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: graphics, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
        return folders.compactMap { folder in
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let nested = folder.appendingPathComponent("package", isDirectory: true)
            let package = FileManager.default.fileExists(atPath: nested.appendingPathComponent("x64/d3d11.dll").path) ? nested : folder
            guard (try? Wine.validateDXVK(package)) != nil else { return nil }
            let title = folder.lastPathComponent.hasPrefix("DXVK-") ? String(folder.lastPathComponent.dropFirst(5)) : folder.lastPathComponent
            let receiptURL = folder.appendingPathComponent("download-receipt.json")
            let receipt = (try? Data(contentsOf: receiptURL)).flatMap { try? JSONDecoder().decode(DXVKPackageReceipt.self, from: $0) }
            return DXVKPackage(title: title, folder: package, releaseTag: receipt?.asset.releaseTag)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
    }

    public static func installDXVKPackage(_ asset: EngineAsset, for runtime: Runtime, allowUnverified: Bool = false,
                                          update: @escaping @Sendable (String, Double?) -> Void) async throws -> URL {
        guard Self.supportsMacOSDXVK(runtime), let managedRoot = runtime.managedRoot else {
            throw RumError.message("This runtime needs a managed x64 Wine engine with MoltenVK to use macOS DXVK.")
        }
        guard asset.verifiedDownload || allowUnverified else {
            throw RumError.message("This DXVK release has no publisher checksum. Review the release before installing it.")
        }
        guard asset.browser_download_url.scheme == "https", isMacOSDXVKAsset(asset),
              asset.size > 0, asset.size < 1_000_000_000 else {
            throw RumError.message("The DXVK release asset has an unexpected URL, format, or size.")
        }
        if let releaseTag = asset.releaseTag,
           let existing = installedDXVKPackages(for: runtime).first(where: { $0.releaseTag == releaseTag }) {
            return existing.folder
        }

        let graphics = managedRoot.appendingPathComponent("graphics", isDirectory: true)
        try FileManager.default.createDirectory(at: graphics, withIntermediateDirectories: true)
        let staging = graphics.appendingPathComponent(".install-dxvk-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        update("Downloading DXVK (\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)))…", nil)
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 1800
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("DXVK download failed. Please retry.") }
        let archive = staging.appendingPathComponent("dxvk.tar.gz")
        try FileManager.default.copyItem(at: download, to: archive)
        let actualSize = (try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value
        guard actualSize == asset.size else { throw RumError.message("The DXVK download is incomplete. Please retry.") }
        update(asset.verifiedDownload ? "Verifying DXVK SHA-256…" : "Recording DXVK download checksum…", nil)
        if asset.verifiedDownload, let digest = asset.digest { try verify(archive, digest: digest) }
        let archiveDigest = try checksum(archive)
        let content = staging.appendingPathComponent("content", isDirectory: true)
        update("Unpacking DXVK…", nil)
        try await unpack(archive, into: content)
        let candidates = (try FileManager.default.contentsOfDirectory(at: content, includingPropertiesForKeys: nil))
        let package = ([content] + candidates).first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("x64/d3d11.dll").path)
        }
        guard let package else { throw RumError.message("This DXVK archive has an unexpected layout. No engine files were changed.") }
        try Wine.validateDXVK(package)
        let tag = String(asset.releaseTag ?? asset.name).map { character -> Character in
            character.isLetter || character.isNumber || "._-".contains(character) ? character : "-"
        }
        let destination = graphics.appendingPathComponent("DXVK-" + String(tag) + "-" + asset.name.replacingOccurrences(of: ".tar.gz", with: ""), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RumError.message("A DXVK folder with this release name already exists but could not be recognized. Remove it manually after checking its contents, then retry.")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            let installedPackage = destination.appendingPathComponent("package", isDirectory: true)
            try FileManager.default.moveItem(at: package, to: installedPackage)
            let receipt = try JSONEncoder().encode(DXVKPackageReceipt(asset: asset, sha256: archiveDigest, publisherChecksumVerified: asset.verifiedDownload))
            try receipt.write(to: destination.appendingPathComponent("download-receipt.json"), options: .atomic)
            update("DXVK installed", 1)
            return installedPackage
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func releaseAssets(from releases: [EngineRelease], feed: EngineFeed) -> [EngineAsset] {
        releases.flatMap { release in
            release.assets.map { original in
                var asset = original
                asset.releaseTag = release.tag_name
                asset.releaseName = release.name
                asset.releaseNotes = release.body
                if feed == .whisky, !asset.verifiedDownload {
                    asset.digest = publisherChecksum(in: release.body, for: asset.name)
                }
                return asset
            }
        }
    }

    static func releasePage(_ assets: [EngineAsset], feed: EngineFeed = .wineHQ, page: Int, link: String?) -> EngineReleasePage {
        var seen = Set<Int>()
        let filtered = assets.filter {
            let name = $0.name.lowercased()
            let supportedArchive = name.hasSuffix(".tar.xz") || name.hasSuffix(".tar.gz")
            let feedArchive = feed == .whisky ? name.contains("libraries") && name.hasSuffix(".tar.gz") : supportedArchive
            return feedArchive && !name.contains("32bit") && seen.insert($0.id).inserted
        }
        let newestFirst = filtered.sorted {
            if $0.created_at != $1.created_at { return ($0.created_at ?? "") > ($1.created_at ?? "") }
            return $0.name.compare($1.name, options: .numeric) == .orderedDescending
        }
        return EngineReleasePage(assets: newestFirst, nextPage: link?.contains("rel=\"next\"") == true ? page + 1 : nil)
    }

    static func publisherChecksum(in releaseNotes: String?, for assetName: String) -> String? {
        guard let releaseNotes else { return nil }
        let line = releaseNotes.components(separatedBy: .newlines).first {
            $0.localizedCaseInsensitiveContains("sha-256") && $0.localizedCaseInsensitiveContains(assetName)
        }
        guard let line,
              let expression = try? NSRegularExpression(pattern: "[A-Fa-f0-9]{64}"),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return "sha256:" + line[range].lowercased()
    }

    static let sikarugirTemplate = "Template-1.0.24"
    static let sikarugirTemplateDigest = "sha256:4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c"

    static func validateStandaloneSikarugir(_ wine: URL) throws {
        let module = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        let data = try Data(contentsOf: module, options: .mappedIfSafe)
        if data.range(of: Data("SikarugirAppWine".utf8)) != nil {
            throw RumError.message("This Sikarugir engine requires the publisher's own launcher before it will start Windows programs. Spiced-Rum does not yet integrate that launcher. Use this build in Sikarugir itself. Within Spiced-Rum, choose Wine Staging or a compatible older Sikarugir engine.")
        }
    }

    static func setupSikarugir(_ runtime: Runtime, update: @escaping @Sendable (String, Double?) -> Void) async throws -> URL {
        update("Downloading Sikarugir's runtime support libraries…", nil)
        // Engines omit dependencies supplied by the publisher's separate wrapper template.
        // Keep its original files and notices intact; launch Wine directly, not the wrapper.
        let url = URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(sikarugirTemplate).tar.xz")!
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RumError.message("Sikarugir's support package could not be downloaded. Its engines also need this package to run; retry engine setup when the connection is available.")
        }
        try verify(file, digest: sikarugirTemplateDigest)
        let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        let support = engine.appendingPathComponent("support", isDirectory: true)
        try await unpack(file, into: support)
        let template = support.appendingPathComponent(sikarugirTemplate + ".app", isDirectory: true)
        try linkSikarugirLibraries(template: template, engine: engine)
        struct Receipt: Encodable { let template: String; let sha256: String; let source: URL }
        try JSONEncoder().encode(Receipt(template: sikarugirTemplate, sha256: sikarugirTemplateDigest, source: url))
            .write(to: support.appendingPathComponent("download-receipt.json"), options: .atomic)
        return try sikarugirLaunchers(in: engine)
    }

    static func sikarugirLaunchers(in engine: URL) throws -> URL {
        let folder = engine.appendingPathComponent("spiced-rum-launchers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        for binary in ["wine", "wineserver"] {
            // Set dyld paths after the system shell starts: arch and system interpreters
            // strip inherited DYLD variables. Wine's children inherit these fresh values.
            let script = """
            #!/bin/sh
            engine_dir=$(CDPATH= cd -- "$(/usr/bin/dirname "$0")/.." && pwd -P) || exit 1
            export DYLD_LIBRARY_PATH="$engine_dir/lib"
            exec "$engine_dir/bin/\(binary)" "$@"

            """
            let file = folder.appendingPathComponent(binary)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return folder.appendingPathComponent("wine")
    }

    static func linkSikarugirLibraries(template: URL, engine: URL) throws {
        let fm = FileManager.default
        let frameworks = template.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard fm.fileExists(atPath: frameworks.appendingPathComponent("libinotify.0.dylib").path) else {
            throw RumError.message("Sikarugir's support package is missing libinotify. Retry setup or choose Wine Staging.")
        }
        let sources = [frameworks, frameworks.appendingPathComponent("GStreamer.framework/Versions/1.0/lib")]
        let destinations = [engine.appendingPathComponent("lib"), engine.appendingPathComponent("lib/wine/x86_64-unix")]
        let supportRoot = engine.appendingPathComponent("support").resolvingSymlinksInPath().path + "/"
        for source in sources {
            let files = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).filter { $0.pathExtension == "dylib" }
            for file in files {
                guard file.resolvingSymlinksInPath().path.hasPrefix(supportRoot) else {
                    throw RumError.message("A Sikarugir support library points outside its package.")
                }
                let relative = String(file.standardizedFileURL.path.dropFirst(engine.standardizedFileURL.path.count + 1))
                for destination in destinations {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                    let link = destination.appendingPathComponent(file.lastPathComponent)
                    // Preserve any libraries included by the selected engine itself.
                    guard (try? fm.attributesOfItem(atPath: link.path)) == nil else { continue }
                    let depth = destination.pathComponents.count - engine.pathComponents.count
                    try fm.createSymbolicLink(atPath: link.path, withDestinationPath: String(repeating: "../", count: depth) + relative)
                }
            }
        }
    }

    public static func checksum(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(_ file: URL, digest: String) throws {
        guard digest.hasPrefix("sha256:"), digest.count == 71 else { throw RumError.message("The publisher has not supplied a SHA-256 digest for this asset.") }
        let actual = try checksum(file)
        guard actual == digest.dropFirst(7).lowercased() else { throw RumError.message("Engine checksum mismatch. The download was discarded; retry from the publisher.") }
    }

    public static func validateArchivePaths(_ listing: String) throws {
        for path in listing.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            guard !path.hasPrefix("/"), !path.components(separatedBy: "/").contains("..") else { throw RumError.message("The archive contains an unsafe path: \(path)") }
        }
    }

    public static func unpack(_ archive: URL, into folder: URL) async throws {
        let listing = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", archive.path])
        try validateArchivePaths(listing)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // macOS bsdtar defaults reject absolute paths, .. and extraction through symlinks.
        // Do not pass -P / --absolute-paths, which would disable those protections.
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", folder.path, "--no-same-owner", "--no-same-permissions"])
    }

    public static func setupGraphics(_ runtime: Runtime, update: @escaping @Sendable (String, Double?) -> Void) async throws -> Runtime {
        var runtime = runtime
        let root = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        // Complete WineHQ macOS bundles include their own Intel MoltenVK and dependencies.
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/libMoltenVK.dylib").path), let managed = runtime.managedRoot else { return runtime }
        update("Setting up macOS DXVK graphics…", nil)
        let url = URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz")!
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("The engine downloaded, but its DXVK graphics package could not be downloaded. Retry engine setup when the connection is available.") }
        // Pinned from the official native-DLL package, checked 16 October 2026.
        try verify(file, digest: "sha256:acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477")
        let graphics = managed.appendingPathComponent("graphics", isDirectory: true)
        try await unpack(file, into: graphics)
        let candidates = try FileManager.default.contentsOfDirectory(at: graphics, includingPropertiesForKeys: nil)
        guard let package = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("x64/d3d11.dll").path) }) else { throw RumError.message("The downloaded DXVK package has an unexpected layout. Retry or use another engine.") }
        try Wine.validateDXVK(package)
        runtime.dxvkPackage = package
        return runtime
    }

    public static func checkX64(_ runtime: Runtime, in root: URL) async throws {
        let test = try ShotglassFiles.create(Shotglass(name: "Engine validation", runtime: runtime, graphics: .wine), parent: root)
        do {
            let ready = try await Wine.initialize(test, dxvk: nil)
            try await Wine.execute(runtime: runtime, arguments: ["cmd", "/c", "echo", "SPICED_RUM_ENGINE_OK"], environment: Wine.environment(for: ready), directory: ready.folder, log: ready.log)
            let output = try String(contentsOf: ready.log).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard output.contains("SPICED_RUM_ENGINE_OK") else { throw RumError.message("The engine did not run the Windows x64 test command.") }
            try await Wine.execute(runtime: runtime, arguments: ["wineboot", "--shutdown", "--force", "--kill"], environment: Wine.environment(for: ready), directory: ready.folder, log: ready.log)
            try FileManager.default.removeItem(at: test.folder)
        } catch {
            let details = String(((try? String(contentsOf: test.log)) ?? "").suffix(2500))
            let server = runtime.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
            if FileManager.default.isExecutableFile(atPath: server.path) {
                var serverRuntime = runtime; serverRuntime.executable = server
                let (binary, args) = Wine.command(runtime: serverRuntime, arguments: ["-k"])
                try? await ProcessRunner.run(binary, args, environment: Wine.environment(for: test), directory: test.folder, log: test.log, timeout: 10)
            }
            throw RumError.message("The engine could not create and run a Windows x64 environment. It has not been marked ready.\n\(error.localizedDescription)\n\(details)")
        }
    }

    public static func findWine(in folder: URL) throws -> URL {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { throw RumError.message("Cannot inspect extracted engine.") }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            if ["wine", "wine64"].contains(url.lastPathComponent), url.path.contains("/bin/"), fm.isExecutableFile(atPath: url.path) {
                guard url.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/") else { continue }
                candidates.append(url)
            }
        }
        // Prefer the public bin launcher to lib/wine's internal loader or an app UI wrapper.
        guard let candidate = candidates.sorted(by: { $0.path.count < $1.path.count }).first else {
            throw RumError.message("The archive has no standalone Wine launcher. This engine requires its publisher's wrapper setup; use manual registration after preparing it.")
        }
        return candidate
    }

    static func relativeExecutablePath(in folder: URL, executable: URL) throws -> String {
        let folderPath = folder.standardizedFileURL.path + "/"
        let executablePath = executable.standardizedFileURL.path
        let canonicalFolder = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let canonicalExecutable = executable.resolvingSymlinksInPath().standardizedFileURL.path
        guard executablePath.hasPrefix(folderPath), canonicalExecutable.hasPrefix(canonicalFolder) else {
            throw RumError.message("The engine executable points outside its installation folder.")
        }
        // Keep the public bin launcher path. Whisky uses relative symlinks from
        // Wine/bin into lib/wine; relocating the resolved target breaks Wine's
        // root discovery and hides GPTK's lib/wine tree from payload setup.
        return String(executablePath.dropFirst(folderPath.count))
    }

    public static func install(_ asset: EngineAsset, feed: EngineFeed, into engines: URL, allowUnverified: Bool = false, update: @escaping @Sendable (String, Double?) -> Void) async throws -> Runtime {
        var evaluation: GPTKEvaluationEnvironment?
        if feed == .whisky, asset.requiresAppleGPTKPayload {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 else {
                throw RumError.message("Whisky community Wine Libraries and Apple's GPTK 4 payload require macOS 15 or later. The engine has not been downloaded.")
            }
            update("Finding Apple's downloaded GPTK evaluation payload…", nil)
            evaluation = try await GPTKInstaller.findOrMountEvaluationEnvironment()
                ?? GPTKInstaller.installedEvaluationPayload(in: engines)
            guard evaluation != nil else {
                throw RumError.message("This GPTK-capable Whisky runtime needs Apple's Game Porting Toolkit evaluation environment .dmg. Spiced-Rum couldn't find it in Downloads, on a mounted toolkit image, or in an installed GPTK runtime. Download the evaluation environment from Apple's developer downloads and retry; the engine has not been downloaded.")
            }
        }
        do {
            let runtime = try await installArchive(asset, feed: feed, into: engines, allowUnverified: allowUnverified, evaluation: evaluation, update: update)
            if let evaluation { await GPTKInstaller.unmountIfMountedBySpicedRum(evaluation) }
            return runtime
        } catch {
            if let evaluation { await GPTKInstaller.unmountIfMountedBySpicedRum(evaluation) }
            throw error
        }
    }

    private static func installArchive(_ asset: EngineAsset, feed: EngineFeed, into engines: URL, allowUnverified: Bool,
                                       evaluation: GPTKEvaluationEnvironment?, update: @escaping @Sendable (String, Double?) -> Void) async throws -> Runtime {
        if feed == .whisky, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15 {
            throw RumError.message("Whisky community Wine Libraries require macOS 15 or later. This runtime has not been downloaded.")
        }
        guard !asset.requiresSikarugirLauncher else {
            throw RumError.message("Sikarugir Wine 11 requires the publisher's launcher, which Spiced-Rum does not yet integrate. Use this build in Sikarugir itself. Within Spiced-Rum, choose Wine Staging or a compatible older Sikarugir version.")
        }
        guard asset.verifiedDownload || allowUnverified else { throw RumError.message("This older release has no publisher checksum. Choose Install legacy download and review the explanation to install it from the publisher.") }
        guard asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com", asset.browser_download_url.path.lowercased().hasPrefix("/\(feed.repository.lowercased())/releases/download/"), asset.size > 0, asset.size < 2_000_000_000 else { throw RumError.message("The release asset has an unexpected URL or size.") }
        let fm = FileManager.default
        try fm.createDirectory(at: engines, withIntermediateDirectories: true)
        let staging = engines.appendingPathComponent(".install-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        update("Downloading engine (\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)))…", nil)
        var request = URLRequest(url: asset.browser_download_url); request.timeoutInterval = 1800
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? fm.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RumError.message("Engine download failed. Please retry.") }
        let archive = staging.appendingPathComponent("engine.tar")
        try fm.copyItem(at: download, to: archive)
        let actualSize = (try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value
        guard actualSize == asset.size else { throw RumError.message("Engine download is incomplete. Please retry.") }
        try Task.checkCancellation()
        update(asset.verifiedDownload ? "Verifying SHA-256…" : "Recording download checksum…", nil)
        if asset.verifiedDownload, let digest = asset.digest { try verify(archive, digest: digest) }
        let calculatedDigest = try checksum(archive)
        let content = staging.appendingPathComponent("content", isDirectory: true)
        update("Unpacking engine…", nil); try await unpack(archive, into: content)
        // Some Wineskin-era engines have one inner wine archive.
        if (try? findWine(in: content)) == nil {
            let files = fm.enumerator(at: content, includingPropertiesForKeys: nil)
            var inner: [URL] = []
            while let file = files?.nextObject() as? URL {
                if ["wine.tar.xz", "wine.tar.gz"].contains(file.lastPathComponent) { inner.append(file) }
            }
            if inner.count == 1 { try await unpack(inner[0], into: inner[0].deletingLastPathComponent()) }
        }
        let wine = try findWine(in: content)
        try Task.checkCancellation()
        update("Checking macOS Wine…", nil)
        var runtime = Runtime(name: asset.installedName(in: feed), executable: wine, useRosetta: true, d3dMetal: false, version: "")
        if feed == .sikarugir {
            try validateStandaloneSikarugir(wine)
            runtime.executable = try await setupSikarugir(runtime, update: update)
        }
        do { runtime.version = try await Wine.probe(runtime) }
        catch { throw RumError.message("The extracted engine could not start.\n\(error.localizedDescription)") }
        try Task.checkCancellation()
        let destination = engines.appendingPathComponent(runtime.id.uuidString, isDirectory: true)
        let relative = try relativeExecutablePath(in: content, executable: runtime.executable)
        do {
            do { try fm.moveItem(at: content, to: destination) }
            catch { throw RumError.message("Cannot place the extracted engine in its installation folder.\n\(error.localizedDescription)") }
            runtime.executable = destination.appendingPathComponent(relative)
            runtime.managedRoot = destination
            if let evaluation {
                update("Attaching Apple's GPTK \(evaluation.version) payload to the Wine engine…", nil)
                runtime = try await GPTKInstaller.attachPayload(evaluation, to: runtime, into: destination)
            }
            // Verify again after relocation; some engines contain absolute paths.
            runtime.version = try await Wine.probe(runtime)
            if feed != .sikarugir {
                runtime = try await setupGraphics(runtime, update: update)
            }
            update("Preparing video playback and H.264 codecs…", nil)
            try await MediaSupport.prepare(runtime)
            update("Testing Windows x64 setup (first run may take a minute)…", nil)
            try await checkX64(runtime, in: destination)
            struct Receipt: Encodable { let asset: EngineAsset; let sha256: String; let publisherChecksumVerified: Bool }
            let receipt = try JSONEncoder().encode(Receipt(asset: asset, sha256: calculatedDigest, publisherChecksumVerified: asset.verifiedDownload))
            try receipt.write(to: destination.appendingPathComponent("download-receipt.json"), options: .atomic)
        } catch { try? fm.removeItem(at: destination); throw error }
        update("Engine installed", 1)
        return runtime
    }
}

extension EngineAsset: Encodable {}
