import Foundation

public enum Graphics: String, Codable, CaseIterable, Identifiable {
    case wine = "Wine default"
    case dxvk = "DXVK · MoltenVK"
    case metal = "D3DMetal · GPTK"
    case dxmt = "DXMT · Metal"
    public var id: String { rawValue }
}

public struct Runtime: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var executable: URL
    public var useRosetta: Bool
    public var d3dMetal: Bool
    public var dxmt: Bool
    public var version: String
    public var dxvkPackage: URL?
    public var managedRoot: URL?
    public var gptkVersion: String? = nil
    public var defaultGraphics: Graphics { dxvkPackage != nil ? .dxvk : dxmt ? .dxmt : d3dMetal ? .metal : .wine }
    public init(name: String, executable: URL, useRosetta: Bool, d3dMetal: Bool, dxmt: Bool = false, version: String) {
        self.name = name; self.executable = executable; self.useRosetta = useRosetta
        self.d3dMetal = d3dMetal; self.dxmt = dxmt; self.version = version
    }
}

public enum RuntimeManagement {
    /// Returns an installed engine directory only when it is a real direct child
    /// of Spiced-Rum's managed Engines folder. Other paths are never deleted.
    public static func managedEngineDirectory(for runtime: Runtime, inside enginesDirectory: URL) -> URL? {
        guard let root = runtime.managedRoot?.standardizedFileURL,
              root.deletingLastPathComponent() == enginesDirectory.standardizedFileURL,
              root != enginesDirectory.standardizedFileURL,
              let engineValues = try? enginesDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              engineValues.isDirectory == true, engineValues.isSymbolicLink != true,
              let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { return nil }

        let resolvedEngines = enginesDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedRoot.deletingLastPathComponent() == resolvedEngines else { return nil }
        return root
    }
}

public struct Program: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var path: String
    public var launchArguments: [String]

    private enum CodingKeys: String, CodingKey { case id, name, path, launchArguments }

    public init(name: String, path: String, launchArguments: [String] = []) {
        self.name = name; self.path = path; self.launchArguments = launchArguments
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        launchArguments = try values.decodeIfPresent([String].self, forKey: .launchArguments) ?? []
        // Migrate earlier Heroic GPU workarounds and software-renderer settings.
        if isHeroicLauncher {
            let hadPreviousWorkaround = launchArguments.contains { Self.previousHeroicUIWorkaroundFlags.contains($0.lowercased()) }
            let hadSoftwareRenderer = launchArguments.contains { Self.heroicUIWorkaroundFlags.contains($0.lowercased()) }
            if hadPreviousWorkaround || hadSoftwareRenderer {
                launchArguments.removeAll { Self.heroicUIWorkaroundFlags.contains($0.lowercased()) }
                launchArguments.append(contentsOf: Self.heroicUIWorkaroundArguments)
            }
        }
    }

    private static let heroicUIWorkaroundArguments = ["--use-gl=angle", "--use-angle=swiftshader", "--disable-gpu-rasterization"]
    private static let previousHeroicUIWorkaroundFlags: Set<String> = ["--disable-gpu", "--single-process", "--disable-d3d11", "--disable-direct-composition"]
    private static let heroicUIWorkaroundFlags: Set<String> = Set(heroicUIWorkaroundArguments + Array(previousHeroicUIWorkaroundFlags))

    public var isHeroicLauncher: Bool {
        let executableName = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        return name.localizedCaseInsensitiveContains("heroic") || executableName.localizedCaseInsensitiveContains("heroic")
    }

    public var heroicUIWorkaroundEnabled: Bool {
        launchArguments.contains { $0.caseInsensitiveCompare("--use-angle=swiftshader") == .orderedSame }
    }

    public mutating func setHeroicUIWorkaround(_ enabled: Bool) {
        launchArguments.removeAll { Self.heroicUIWorkaroundFlags.contains($0.lowercased()) }
        if enabled { launchArguments.append(contentsOf: Self.heroicUIWorkaroundArguments) }
    }
}

