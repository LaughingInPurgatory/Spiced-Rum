import Foundation

public enum HeroicInstaller {
    private static let fileManager = FileManager.default

    public static func isSetup(_ executable: URL) -> Bool {
        let name = executable.deletingPathExtension().lastPathComponent.lowercased()
        return name.contains("heroic") && name.contains("setup")
    }

    /// Extracts Heroic's embedded Electron application without starting its NSIS installer under Wine.
    /// This intentionally skips Windows registry, Start menu, and uninstaller registration.
    public static func extract(_ setup: URL, into entry: ShotglassEntry, using sevenZip: URL) async throws -> URL {
        guard isSetup(setup), setup.pathExtension.lowercased() == "exe",
              fileManager.isReadableFile(atPath: setup.path) else {
            throw RumError.message("Select a readable Heroic Windows setup .exe.")
        }
        guard fileManager.isExecutableFile(atPath: sevenZip.path) else {
            throw RumError.message("7-Zip (7zz) is not executable. Install 7-Zip and retry the Heroic extraction.")
        }

        let target = entry.prefix.appendingPathComponent("drive_c/Program Files/Heroic", isDirectory: true)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw RumError.message("Heroic is already extracted at \(target.path). Remove that folder first if you want to replace it.")
        }

        let staging = entry.folder.appendingPathComponent(".heroic-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        let listing = try await ProcessRunner.capture(sevenZip, ["l", "-slt", setup.path])
        let available = Set(listing.components(separatedBy: .newlines).compactMap { line -> String? in
            guard line.hasPrefix("Path = $PLUGINSDIR/app-"), line.hasSuffix(".7z") else { return nil }
            return String(line.dropFirst("Path = $PLUGINSDIR/".count))
        })
        let payload = ["app-64.7z", "app-32.7z"].first(where: available.contains)
        guard let payload else {
            throw RumError.message("This Heroic setup does not contain the expected app-64.7z or app-32.7z payload, so it cannot be installed by direct extraction.")
        }

        try await ProcessRunner.run(sevenZip, ["x", "-y", "-o\(staging.path)", setup.path, "$PLUGINSDIR/\(payload)"], directory: staging, log: entry.log, label: "Extracting Heroic setup payload")
        let archive = staging.appendingPathComponent("$PLUGINSDIR/\(payload)")
        guard fileManager.isReadableFile(atPath: archive.path) else {
            throw RumError.message("7-Zip did not extract Heroic's embedded app payload. See the shotglass log.")
        }

        let expanded = staging.appendingPathComponent("application", isDirectory: true)
        try fileManager.createDirectory(at: expanded, withIntermediateDirectories: false)
        try await ProcessRunner.run(sevenZip, ["x", "-y", "-o\(expanded.path)", archive.path], directory: expanded, log: entry.log, label: "Unpacking Heroic application files")
        let executable = expanded.appendingPathComponent("Heroic.exe")
        guard fileManager.isReadableFile(atPath: executable.path),
              fileManager.fileExists(atPath: expanded.appendingPathComponent("resources/app.asar").path) else {
            throw RumError.message("The extracted Heroic payload is incomplete: Heroic.exe or resources/app.asar is missing.")
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: expanded, to: target)
        return target.appendingPathComponent("Heroic.exe")
    }
}
