import Foundation

public struct GPTKEvaluationEnvironment: Sendable {
    public let libraries: URL
    public let volume: URL
    public let version: String
    public let mountedBySpicedRum: Bool
    public let volumesMountedBySpicedRum: [URL]
}

public enum GPTKInstaller {
    private static let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)

    public static func availableEvaluationVersions(downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)) -> [String] {
        let mounted = volumeRoots().compactMap { root -> String? in
            let libraries = root.appendingPathComponent("redist/lib", isDirectory: true)
            guard validRedistributables(at: libraries) else { return nil }
            let prefix = "Evaluation environment for Windows games "
            return root.lastPathComponent.hasPrefix(prefix) ? String(root.lastPathComponent.dropFirst(prefix.count)) : root.lastPathComponent
        }
        let images = evaluationImages(in: downloads) + nestedEvaluationImages(in: inMountedToolkitVolumes())
        return orderedAvailableVersions(from: images, mountedVersions: mounted)
    }

    public static func availableEvaluationVersion(downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)) -> String? {
        availableEvaluationVersions(downloads: downloads).first
    }

    static func orderedAvailableVersions(from images: [URL], mountedVersions: [String] = []) -> [String] {
        var seen = Set<String>()
        let versions = mountedVersions + images.compactMap { versionFromImageName($0.deletingPathExtension().lastPathComponent) }
        return versions.filter { seen.insert($0.lowercased()).inserted }.sorted(by: isNewerVersion)
    }

    static func evaluationImages(matchingVersion version: String?, from images: [URL]) -> [URL] {
        let matching = images.filter { image in
            guard let version else { return true }
            return versionFromImageName(image.deletingPathExtension().lastPathComponent)?
                .localizedStandardCompare(version) == .orderedSame
        }
        return matching.sorted(by: imageIsNewer)
    }

    /// Orders GPTK labels naturally, including beta numbers, and ranks a final
    /// release above its prereleases (for example, 4.0 above 4.0 beta 10).
    public static func newestVersion(in versions: [String]) -> String? {
        versions.sorted(by: isNewerVersion).first
    }

    public static func isNewerVersion(_ lhs: String, than rhs: String) -> Bool {
        func parts(_ value: String) -> (base: [Int], stage: Int, suffix: [Int])? {
            var tokens: [String] = []
            var token = ""
            var tokenIsNumber: Bool?
            for character in value.lowercased() {
                let isNumber = character.isNumber
                guard isNumber || character.isLetter else {
                    if !token.isEmpty { tokens.append(token); token = ""; tokenIsNumber = nil }
                    continue
                }
                if let tokenIsNumber, tokenIsNumber != isNumber {
                    tokens.append(token); token = ""
                }
                tokenIsNumber = isNumber
                token.append(character)
            }
            if !token.isEmpty { tokens.append(token) }
            guard !tokens.isEmpty else { return nil }
            if let index = tokens.firstIndex(where: { ["alpha", "a", "beta", "b", "rc"].contains($0) }) {
                let label = tokens[index]
                let stage = ["alpha", "a"].contains(label) ? 0 : ["beta", "b"].contains(label) ? 1 : 2
                return (tokens[..<index].compactMap(Int.init), stage, tokens.dropFirst(index + 1).compactMap(Int.init))
            }
            return (tokens.compactMap(Int.init), 3, [])
        }
        func compare(_ a: [Int], _ b: [Int]) -> ComparisonResult {
            for index in 0..<max(a.count, b.count) {
                let left = index < a.count ? a[index] : 0
                let right = index < b.count ? b[index] : 0
                if left != right { return left > right ? .orderedDescending : .orderedAscending }
            }
            return .orderedSame
        }
        if let left = parts(lhs), let right = parts(rhs) {
            let baseOrder = compare(left.base, right.base)
            if baseOrder != .orderedSame { return baseOrder == .orderedDescending }
            if left.stage != right.stage { return left.stage > right.stage }
            let suffixOrder = compare(left.suffix, right.suffix)
            if suffixOrder != .orderedSame { return suffixOrder == .orderedDescending }
        }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }

    public static func hasDownloadedOrMountedEvaluationEnvironment(downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)) -> Bool {
        availableEvaluationVersion(downloads: downloads) != nil
    }

    public static func findMountedEvaluationEnvironment(version requestedVersion: String? = nil) -> GPTKEvaluationEnvironment? {
        let fm = FileManager.default
        guard let roots = try? fm.contentsOfDirectory(at: volumes, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for root in roots.sorted(by: volumeIsNewer) {
            let libraries = root.appendingPathComponent("redist/lib", isDirectory: true)
            guard validRedistributables(at: libraries) else { continue }
            let prefix = "Evaluation environment for Windows games "
            let versionName = root.lastPathComponent.hasPrefix(prefix) ? String(root.lastPathComponent.dropFirst(prefix.count)) : root.lastPathComponent
            if let requestedVersion, versionName.localizedStandardCompare(requestedVersion) != .orderedSame { continue }
            return GPTKEvaluationEnvironment(libraries: libraries, volume: root, version: versionName, mountedBySpicedRum: false, volumesMountedBySpicedRum: [])
        }
        return nil
    }

    /// Mounts only GPTK-named disk images read-only. It never launches files from an image.
    public static func findOrMountEvaluationEnvironment(
        downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true),
        requestedVersion: String? = nil
    ) async throws -> GPTKEvaluationEnvironment? {
        let requestedVersion = requestedVersion ?? availableEvaluationVersion(downloads: downloads)
        if let mounted = findMountedEvaluationEnvironment(version: requestedVersion) { return mounted }
        let preexistingVolumes = Set(volumeRoots().map { $0.standardizedFileURL.path })
        let candidates = evaluationImages(matchingVersion: requestedVersion,
            from: evaluationImages(in: downloads) + nestedEvaluationImages(in: inMountedToolkitVolumes()))
        var attempted = Set<String>()
        for image in candidates where attempted.insert(image.standardizedFileURL.path).inserted {
            _ = try? await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["attach", "-readonly", "-nobrowse", "-noautoopen", "-quiet", image.path])
            if let mounted = findMountedEvaluationEnvironment(version: requestedVersion) {
                return withMountOwnership(mounted, preexistingVolumes: preexistingVolumes)
            }
            // The outer Game Porting Toolkit image contains the evaluation DMG.
            let nested = nestedEvaluationImages(in: inMountedToolkitVolumes())
            for inner in nested where attempted.insert(inner.standardizedFileURL.path).inserted {
                _ = try? await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["attach", "-readonly", "-nobrowse", "-noautoopen", "-quiet", inner.path])
                if let mounted = findMountedEvaluationEnvironment(version: requestedVersion) {
                    return withMountOwnership(mounted, preexistingVolumes: preexistingVolumes)
                }
            }
        }
        let mounted = requestedVersion.map { findMountedEvaluationEnvironment(version: $0) } ?? findMountedEvaluationEnvironment()
        return mounted.map { withMountOwnership($0, preexistingVolumes: preexistingVolumes) }
    }

    /// Reuses a payload already imported into a managed Apple GPTK runtime if its
    /// original evaluation image is no longer available.
    public static func installedEvaluationPayload(in engines: URL) -> GPTKEvaluationEnvironment? {
        struct Receipt: Decodable { let schemaVersion: Int; let toolkitVersion: String }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: engines, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        let candidates = children.compactMap { root -> (URL, String)? in
            let receipt = root.appendingPathComponent("spiced-rum-gptk.json")
            guard let data = try? Data(contentsOf: receipt),
                  let decoded = try? JSONDecoder().decode(Receipt.self, from: data), decoded.schemaVersion == 2 else { return nil }
            let libraries = root.appendingPathComponent("wine/lib", isDirectory: true)
            guard validRedistributables(at: libraries) else { return nil }
            return (root, decoded.toolkitVersion)
        }.sorted { isNewerVersion($0.1, than: $1.1) }
        guard let (root, version) = candidates.first else { return nil }
        return GPTKEvaluationEnvironment(libraries: root.appendingPathComponent("wine/lib", isDirectory: true), volume: root,
                                         version: version, mountedBySpicedRum: false, volumesMountedBySpicedRum: [])
    }

    public static func unmountIfMountedBySpicedRum(_ evaluation: GPTKEvaluationEnvironment) async {
        guard evaluation.mountedBySpicedRum else { return }
        let mounted = evaluation.volumesMountedBySpicedRum.filter { $0.standardizedFileURL.path != evaluation.volume.standardizedFileURL.path }
        _ = try? await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["detach", evaluation.volume.path])
        for volume in mounted.reversed() {
            _ = try? await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["detach", volume.path])
        }
    }

    /// Creates a private runtime overlay: Wine's core and support libraries remain
    /// intact, Apple's matching graphics redistributables are overlaid, and the
    /// signed app bundle in /Applications is left unchanged.
    public static func install(_ evaluation: GPTKEvaluationEnvironment, using base: Runtime, into engines: URL) async throws -> Runtime {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 else {
            throw RumError.message("Apple's GPTK 4 evaluation environment needs macOS 15 or later. The downloaded image has not been installed.")
        }
        guard validRedistributables(at: evaluation.libraries) else {
            throw RumError.message("The mounted Apple evaluation image is missing D3DMetal or its Wine graphics libraries.")
        }
        let sourceWine = base.executable.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        let sourceLib = sourceWine.appendingPathComponent("lib", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceWine.appendingPathComponent("bin/wine64").path),
              FileManager.default.fileExists(atPath: sourceWine.appendingPathComponent("bin/wineserver").path),
              FileManager.default.fileExists(atPath: sourceLib.appendingPathComponent("GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib").path) else {
            throw RumError.message("The installed Apple GPTK Wine host is incomplete. Install Apple's Game Porting Toolkit app first, then check again.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: engines, withIntermediateDirectories: true)
        let safeVersion = evaluation.version.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = "Apple GPTK \(safeVersion)"
        let destination = engines.appendingPathComponent(name, isDirectory: true)
        let receipt = destination.appendingPathComponent("spiced-rum-gptk.json")
        struct ExistingReceipt: Decodable { let schemaVersion: Int }
        let existingSchema = (try? Data(contentsOf: receipt)).flatMap { try? JSONDecoder().decode(ExistingReceipt.self, from: $0).schemaVersion }
        if existingSchema == 2, fm.fileExists(atPath: destination.appendingPathComponent("wine/bin/wine64").path) {
            var runtime = Runtime(name: name, executable: destination.appendingPathComponent("wine/bin/wine64"), useRosetta: true, d3dMetal: true, version: "")
            runtime.managedRoot = destination
            runtime.gptkVersion = safeVersion
            return runtime
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        let staging = engines.appendingPathComponent(".install-gptk-" + UUID().uuidString, isDirectory: true)
        let stagedWine = staging.appendingPathComponent("wine", isDirectory: true)
        let stagedBin = stagedWine.appendingPathComponent("bin", isDirectory: true)
        let stagedLib = stagedWine.appendingPathComponent("lib", isDirectory: true)
        try fm.createDirectory(at: stagedLib, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [sourceWine.appendingPathComponent("bin").path, stagedBin.path])
        let stagedShare = stagedWine.appendingPathComponent("share", isDirectory: true)
        try fm.createSymbolicLink(atPath: stagedShare.path, withDestinationPath: sourceWine.appendingPathComponent("share").path)
        for item in try fm.contentsOfDirectory(at: sourceLib, includingPropertiesForKeys: nil) where !["wine", "external"].contains(item.lastPathComponent) {
            try fm.createSymbolicLink(atPath: stagedLib.appendingPathComponent(item.lastPathComponent).path, withDestinationPath: item.path)
        }
        // The image contains D3DMetal's Wine modules, not Wine's core ntdll and
        // kernel libraries. Keep the host's complete Wine tree, then overlay the
        // matching beta files in place as Apple's own setup instructions describe.
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [sourceLib.appendingPathComponent("wine").path, stagedLib.appendingPathComponent("wine").path])
        var stagedRuntime = Runtime(name: name, executable: stagedBin.appendingPathComponent("wine64"), useRosetta: true, d3dMetal: false, version: "")
        stagedRuntime.managedRoot = staging
        stagedRuntime = try await attachPayload(evaluation, to: stagedRuntime, into: staging)
        struct Receipt: Encodable { let schemaVersion: Int; let toolkitVersion: String; let sourceWine: URL; let evaluationImage: URL; let installedAt: Date }
        try JSONEncoder().encode(Receipt(schemaVersion: 2, toolkitVersion: evaluation.version, sourceWine: sourceWine, evaluationImage: evaluation.volume, installedAt: Date()))
            .write(to: staging.appendingPathComponent("spiced-rum-gptk.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        var runtime = stagedRuntime
        runtime.executable = destination.appendingPathComponent("wine/bin/wine64")
        runtime.managedRoot = destination
        return runtime
    }

    /// Overlays Apple's three-part GPTK payload onto a runtime that advertises
    /// GPTK compatibility. Wine's core files remain those of the selected engine.
    public static func attachPayload(_ evaluation: GPTKEvaluationEnvironment, to base: Runtime, into engineRoot: URL? = nil) async throws -> Runtime {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 else {
            throw RumError.message("Apple's GPTK 4 payload requires macOS 15 or later. The engine has not been installed.")
        }
        guard validRedistributables(at: evaluation.libraries) else {
            throw RumError.message("The mounted Apple evaluation image is missing D3DMetal or its Wine graphics libraries.")
        }
        let wineRoot = base.executable.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        let wineLib = wineRoot.appendingPathComponent("lib", isDirectory: true)
        guard FileManager.default.isExecutableFile(atPath: base.executable.path),
              FileManager.default.fileExists(atPath: wineLib.appendingPathComponent("wine").path) else {
            throw RumError.message("The GPTK-capable engine is missing its Wine library tree. Its GPTK payload was not attached.")
        }
        let fm = FileManager.default
        let destinations = [wineLib.appendingPathComponent("wine", isDirectory: true), wineLib.appendingPathComponent("external", isDirectory: true)]
        for destination in destinations {
            let values = try? destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { throw RumError.message("The engine's GPTK payload destination is a symbolic link; refusing to write outside its Wine runtime.") }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            let resolvedRoot = wineRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRoot) else {
                throw RumError.message("The engine's GPTK payload destination points outside its Wine runtime.")
            }
        }
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [evaluation.libraries.appendingPathComponent("wine").path, destinations[0].path])
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [evaluation.libraries.appendingPathComponent("external").path, destinations[1].path])

        let root = engineRoot ?? base.managedRoot ?? wineRoot.deletingLastPathComponent()
        let payloadFolder = root.appendingPathComponent("GPTK Payload", isDirectory: true)
        try fm.createDirectory(at: payloadFolder, withIntermediateDirectories: true)
        let evaluationRoot = evaluation.volume
        for notice in ["License.rtf", "Acknowledgements.rtf", "Read Me.rtf"] {
            let source = [evaluationRoot.appendingPathComponent(notice), evaluationRoot.appendingPathComponent("GPTK Payload", isDirectory: true).appendingPathComponent(notice)]
                .first { fm.fileExists(atPath: $0.path) }
            guard let source else { continue }
            _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [source.path, payloadFolder.appendingPathComponent(notice).path])
        }
        struct PayloadReceipt: Encodable { let schemaVersion: Int; let toolkitVersion: String; let sourceImage: URL; let installedAt: Date }
        try JSONEncoder().encode(PayloadReceipt(schemaVersion: 1, toolkitVersion: evaluation.version, sourceImage: evaluation.volume, installedAt: Date()))
            .write(to: payloadFolder.appendingPathComponent("spiced-rum-gptk-payload.json"), options: .atomic)
        var runtime = base
        runtime.d3dMetal = true
        runtime.gptkVersion = evaluation.version
        return runtime
    }

    private static func validRedistributables(at libraries: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: libraries.appendingPathComponent("wine/x86_64-windows/d3d11.dll").path)
            && fm.fileExists(atPath: libraries.appendingPathComponent("wine/x86_64-unix/d3d11.so").path)
            && fm.fileExists(atPath: libraries.appendingPathComponent("external/libd3dshared.dylib").path)
            && fm.fileExists(atPath: libraries.appendingPathComponent("external/D3DMetal.framework/Versions/A/D3DMetal").path)
    }

    private static func evaluationImages(in downloads: URL) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return files.filter { image in
            guard image.pathExtension.lowercased() == "dmg" else { return false }
            let name = image.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: "_", with: " ")
            return name.contains("evaluation environment for windows games") || name.contains("game porting toolkit")
        }.sorted(by: imageIsNewer)
    }

    static func versionFromImageName(_ name: String) -> String? {
        let normalized = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Evaluation environment for Windows games ", "Game Porting Toolkit "] {
            if normalized.lowercased().hasPrefix(prefix.lowercased()) {
                let version = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return version.isEmpty ? nil : version
            }
        }
        return nil
    }

    private static func volumeRoots() -> [URL] {
        let fm = FileManager.default
        guard let roots = try? fm.contentsOfDirectory(at: volumes, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return roots
    }

    private static func inMountedToolkitVolumes() -> [URL] {
        volumeRoots().filter { $0.lastPathComponent.localizedCaseInsensitiveContains("Game Porting Toolkit") }
    }

    private static func withMountOwnership(_ evaluation: GPTKEvaluationEnvironment, preexistingVolumes: Set<String>) -> GPTKEvaluationEnvironment {
        let owned = volumeRoots().filter { !preexistingVolumes.contains($0.standardizedFileURL.path) }
        return GPTKEvaluationEnvironment(libraries: evaluation.libraries, volume: evaluation.volume, version: evaluation.version,
                                         mountedBySpicedRum: !owned.isEmpty, volumesMountedBySpicedRum: owned)
    }

    private static func nestedEvaluationImages(in roots: [URL]) -> [URL] {
        roots.flatMap { root in
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        }.filter { image in
            image.pathExtension.lowercased() == "dmg"
                && image.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains("Evaluation environment for Windows games")
        }.sorted(by: imageIsNewer)
    }

    private static func imageIsNewer(_ lhs: URL, than rhs: URL) -> Bool {
        let leftName = lhs.deletingPathExtension().lastPathComponent
        let rightName = rhs.deletingPathExtension().lastPathComponent
        let leftVersion = versionFromImageName(leftName)
        let rightVersion = versionFromImageName(rightName)
        if let leftVersion, let rightVersion, leftVersion != rightVersion {
            return isNewerVersion(leftVersion, than: rightVersion)
        }
        if leftVersion != nil, rightVersion == nil { return true }
        if leftVersion == nil, rightVersion != nil { return false }
        return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedDescending
    }

    private static func volumeIsNewer(_ lhs: URL, than rhs: URL) -> Bool {
        let leftVersion = versionFromImageName(lhs.lastPathComponent)
        let rightVersion = versionFromImageName(rhs.lastPathComponent)
        if let leftVersion, let rightVersion, leftVersion != rightVersion {
            return isNewerVersion(leftVersion, than: rightVersion)
        }
        if leftVersion != nil, rightVersion == nil { return true }
        if leftVersion == nil, rightVersion != nil { return false }
        return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedDescending
    }
}