public struct Shotglass: Codable, Identifiable {
    public var schemaVersion = 1
    public var id = UUID()
    public var name: String
    public var runtime: Runtime
    public var graphics: Graphics
    public var created = Date()
    public var initialized = false
    public var programs: [Program] = []
    public init(name: String, runtime: Runtime, graphics: Graphics) {
        self.name = name; self.runtime = runtime; self.graphics = graphics
    }
    public func save(in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent("shotglass.json"), options: .atomic)
    }
    public static func load(from folder: URL) throws -> Self {
        let metadata = folder.appendingPathComponent("shotglass.json")
        // Read metadata and backups saved before the terminology change.
        let source = FileManager.default.fileExists(atPath: metadata.path) ? metadata : folder.appendingPathComponent("bottle.json")
        let shotglass = try JSONDecoder().decode(Self.self, from: Data(contentsOf: source))
        guard shotglass.schemaVersion == 1 else { throw RumError.message("This shotglass was created by a newer version of Spiced-Rum.") }
        return shotglass
    }
}

public struct ShotglassEntry: Identifiable {
    public var shotglass: Shotglass
    public var folder: URL
    public var id: UUID { shotglass.id }
    public init(shotglass: Shotglass, folder: URL) { self.shotglass = shotglass; self.folder = folder }
    public var prefix: URL { folder.appendingPathComponent("prefix", isDirectory: true) }
    public var log: URL { folder.appendingPathComponent("session.log") }
    public var engineChangePending: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent("engine-change.json").path) }
}

public struct Catalog: Codable {
    public var shotglassFolders: [URL] = []
    public var runtimes: [Runtime] = []
    public var defaultLocation: URL
    public init(defaultLocation: URL) { self.defaultLocation = defaultLocation }

    private enum CodingKeys: String, CodingKey {
        case shotglassFolders, runtimes, defaultLocation
    }
    private enum LegacyKeys: String, CodingKey {
        case folders = "bottleFolders"
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.shotglassFolders) {
            shotglassFolders = try values.decode([URL].self, forKey: .shotglassFolders)
        } else {
            shotglassFolders = try decoder.container(keyedBy: LegacyKeys.self).decode([URL].self, forKey: .folders)
        }
        runtimes = try values.decode([Runtime].self, forKey: .runtimes)
        defaultLocation = try values.decode(URL.self, forKey: .defaultLocation)
    }
}

public enum RumError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public enum ShotglassFiles {
    public static func create(_ shotglass: Shotglass, parent: URL) throws -> ShotglassEntry {
        guard !shotglass.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RumError.message("Give your shotglass a name.")
        }
        // Folder identity never comes from a user-supplied name.
        let folder = parent.appendingPathComponent(shotglass.id.uuidString + ".spicedrum", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do { try shotglass.save(in: folder) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return ShotglassEntry(shotglass: shotglass, folder: folder)
    }

    public static func validateForRemoval(_ entry: ShotglassEntry) throws {
        let folder = entry.folder.standardizedFileURL
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RumError.message("This shotglass folder is missing or is a symbolic link. Spiced-Rum left it untouched.")
        }
        let onDisk = try Shotglass.load(from: folder)
        guard onDisk.id == entry.id else {
            throw RumError.message("The shotglass metadata no longer matches this library entry. Refresh the library before removing it.")
        }
    }

    public static func programPath(_ executable: URL, in entry: ShotglassEntry) -> String {
        let root = entry.folder.standardizedFileURL.path + "/"
        let path = executable.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    public static func programURL(_ program: Program, in entry: ShotglassEntry) throws -> URL {
        if program.path.hasPrefix("/") { return URL(fileURLWithPath: program.path) }
        let url = entry.folder.appendingPathComponent(program.path).standardizedFileURL
        guard url.path.hasPrefix(entry.folder.standardizedFileURL.path + "/") else {
            throw RumError.message("The shortcut path escapes its shotglass folder.")
        }
        return url
    }
}
