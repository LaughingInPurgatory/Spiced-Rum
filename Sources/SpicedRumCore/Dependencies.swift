import Foundation

public enum WindowsDependency: String, CaseIterable, Identifiable {
    case vcrun2022, vcrun2019, d3dcompiler_47, d3dx9, corefonts, dotnet48
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .vcrun2022: return "Visual C++ 2015–2022"
        case .vcrun2019: return "Visual C++ 2015–2019"
        case .d3dcompiler_47: return "DirectX shader compiler 47"
        case .d3dx9: return "DirectX 9 helper libraries"
        case .corefonts: return "Microsoft core fonts"
        case .dotnet48: return ".NET Framework 4.8"
        }
    }
}

public enum Dependencies {
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
