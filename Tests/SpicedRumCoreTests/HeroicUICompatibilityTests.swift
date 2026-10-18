import XCTest
@testable import SpicedRumCore

final class HeroicUICompatibilityTests: XCTestCase {
    func testClearsOnlyHeroicGPUCacheAcrossWindowsProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HeroicCacheTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = ShotglassEntry(shotglass: Shotglass(name: "Heroic", runtime: Runtime(name: "Test", executable: URL(fileURLWithPath: "/usr/bin/true"), useRosetta: false, d3dMetal: false, version: "test"), graphics: .wine), folder: root)

        for profile in ["player", "crossover"] {
            let cache = entry.prefix.appendingPathComponent("drive_c/users/\(profile)/AppData/Roaming/heroic/GPUCache", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("stale cache".utf8).write(to: cache.appendingPathComponent("index"))
            let settings = cache.deletingLastPathComponent().appendingPathComponent("config.json")
            try Data("settings".utf8).write(to: settings)
        }
        let otherCache = entry.prefix.appendingPathComponent("drive_c/users/player/AppData/Roaming/other-app/GPUCache", isDirectory: true)
        try FileManager.default.createDirectory(at: otherCache, withIntermediateDirectories: true)

        XCTAssertEqual(try HeroicUICompatibility.clearGPUCache(in: entry), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.prefix.appendingPathComponent("drive_c/users/player/AppData/Roaming/heroic/GPUCache").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.prefix.appendingPathComponent("drive_c/users/crossover/AppData/Roaming/heroic/config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherCache.path))
        XCTAssertEqual(try HeroicUICompatibility.clearGPUCache(in: entry), 0)
    }
}
