import Foundation

public enum HeroicUICompatibility {
    /// Clears only Electron's regenerated GPU cache from Heroic's Windows user profiles.
    /// Settings, game data, and other applications' caches are left untouched.
    @discardableResult
    public static func clearGPUCache(in entry: ShotglassEntry) throws -> Int {
        let fileManager = FileManager.default
        let users = entry.prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard safeDirectory(users) else { return 0 }

        var removed = 0
        for profile in try fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
            guard safeDirectory(profile),
                  let appData = childDirectory("AppData", in: profile),
                  let roaming = childDirectory("Roaming", in: appData),
                  let heroic = childDirectory("heroic", in: roaming),
                  let gpuCache = childDirectory("GPUCache", in: heroic) else { continue }
            try fileManager.removeItem(at: gpuCache)
            removed += 1
        }
        return removed
    }

    private static func childDirectory(_ name: String, in parent: URL) -> URL? {
        guard safeDirectory(parent),
              let children = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil),
              let child = children.first(where: { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }),
              safeDirectory(child) else { return nil }
        return child
    }

    private static func safeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
