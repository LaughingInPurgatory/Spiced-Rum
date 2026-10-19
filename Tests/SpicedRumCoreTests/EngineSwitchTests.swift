import XCTest
@testable import SpicedRumCore

final class EngineSwitchTests: XCTestCase {
    func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumSwitch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func engine(in root: URL, name: String, fails: Bool = false, failsStop: Bool = false) throws -> Runtime {
        let bin = root.appendingPathComponent(name + "/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine = bin.appendingPathComponent("wine")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo wine-test; exit 0; fi
        if [ "$1" = "wineboot" ]; then
          printf '#arch=win64\n' > "$WINEPREFIX/system.reg"
          mkdir -p "$WINEPREFIX/drive_c/windows/system32"
          printf changed > "$WINEPREFIX/drive_c/windows/system32/engine-state"
          exit \(fails ? 42 : 0)
        fi
        exit 0
        """
        try script.write(to: wine, atomically: true, encoding: .utf8)
        let server = bin.appendingPathComponent("wineserver")
        let serverScript = failsStop ? "#!/bin/sh\nexit 1\n" : "#!/bin/sh\nif [ \"$1\" = \"-k\" ]; then exit 1; fi\nexit 0\n"
        try serverScript.write(to: server, atomically: true, encoding: .utf8)
        for file in [wine, server] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        return Runtime(name: name, executable: wine, useRosetta: false, d3dMetal: false, version: "wine-test")
    }

    func shotglass(in root: URL, runtime: Runtime) throws -> ShotglassEntry {
        var model = Shotglass(name: "Games", runtime: runtime, graphics: .wine); model.initialized = true
        let entry = try ShotglassFiles.create(model, parent: root)
        for path in ["drive_c/windows/system32", "drive_c/windows/syswow64", "drive_c/Program Files/Game", "drive_c/users/player/Saved Games", "drive_c/ProgramData/Game", "dosdevices"] {
            try FileManager.default.createDirectory(at: entry.prefix.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try "#arch=win64\noriginal registry".write(to: entry.prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        try "original environment".write(to: entry.prefix.appendingPathComponent("drive_c/windows/system32/engine-state"), atomically: true, encoding: .utf8)
        for path in ["drive_c/Program Files/Game/game.exe", "drive_c/users/player/Saved Games/save.dat", "drive_c/ProgramData/Game/data"] {
            try "installed app data".write(to: entry.prefix.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(atPath: entry.prefix.appendingPathComponent("dosdevices/c:").path, withDestinationPath: "../drive_c")
        return entry
    }

    func testSwitchRestoreAndDeleteBackUpEnvironmentOnly() async throws {
        let root = try fixture()
        let old = try engine(in: root, name: "old")
        let newer = try engine(in: root, name: "new")
        let entry = try shotglass(in: root, runtime: old)
        var switched = try await ShotglassEngines.change(entry, to: newer)
        XCTAssertEqual(try Shotglass.load(from: entry.folder).runtime.id, newer.id)
        let backup = try XCTUnwrap(ShotglassEngines.backups(for: entry).first)
        for path in ["drive_c/Program Files", "drive_c/users", "drive_c/ProgramData"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.appendingPathComponent("prefix/" + path).path))
        }
        let savedGame = entry.prefix.appendingPathComponent("drive_c/users/player/Saved Games/save.dat")
        try "new save after switching".write(to: savedGame, atomically: true, encoding: .utf8)
        switched.shotglass.programs.append(Program(name: "Game", path: "prefix/drive_c/Program Files/Game/game.exe"))
        try switched.shotglass.save(in: switched.folder)
        let restored = try await ShotglassEngines.restore(backup, to: switched)
        XCTAssertEqual(restored.shotglass.runtime.id, old.id)
        XCTAssertEqual(restored.shotglass.programs.count, 1)
        XCTAssertEqual(try String(contentsOf: savedGame), "new save after switching")
        XCTAssertEqual(try String(contentsOf: restored.prefix.appendingPathComponent("drive_c/windows/system32/engine-state")), "original environment")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: restored.prefix.appendingPathComponent("dosdevices/c:").path), "../drive_c")
        XCTAssertEqual(try ShotglassEngines.backups(for: restored).count, 2)
        try ShotglassEngines.delete(backup, from: restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.path))
        XCTAssertEqual(try String(contentsOf: savedGame), "new save after switching")
        XCTAssertFalse(restored.engineChangePending)
    }

    func testFailedMigrationAutomaticallyRestoresWineWithoutTouchingApps() async throws {
        let root = try fixture()
        let old = try engine(in: root, name: "old")
        let broken = try engine(in: root, name: "broken", fails: true)
        let entry = try shotglass(in: root, runtime: old)
        do { _ = try await ShotglassEngines.change(entry, to: broken); XCTFail("Expected update failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("have been restored")) }
        XCTAssertEqual(try Shotglass.load(from: entry.folder).runtime.id, old.id)
        XCTAssertEqual(try String(contentsOf: entry.prefix.appendingPathComponent("drive_c/windows/system32/engine-state")), "original environment")
        XCTAssertEqual(try String(contentsOf: entry.prefix.appendingPathComponent("drive_c/Program Files/Game/game.exe")), "installed app data")
        XCTAssertFalse(entry.engineChangePending)
    }

    func testEngineCanBeChangedBeforeInitialization() async throws {
        let root = try fixture()
        let old = try engine(in: root, name: "old")
        let replacement = try engine(in: root, name: "replacement")
        let entry = try ShotglassFiles.create(Shotglass(name: "Not initialized", runtime: old, graphics: .wine), parent: root)
        let changed = try await ShotglassEngines.change(entry, to: replacement)
        XCTAssertEqual(try Shotglass.load(from: entry.folder).runtime.id, replacement.id)
        XCTAssertFalse(changed.shotglass.initialized)
        XCTAssertTrue(try ShotglassEngines.backups(for: changed).isEmpty)
    }

    func testSwitchReplacesDXVKAndRestoresItsPreviousVersion() async throws {
        let root = try fixture()
        let old = try engine(in: root, name: "old")
        var replacement = try engine(in: root, name: "replacement")
        var entry = try shotglass(in: root, runtime: old)
        func package(_ name: String) throws -> URL {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("x64"), withIntermediateDirectories: true)
            for dll in ["d3d11.dll", "d3d10core.dll"] { try Data(name.utf8).write(to: folder.appendingPathComponent("x64/" + dll)) }
            return folder
        }
        let originalDLL = entry.prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll")
        try Data("Wine builtin".utf8).write(to: originalDLL)
        try Wine.installDXVK(from: package("old-DXVK"), into: entry.prefix)
        entry.shotglass.graphics = .dxvk; try entry.shotglass.save(in: entry.folder)
        replacement.dxvkPackage = try package("replacement-DXVK")
        let switched = try await ShotglassEngines.change(entry, to: replacement)
        XCTAssertEqual(try String(contentsOf: originalDLL), "replacement-DXVK")
        XCTAssertEqual(try String(contentsOf: originalDLL.appendingPathExtension("spicedrum-original")), "Wine builtin")
        let backup = try XCTUnwrap(ShotglassEngines.backups(for: switched).first)
        _ = try await ShotglassEngines.restore(backup, to: switched)
        XCTAssertEqual(try String(contentsOf: originalDLL), "old-DXVK")
    }

    func testShotglassCanSwitchBetweenDXVKAndD3DMetal() async throws {
        let root = try fixture()
        var runtime = try engine(in: root, name: "graphics")
        runtime.d3dMetal = true
        let package = root.appendingPathComponent("DXVK", isDirectory: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("x64"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("x32"), withIntermediateDirectories: true)
        for arch in ["x64", "x32"] {
            for dll in ["d3d11.dll", "d3d10core.dll"] {
                try Data("DXVK".utf8).write(to: package.appendingPathComponent("\(arch)/\(dll)"))
            }
        }
        runtime.dxvkPackage = package
        var entry = try shotglass(in: root, runtime: runtime)
        let originalDLL = entry.prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll")
        try Data("Wine builtin".utf8).write(to: originalDLL)
        try Wine.installDXVK(from: package, into: entry.prefix)
        entry.shotglass.graphics = .dxvk
        try entry.shotglass.save(in: entry.folder)

        let metal = try await ShotglassGraphics.change(entry, to: .metal)
        XCTAssertEqual(metal.shotglass.graphics, .metal)
        XCTAssertEqual(try Data(contentsOf: originalDLL), Data("Wine builtin".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalDLL.appendingPathExtension("spicedrum-original").path))

        let dxvk = try await ShotglassGraphics.change(metal, to: .dxvk)
        XCTAssertEqual(dxvk.shotglass.graphics, .dxvk)
        XCTAssertEqual(try Data(contentsOf: originalDLL), Data("DXVK".utf8))
        XCTAssertEqual(try Data(contentsOf: originalDLL.appendingPathExtension("spicedrum-original")), Data("Wine builtin".utf8))
    }

    func testD3DMetalCannotBeSelectedWhenEngineDoesNotSupportIt() async throws {
        let root = try fixture()
        let runtime = try engine(in: root, name: "wine-only")
        let entry = try ShotglassFiles.create(Shotglass(name: "Wine only", runtime: runtime, graphics: .wine), parent: root)
        do {
            _ = try await ShotglassGraphics.change(entry, to: .metal)
            XCTFail("Expected unsupported D3DMetal selection to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("does not provide"))
        }
        XCTAssertEqual(try Shotglass.load(from: entry.folder).graphics, .wine)
    }

    func testWinetricksListParsesCategoriesAndFiltersNonVerbLines() {
        let dependencies = Dependencies.parseListAll("""
        | ===== apps =====
        | heroic Helper Application [downloadable]
        | ===== dlls =====
        | vcrun2022 Visual C++ 2015-2022 [downloadable]
        | invalid/verb This must be skipped
        | ===== settings =====
        | win10 Set Windows version to Windows 10
        """)
        XCTAssertEqual(dependencies.first(where: { $0.id == "heroic" })?.category, "apps")
        XCTAssertEqual(dependencies.first(where: { $0.id == "vcrun2022" })?.title, "Visual C++ 2015-2022 [downloadable]")
        XCTAssertEqual(dependencies.first(where: { $0.id == "win10" })?.category, "settings")
        XCTAssertFalse(dependencies.contains(where: { $0.id == "invalid/verb" }))
        XCTAssertTrue(dependencies.contains(where: { $0.id == "corefonts" }))
    }

    func testDXVKReleasePageIncludesOnlyMacOSPackages() {
        func asset(_ id: Int, _ name: String) -> EngineAsset {
            EngineAsset(id: id, name: name, size: 100, digest: nil,
                        browser_download_url: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1/\(name)")!)
        }
        let page = EngineInstaller.dxvkReleasePage([
            asset(1, "dxvk-macOS-async-v1.tar.gz"),
            asset(2, "dxvk-macOS-source.tar.gz"),
            asset(3, "dxvk-linux.tar.gz"),
            asset(4, "notes.txt")
        ], page: 2, link: "<https://api.github.com/releases?page=3>; rel=\"next\"")
        XCTAssertEqual(page.assets.map(\.id), [1])
        XCTAssertEqual(page.nextPage, 3)
    }

    func testRecoveryBackupCannotBeDeletedUntilRestored() async throws {
        let root = try fixture()
        let old = try engine(in: root, name: "old")
        let broken = try engine(in: root, name: "broken", fails: true, failsStop: true)
        let entry = try shotglass(in: root, runtime: old)
        do { _ = try await ShotglassEngines.change(entry, to: broken); XCTFail("Expected recovery failure") } catch {}
        XCTAssertTrue(entry.engineChangePending)
        let backup = try XCTUnwrap(ShotglassEngines.backups(for: entry).first)
        XCTAssertThrowsError(try ShotglassEngines.delete(backup, from: entry))
        try "#!/bin/sh\nexit 0\n".write(to: broken.executable.deletingLastPathComponent().appendingPathComponent("wineserver"), atomically: false, encoding: .utf8)
        let restored = try await ShotglassEngines.restore(backup, to: entry)
        XCTAssertFalse(restored.engineChangePending)
        try ShotglassEngines.delete(backup, from: restored)
    }

    func testReleaseHistoryPaginationAndOlderAssetsWithoutChecksums() {
        func asset(_ id: Int, _ name: String) -> EngineAsset {
            EngineAsset(id: id, name: name, size: 100, digest: nil, browser_download_url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/old/\(name)")!)
        }
        let old = asset(1, "wine-staging-8.0.tar.xz")
        let page = EngineInstaller.releasePage([old, old, asset(2, "Wine32Bit.tar.xz"), asset(3, "notes.txt")], page: 4, link: "<https://api.github.com/releases?page=5>; rel=\"next\"")
        XCTAssertEqual(page.assets.map(\.id), [1])
        XCTAssertFalse(page.assets[0].verifiedDownload)
        XCTAssertEqual(page.nextPage, 5)
        XCTAssertNil(EngineInstaller.releasePage([], page: 5, link: nil).nextPage)
    }

    func testOptionalRealWineEngineSwitchAndRestore() async throws {
        guard let first = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_WINE"],
              let second = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_OTHER_WINE"] else {
            throw XCTSkip("Set SPICED_RUM_TEST_WINE and SPICED_RUM_TEST_OTHER_WINE to test switching real macOS Wine versions.")
        }
        let root = try fixture()
        var original = Runtime(name: "Original Wine", executable: URL(fileURLWithPath: first), useRosetta: true, d3dMetal: false, version: "")
        var alternate = Runtime(name: "Alternate Wine", executable: URL(fileURLWithPath: second), useRosetta: true, d3dMetal: false, version: "")
        original.version = try await Wine.probe(original); alternate.version = try await Wine.probe(alternate)
        XCTAssertNotEqual(original.version, alternate.version)
        let created = try ShotglassFiles.create(Shotglass(name: "Real compatibility switch", runtime: original, graphics: .wine), parent: root)
        addTeardownBlock {
            if (self.testRun?.failureCount ?? 0) > 0 {
                print("Engine-switch integration log:\n" + String(((try? String(contentsOf: created.log, encoding: .utf8)) ?? "").suffix(12000)))
            }
            if let model = try? Shotglass.load(from: created.folder) { try? await Wine.stopServer(ShotglassEntry(shotglass: model, folder: created.folder)) }
        }
        let ready = try await Wine.initialize(created, dxvk: nil)
        let apps = ready.prefix.appendingPathComponent("drive_c/Program Files/Compatibility Test")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let gameData = apps.appendingPathComponent("game.dat")
        try Data("preserve installed app".utf8).write(to: gameData)
        let switched = try await ShotglassEngines.change(ready, to: alternate)
        try await Wine.execute(runtime: alternate, arguments: ["cmd", "/c", "exit", "0"], environment: Wine.environment(for: switched), directory: switched.folder, log: switched.log, timeout: 60)
        let backup = try XCTUnwrap(ShotglassEngines.backups(for: switched).first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.appendingPathComponent("prefix/drive_c/Program Files").path))
        let restored = try await ShotglassEngines.restore(backup, to: switched)
        XCTAssertEqual(restored.shotglass.runtime.version, original.version)
        try await Wine.execute(runtime: original, arguments: ["cmd", "/c", "exit", "0"], environment: Wine.environment(for: restored), directory: restored.folder, log: restored.log, timeout: 60)
        XCTAssertEqual(try Data(contentsOf: gameData), Data("preserve installed app".utf8))
        try ShotglassEngines.delete(backup, from: restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.path))
    }
}
