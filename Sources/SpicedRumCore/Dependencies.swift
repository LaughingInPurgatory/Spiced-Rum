import Foundation

public struct WindowsDependency: Identifiable, Hashable {
    public let rawValue: String
    public let title: String
    public let category: String
    public var id: String { rawValue }

    public init(rawValue: String, title: String, category: String) {
        self.rawValue = rawValue
        self.title = title
        self.category = category
    }
}

public enum Dependencies {
    public static let recommended = [
        WindowsDependency(rawValue: "vcrun2022", title: "Visual C++ 2015–2022", category: "dlls"),
        WindowsDependency(rawValue: "d3dcompiler_47", title: "DirectX shader compiler 47", category: "dlls"),
        WindowsDependency(rawValue: "d3dx9", title: "DirectX 9 helper libraries", category: "dlls"),
        WindowsDependency(rawValue: "corefonts", title: "Microsoft core fonts", category: "fonts"),
        WindowsDependency(rawValue: "dotnet48", title: ".NET Framework 4.8", category: "dlls")
    ]
    public static var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static var winetricks: URL? {
        ["/opt/homebrew/bin/winetricks", "/usr/local/bin/winetricks", "/opt/local/bin/winetricks"].map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static var sevenZip: URL? {
        ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7zz", "/usr/local/bin/7z", "/opt/local/bin/7zz", "/opt/local/bin/7z"].map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static var hostEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"; env["HOMEBREW_NO_ANALYTICS"] = "1"
        return env
    }
    public static func listAll() async throws -> [WindowsDependency] {
        guard let script = winetricks else { throw RumError.message("Install Winetricks in Runtimes & setup to browse its components.") }
        var environment = hostEnvironment
        for key in ["WINEPREFIX", "WINE", "WINE64", "WINESERVER"] { environment.removeValue(forKey: key) }
        environment["WINETRICKS_GUI"] = "none"
        let output = try await ProcessRunner.capture(URL(fileURLWithPath: "/bin/bash"), [script.path, "list-all"], environment: environment)
        let results = parseListAll(output)
        guard !results.isEmpty else { throw RumError.message("Winetricks returned no components. Check the dependency tools setup and try again.") }
        return results
    }

    public static func parseListAll(_ output: String) -> [WindowsDependency] {
        let verbPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_][A-Za-z0-9_-]*$")
        let linuxGraphicsPattern = try! NSRegularExpression(pattern: "^(dxvk([0-9]+|_nvapi[0-9]*|_async)?|vkd3d(-proton)?)$")
        var category = "components"
        var seen = Set<String>()
        var results: [WindowsDependency] = []
        for sourceLine in output.components(separatedBy: .newlines) {
            let line = sourceLine.replacingOccurrences(of: "|", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("===="), line.hasSuffix("====") {
                category = line.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).lowercased()
                continue
            }
            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let verb = fields.first else { continue }
            let rawValue = String(verb)
            let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
            guard verbPattern.firstMatch(in: rawValue, range: range) != nil else { continue }
            let title = fields.count > 1 ? String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines) : rawValue
            let normalizedID = rawValue.lowercased()
            let idRange = NSRange(normalizedID.startIndex..<normalizedID.endIndex, in: normalizedID)
            guard linuxGraphicsPattern.firstMatch(in: normalizedID, range: idRange) == nil,
                  !title.localizedCaseInsensitiveContains("linux"),
                  seen.insert(normalizedID).inserted else { continue }
            results.append(WindowsDependency(rawValue: rawValue, title: title, category: category))
        }
        for dependency in recommended where !seen.contains(dependency.rawValue) {
            results.append(dependency)
        }
        return results.sorted {
            let categoryOrder = $0.category.localizedStandardCompare($1.category)
            return categoryOrder == .orderedSame ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : categoryOrder == .orderedAscending
        }
    }
    public static func installTools(log: URL) async throws {
        guard let brew else { throw RumError.message("Install Homebrew from brew.sh first, then use Install dependency tools again. Spiced-Rum uses Homebrew to install Winetricks and its extraction tools.") }
        try await ProcessRunner.run(brew, ["install", "winetricks"], environment: hostEnvironment, directory: log.deletingLastPathComponent(), log: log, label: "Homebrew")
        guard winetricks != nil else { throw RumError.message("Homebrew finished, but Winetricks was not found. See the tools log.") }
    }
    public static func ensureSevenZip(log: URL) async throws -> URL {
        if let sevenZip { return sevenZip }
        guard let brew else { throw RumError.message("Heroic's setup cannot run in this shotglass. Install 7-Zip (7zz) or Homebrew, then retry. Spiced-Rum can extract the setup files directly once 7-Zip is available.") }
        try await ProcessRunner.run(brew, ["install", "sevenzip"], environment: hostEnvironment, directory: log.deletingLastPathComponent(), log: log, label: "Installing 7-Zip for Heroic extraction")
        guard let sevenZip else { throw RumError.message("Homebrew finished, but 7-Zip (7zz) was not found. See the shotglass log.") }
        return sevenZip
    }
    public static func install(_ dependency: WindowsDependency, in entry: ShotglassEntry) async throws {
        guard entry.shotglass.initialized else { throw RumError.message("Initialize the shotglass first.") }
        guard let script = winetricks else { throw RumError.message("Install dependency tools in Runtimes & setup first.") }
        guard dependency.rawValue.range(of: "^[A-Za-z0-9_][A-Za-z0-9_-]*$", options: .regularExpression) != nil else {
            throw RumError.message("This Winetricks component name is invalid.")
        }
        try Wine.checkExecutable(entry.shotglass.runtime.executable)
        let server = entry.shotglass.runtime.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: server.path) else { throw RumError.message("Winetricks needs wineserver beside the Wine executable. Select the runtime's bin/wine launcher instead of a wrapper script.") }
        // Leave renderer overrides out of dependency setup; Winetricks manages required DLL overrides in the prefix.
        var plain = entry; plain.shotglass.graphics = .wine
        var env = Wine.environment(for: plain)
        env["PATH"] = entry.shotglass.runtime.executable.deletingLastPathComponent().path + ":" + hostEnvironment["PATH"]!
        env["WINE"] = entry.shotglass.runtime.executable.path
        env["WINE64"] = entry.shotglass.runtime.executable.path
        env["WINESERVER"] = server.path
        env["WINETRICKS_GUI"] = "none"
        // Keep installers interactive so their own license and setup dialogs remain available.
        try await ProcessRunner.run(URL(fileURLWithPath: "/bin/bash"), [script.path, dependency.rawValue], environment: env, directory: entry.folder, log: entry.log, label: "Winetricks")
    }
}
