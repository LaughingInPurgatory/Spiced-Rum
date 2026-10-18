import XCTest
@testable import SpicedRumCore

final class RuntimeManagementTests: XCTestCase {
    func testManagedRemovalPathMustBeDirectRealChildOfEngineFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumRuntimeRemoval-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engines = root.appendingPathComponent("Engines", isDirectory: true)
        let managed = engines.appendingPathComponent("Wine Staging 10", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        var runtime = Runtime(name: "Wine Staging", executable: managed.appendingPathComponent("bin/wine"), useRosetta: true, d3dMetal: false, version: "10")
        runtime.managedRoot = managed
        XCTAssertEqual(RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines), managed)

        runtime.managedRoot = root.appendingPathComponent("External Engine", isDirectory: true)
        XCTAssertNil(RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines))

        let nested = managed.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        runtime.managedRoot = nested
        XCTAssertNil(RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines))

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = engines.appendingPathComponent("linked-engine", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        runtime.managedRoot = link
        XCTAssertNil(RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines))
    }

    func testDetectsWhenARecoverableBackupReferencesAnEngine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumBackupEngineRef-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRuntime = Runtime(name: "Old engine", executable: URL(fileURLWithPath: "/tmp/old-wine"), useRosetta: true, d3dMetal: false, version: "1")
        let entry = try ShotglassFiles.create(Shotglass(name: "Test", runtime: oldRuntime, graphics: .wine), parent: root)
        let backup = entry.folder.appendingPathComponent("engine-backups", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try entry.shotglass.save(in: backup)
        try Data("{}".utf8).write(to: backup.appendingPathComponent("environment.json"))

        XCTAssertTrue(try ShotglassEngines.backupReferences(runtimeID: oldRuntime.id, for: entry))
        XCTAssertFalse(try ShotglassEngines.backupReferences(runtimeID: UUID(), for: entry))
    }
}
