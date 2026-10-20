import XCTest
@testable import SpicedRumCore

final class ShotglassTests: XCTestCase {
    func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func runtime(_ file: URL = URL(fileURLWithPath: "/usr/bin/true")) -> Runtime {
        Runtime(name: "Test Wine", executable: file, useRosetta: false, d3dMetal: false, version: "wine-test")
    }

    func testPortableShotglassAndPaths() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "../Games / Steam", runtime: runtime(), graphics: .wine), parent: root)
        XCTAssertEqual(entry.folder.deletingLastPathComponent().path, root.path)
        XCTAssertEqual(try Shotglass.load(from: entry.folder).name, "../Games / Steam")
        XCTAssertNil(try Shotglass.load(from: entry.folder).runtime.gptkVersion)
        let exe = entry.prefix.appendingPathComponent("drive_c/Program Files/Steam/Steam.exe")
        let program = Program(name: "Steam", path: ShotglassFiles.programPath(exe, in: entry))
        XCTAssertFalse(program.path.hasPrefix("/"))
        XCTAssertEqual(try ShotglassFiles.programURL(program, in: entry), exe)
        XCTAssertThrowsError(try ShotglassFiles.programURL(Program(name: "Escape", path: "../outside.exe"), in: entry))
        XCTAssertThrowsError(try ShotglassFiles.create(Shotglass(name: " ", runtime: runtime(), graphics: .wine), parent: root))
        XCTAssertThrowsError(try ShotglassFiles.create(entry.shotglass, parent: root))
    }

    func testShotglassRemovalValidationRejectsLinksAndStaleMetadata() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "Trash me", runtime: runtime(), graphics: .wine), parent: root)
        XCTAssertNoThrow(try ShotglassFiles.validateForRemoval(entry))

        var staleShotglass = entry.shotglass
        staleShotglass.id = UUID()
        XCTAssertThrowsError(try ShotglassFiles.validateForRemoval(ShotglassEntry(shotglass: staleShotglass, folder: entry.folder)))

        let link = root.appendingPathComponent("linked.spicedrum")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: entry.folder)
        XCTAssertThrowsError(try ShotglassFiles.validateForRemoval(ShotglassEntry(shotglass: entry.shotglass, folder: link)))
    }

    func testShotglassRenamePreservesIdentityAndFolder() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "Before", runtime: runtime(), graphics: .wine), parent: root)

        let renamed = try ShotglassFiles.rename(entry, to: "  After  ")

        XCTAssertEqual(renamed.id, entry.id)
        XCTAssertEqual(renamed.folder, entry.folder)
        XCTAssertEqual(renamed.shotglass.name, "After")
        XCTAssertEqual(try Shotglass.load(from: entry.folder).name, "After")
        XCTAssertThrowsError(try ShotglassFiles.rename(renamed, to: " \n "))
    }

    func testShotglassDuplicateCopiesEnvironmentAndShortcutsButNotBackupsOrLogs() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "Original", runtime: runtime(), graphics: .wine), parent: root)
        let executable = entry.prefix.appendingPathComponent("drive_c/Program Files/Game/Game.exe")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("game".utf8).write(to: executable)
        let dosdevices = entry.prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dosdevices.appendingPathComponent("c:").path, withDestinationPath: "../drive_c")
        try Data("registry".utf8).write(to: entry.prefix.appendingPathComponent("system.reg"))
        try Data("old log".utf8).write(to: entry.log)
        let backupFile = entry.folder.appendingPathComponent("engine-backups/backup/large-file")
        try FileManager.default.createDirectory(at: backupFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("backup".utf8).write(to: backupFile)
        var source = entry.shotglass
        source.initialized = true
        source.programs = [Program(name: "Game", path: ShotglassFiles.programPath(executable, in: entry))]
        try source.save(in: entry.folder)
        let currentEntry = ShotglassEntry(shotglass: source, folder: entry.folder)

        let duplicate = try ShotglassFiles.duplicate(currentEntry, name: "Game Copy")

        XCTAssertNotEqual(duplicate.id, currentEntry.id)
        XCTAssertEqual(duplicate.shotglass.name, "Game Copy")
        XCTAssertEqual(duplicate.shotglass.runtime, currentEntry.shotglass.runtime)
        XCTAssertTrue(duplicate.shotglass.initialized)
        XCTAssertNotEqual(duplicate.shotglass.programs.first?.id, currentEntry.shotglass.programs.first?.id)
        XCTAssertEqual(try Shotglass.load(from: duplicate.folder).id, duplicate.id)
        XCTAssertEqual(try Data(contentsOf: duplicate.prefix.appendingPathComponent("system.reg")), Data("registry".utf8))
        XCTAssertEqual(try Data(contentsOf: ShotglassFiles.programURL(try XCTUnwrap(duplicate.shotglass.programs.first), in: duplicate)), Data("game".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: duplicate.prefix.appendingPathComponent("dosdevices/c:").path), "../drive_c")
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.log.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.folder.appendingPathComponent("engine-backups").path))
        XCTAssertEqual(try Shotglass.load(from: currentEntry.folder).id, currentEntry.id)

        try Data("pending".utf8).write(to: currentEntry.folder.appendingPathComponent("engine-change.json"))
        XCTAssertThrowsError(try ShotglassFiles.duplicate(currentEntry, name: "Pending Copy"))
    }

    func testGPTKPayloadVersionPersistsInRuntimeMetadata() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "GPTK", runtime: runtime(), graphics: .wine), parent: root)
        var shotglass = entry.shotglass
        shotglass.runtime.d3dMetal = true
        shotglass.runtime.gptkVersion = "4.0 beta 10"
        try shotglass.save(in: entry.folder)
        let loaded = try Shotglass.load(from: entry.folder)
        XCTAssertTrue(loaded.runtime.d3dMetal)
        XCTAssertEqual(loaded.runtime.gptkVersion, "4.0 beta 10")
    }

    func testHeroicGPUWorkaroundSupportsInstalledAndPortableShortcuts() throws {
        var installed = Program(name: "Heroic", path: "prefix/drive_c/Program Files/Heroic/Heroic.exe")
        var portable = Program(name: "Heroic-2.22.3-Portable", path: "prefix/drive_c/Games/Heroic-2.22.3-Portable.exe")
        XCTAssertTrue(installed.isHeroicLauncher)
        XCTAssertTrue(portable.isHeroicLauncher)

        installed.setHeroicUIWorkaround(true)
        installed.setHeroicUIWorkaround(true)
        portable.setHeroicUIWorkaround(true)
        let flags = ["--use-gl=angle", "--use-angle=swiftshader", "--disable-gpu-rasterization"]
        XCTAssertEqual(installed.launchArguments, flags)
        XCTAssertEqual(portable.launchArguments, flags)
        XCTAssertTrue(installed.heroicUIWorkaroundEnabled)
        XCTAssertEqual(Wine.command(runtime: runtime(), arguments: ["Heroic.exe"] + installed.launchArguments).1, ["Heroic.exe"] + flags)

        installed.setHeroicUIWorkaround(false)
        XCTAssertTrue(installed.launchArguments.isEmpty)
        let roundTrip = try JSONDecoder().decode(Program.self, from: JSONEncoder().encode(portable))
        XCTAssertEqual(roundTrip.launchArguments, flags)

        let savedWithUnsupportedMode = Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Heroic\",\"path\":\"prefix/drive_c/Heroic.exe\",\"launchArguments\":[\"--disable-gpu\",\"--single-process\",\"--disable-d3d11\",\"--disable-direct-composition\"]}".utf8)
        let migratedShortcut = try JSONDecoder().decode(Program.self, from: savedWithUnsupportedMode)
        XCTAssertEqual(migratedShortcut.launchArguments, flags)
        XCTAssertTrue(migratedShortcut.heroicUIWorkaroundEnabled)

        let savedWithOldSoftwareRenderer = Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Heroic\",\"path\":\"prefix/drive_c/Heroic.exe\",\"launchArguments\":[\"--use-gl=angle\",\"--use-angle=swiftshader\"]}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(Program.self, from: savedWithOldSoftwareRenderer).launchArguments, flags)

        let nonHeroic = Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Other\",\"path\":\"prefix/drive_c/Other.exe\",\"launchArguments\":[\"--single-process\"]}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(Program.self, from: nonHeroic).launchArguments, ["--single-process"])

        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Heroic\",\"path\":\"prefix/drive_c/Heroic.exe\"}".utf8)
        let oldShortcut = try JSONDecoder().decode(Program.self, from: legacy)
        XCTAssertTrue(oldShortcut.launchArguments.isEmpty)
    }

    func testLegacyLibraryAndMetadataRemainReadable() throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "Steam", runtime: runtime(), graphics: .wine), parent: root)
        let metadata = entry.folder.appendingPathComponent("shotglass.json")
        let legacyMetadata = entry.folder.appendingPathComponent("bottle.json")
        try FileManager.default.moveItem(at: metadata, to: legacyMetadata)
        XCTAssertEqual(try Shotglass.load(from: entry.folder).id, entry.id)
        var updated = entry.shotglass
        updated.name = "Updated Steam"
        try updated.save(in: entry.folder)
        XCTAssertEqual(try Shotglass.load(from: entry.folder).name, updated.name)
        // A damaged new file must not silently fall back to stale metadata.
        try Data("invalid".utf8).write(to: metadata)
        XCTAssertThrowsError(try Shotglass.load(from: entry.folder))

        var catalog = Catalog(defaultLocation: root)
        catalog.shotglassFolders = [entry.folder]
        catalog.runtimes = [entry.shotglass.runtime]
        let encoded = try JSONEncoder().encode(catalog)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(fields["bottleFolders"])
        fields["bottleFolders"] = fields.removeValue(forKey: "shotglassFolders")
        let migrated = try JSONDecoder().decode(Catalog.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(migrated.shotglassFolders, catalog.shotglassFolders)
        XCTAssertEqual(migrated.defaultLocation, root)
        XCTAssertEqual(migrated.runtimes, catalog.runtimes)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any])
        XCTAssertNotNil(saved["shotglassFolders"])
        XCTAssertNil(saved["bottleFolders"])
    }

    func testPrefixEnvironmentAndArguments() throws {
        let root = try fixture()
        var entry = try ShotglassFiles.create(Shotglass(name: "Steam", runtime: runtime(), graphics: .dxvk), parent: root)
        let env = Wine.environment(for: entry)
        XCTAssertEqual(env["WINEPREFIX"], entry.prefix.path)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "dxgi=b;d3d11,d3d10core=n,b")
        entry.shotglass.graphics = .wine
        XCTAssertNil(Wine.environment(for: entry)["WINEDLLOVERRIDES"])
        var intel = runtime(); intel.useRosetta = true
        let (_, args) = Wine.command(runtime: intel, arguments: ["/Games/a name;$(whoami).exe"])
        XCTAssertEqual(args, ["-x86_64", "/usr/bin/true", "/Games/a name;$(whoami).exe"])
    }

    func testDXMTBuiltinEnvironmentAndPackageValidation() throws {
        let root = try fixture()
        let package = root.appendingPathComponent("graphics/DXMT-v0.80/package", isDirectory: true)
        for file in ["x86_64-unix/winemetal.so", "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll"] {
            let path = package.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: path)
        }
        try Wine.validateDXMT(package)
        var engine = runtime()
        engine.dxmt = true
        engine.dxmtPackage = package
        var entry = try ShotglassFiles.create(Shotglass(name: "DXMT", runtime: engine, graphics: .dxmt), parent: root)
        XCTAssertEqual(Wine.environment(for: entry)["WINEDLLOVERRIDES"], "dxgi,d3d10core,d3d11,winemetal=b")
        XCTAssertEqual(Wine.environment(for: entry)["WINEDLLPATH_PREPEND"], package.path)
        XCTAssertEqual(Wine.environment(for: entry)["WINEMSYNC"], "1")
        XCTAssertTrue(ShotglassGraphics.choices(for: engine).contains(.dxmt))
        try FileManager.default.removeItem(at: package.appendingPathComponent("x86_64-windows/dxgi.dll"))
        XCTAssertFalse(ShotglassGraphics.choices(for: engine).contains(.dxmt))
        entry.shotglass.graphics = .wine
    }

    func testDXMTWineMetalDLLCanBeUpdatedAndRestoredWithoutLosingWineCopy() throws {
        let root = try fixture()
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let system32 = prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)
        let original64 = system32.appendingPathComponent("winemetal.dll")
        let original32 = syswow64.appendingPathComponent("winemetal.dll")
        try Data("Wine 64-bit builtin".utf8).write(to: original64)
        try Data("Wine 32-bit builtin".utf8).write(to: original32)

        func package(_ name: String, dll: String) throws -> URL {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            for (path, contents) in [
                ("x86_64-unix/winemetal.so", "unix"),
                ("x86_64-windows/winemetal.dll", dll),
                ("x86_64-windows/d3d11.dll", "d3d11"),
                ("x86_64-windows/dxgi.dll", "dxgi"),
                ("i386-windows/winemetal.dll", "32-bit " + dll)
            ] {
                let destination = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: destination)
            }
            return folder
        }
        let first = try package("DXMT-v0.80", dll: "DXMT 0.80")
        let second = try package("DXMT-v0.81", dll: "DXMT 0.81")

        try Wine.installDXMT(from: first, into: prefix)
        XCTAssertEqual(try String(contentsOf: original64), "DXMT 0.80")
        XCTAssertEqual(try String(contentsOf: original32), "32-bit DXMT 0.80")
        XCTAssertEqual(try String(contentsOf: original64.appendingPathExtension("spicedrum-original")), "Wine 64-bit builtin")
        XCTAssertEqual(try String(contentsOf: original32.appendingPathExtension("spicedrum-original")), "Wine 32-bit builtin")

        try Wine.removeDXMT(from: prefix)
        try Wine.installDXMT(from: second, into: prefix)
        XCTAssertEqual(try String(contentsOf: original64), "DXMT 0.81")
        XCTAssertEqual(try String(contentsOf: original64.appendingPathExtension("spicedrum-original")), "Wine 64-bit builtin")
        try Wine.removeDXMT(from: prefix)
        XCTAssertEqual(try String(contentsOf: original64), "Wine 64-bit builtin")
        XCTAssertEqual(try String(contentsOf: original32), "Wine 32-bit builtin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original64.appendingPathExtension("spicedrum-original").path))
    }

    func testDXMTAndBarrelReleaseFeedsOnlyExposeSupportedArchives() throws {
        func asset(_ id: Int, _ name: String, _ url: String, tag: String? = nil) -> EngineAsset {
            var result = EngineAsset(id: id, name: name, size: 100, digest: "sha256:" + String(repeating: "a", count: 64), browser_download_url: URL(string: url)!)
            result.releaseTag = tag
            return result
        }
        let barrel = asset(1, "barrel-wine-26.3.0.tar.xz", "https://github.com/MrTuNNe/Barrel/releases/download/wine-cx-26.3.0/barrel-wine-26.3.0.tar.xz", tag: "wine-cx-26.3.0")
        let unrelatedBarrel = asset(2, "Barrel-0.4.2.dmg", "https://github.com/MrTuNNe/Barrel/releases/download/v0.4.2/Barrel-0.4.2.dmg", tag: "v0.4.2")
        let barrelPage = EngineInstaller.releasePage([barrel, unrelatedBarrel], feed: .barrelWine, page: 1, link: nil)
        XCTAssertEqual(barrelPage.assets.map(\.id), [1])
        XCTAssertEqual(barrel.installedName(in: .barrelWine), "Barrel Wine · CrossOver 26.3.0")

        let dxmt = asset(3, "dxmt-v0.80-builtin.tar.gz", "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz", tag: "v0.80")
        let source = asset(4, "Source code (tar.gz)", "https://github.com/3Shain/dxmt/archive/refs/tags/v0.80.tar.gz", tag: "v0.80")
        let dxmtPage = EngineInstaller.dxmtReleasePage([dxmt, source], page: 1, link: nil)
        XCTAssertEqual(dxmtPage.assets.map(\.id), [3])
    }

    func testDXMTPackageDiscoveryAndRuntimeMigration() throws {
        let root = try fixture()
        let managed = root.appendingPathComponent("Engines/Barrel", isDirectory: true)
        let package = managed.appendingPathComponent("graphics/DXMT-v0.80/package", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: managed.appendingPathComponent("barrel-wine.json"))
        for file in ["x86_64-unix/winemetal.so", "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll"] {
            let path = package.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: path)
        }
        var engine = Runtime(name: "Barrel Wine · CrossOver 26.3.0", executable: managed.appendingPathComponent("bin/wine"), useRosetta: true, d3dMetal: false, dxmt: true, version: "Wine")
        engine.managedRoot = managed
        engine.dxmtPackage = package
        XCTAssertTrue(EngineInstaller.supportsDXMTVersions(engine))
        XCTAssertEqual(EngineInstaller.installedDXMTPackages(for: engine).map(\.title), ["v0.80"])

        var oldFields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine)) as? [String: Any])
        oldFields.removeValue(forKey: "dxmtPackage")
        let migrated = try JSONDecoder().decode(Runtime.self, from: JSONSerialization.data(withJSONObject: oldFields))
        XCTAssertNil(migrated.dxmtPackage)
        XCTAssertTrue(migrated.dxmt)
    }

    func testBarrelTemplateVersionsSortByNumericComponents() {
        func asset(_ id: Int, _ name: String) -> EngineAsset {
            EngineAsset(id: id, name: name, size: 1, digest: nil,
                        browser_download_url: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(name)")!)
        }
        let base = asset(1, "Template-1.0.tar.xz")
        let latest = asset(2, "Template-1.0.24.tar.xz")
        XCTAssertEqual(EngineInstaller.newestBarrelTemplateAsset(in: [base, latest])?.name, latest.name)
        XCTAssertEqual(EngineInstaller.newestBarrelTemplateAsset(in: [asset(3, "Template-1.0.9.tar.xz"), asset(4, "Template-1.0.10.tar.xz")])?.name, "Template-1.0.10.tar.xz")
    }

    func testBarrelWineLauncherSetsRuntimeEnvironmentAfterRosettaStarts() throws {
        let root = try fixture().appendingPathComponent("Barrel", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let frameworks = root.appendingPathComponent("support/Template-1.0.24.app/Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try Data("KosmicKrisp".utf8).write(to: frameworks.appendingPathComponent("libvulkan_kosmickrisp.dylib"))
        let wine = try EngineInstaller.barrelWineLaunchers(in: root, templateName: "Template-1.0.24")
        let script = try String(contentsOf: wine, encoding: .utf8)
        XCTAssertTrue(script.contains("DYLD_FALLBACK_LIBRARY_PATH=\"$frameworks:$frameworks/GStreamer.framework/Libraries:/usr/lib\""))
        XCTAssertTrue(script.contains("export VK_DRIVER_FILES=\"$engine_dir/barrel-vulkan-icd.json\""))
        XCTAssertTrue(script.contains("export WINEMSYNC=1"))
        XCTAssertTrue(script.contains("exec \"$engine_dir/bin/wine\" \"$@\""))

        let moved = root.deletingLastPathComponent().appendingPathComponent("relocated Barrel")
        try FileManager.default.moveItem(at: root, to: moved)
        try EngineInstaller.writeBarrelVulkanManifest(in: moved, templateName: "Template-1.0.24")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: moved.appendingPathComponent("barrel-vulkan-icd.json"))) as? [String: Any])
        let icd = try XCTUnwrap(manifest["ICD"] as? [String: String])
        XCTAssertEqual(icd["library_path"], moved.appendingPathComponent("support/Template-1.0.24.app/Contents/Frameworks/libvulkan_kosmickrisp.dylib").path)

        let relocatedWine = moved.appendingPathComponent("spiced-rum-barrel-launchers/wine")
        var engine = Runtime(name: "Barrel Wine", executable: relocatedWine, useRosetta: true, d3dMetal: false, dxmt: true, version: "Wine")
        engine.managedRoot = moved
        try Data("{}".utf8).write(to: moved.appendingPathComponent("barrel-wine.json"))
        let entry = try ShotglassFiles.create(Shotglass(name: "Barrel", runtime: engine, graphics: .dxmt), parent: moved.appendingPathComponent("shotglasses"))
        XCTAssertEqual(Wine.environment(for: entry)["WINEMSYNC"], "1")
        XCTAssertEqual(Wine.environment(for: entry)["WINEBOOT_HIDE_DIALOG"], "1")
        XCTAssertEqual(Wine.environment(for: entry)["ROSETTA_ADVERTISE_AVX"], "1")
        let (binary, arguments) = Wine.command(runtime: engine, arguments: ["--version"])
        XCTAssertEqual(binary.path, "/usr/bin/arch")
        XCTAssertEqual(arguments, ["-x86_64", relocatedWine.path, "--version"])
        XCTAssertTrue(Wine.environment(for: entry)["PATH"]?.contains(moved.appendingPathComponent("bin").path) == true)
    }

    func testFailedEngineInstallLogIsPreservedForReview() throws {
        let root = try fixture()
        let engines = root.appendingPathComponent("Engines", isDirectory: true)
        let id = UUID()
        let engine = engines.appendingPathComponent(id.uuidString, isDirectory: true)
        let shotglass = engine.appendingPathComponent("validation.spicedrum", isDirectory: true)
        try FileManager.default.createDirectory(at: shotglass, withIntermediateDirectories: true)
        try Data("Wine failure details".utf8).write(to: shotglass.appendingPathComponent("session.log"))

        let saved = try XCTUnwrap(EngineInstaller.preserveFailedSetupLog(in: engine, under: engines, id: id))
        try FileManager.default.removeItem(at: engine)
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Wine failure details")
        XCTAssertTrue(saved.path.contains("Install Logs"))
    }

    func testRejectsLinuxRuntimeBeforeExecution() throws {
        let elf = try fixture().appendingPathComponent("wine")
        try Data([0x7f, 0x45, 0x4c, 0x46, 0]).write(to: elf)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: elf.path)
        XCTAssertThrowsError(try Wine.checkExecutable(elf)) { XCTAssertTrue($0.localizedDescription.contains("Linux")) }
    }

    func testDXVKInstallationPreservesRuntimeSymlinks() throws {
        let root = try fixture()
        let source = root.appendingPathComponent("dxvk/x64")
        let prefix = root.appendingPathComponent("prefix")
        let windows = prefix.appendingPathComponent("drive_c/windows/system32")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        let shared = root.appendingPathComponent("shared-d3d11.dll")
        try Data("Wine original".utf8).write(to: shared)
        try FileManager.default.createSymbolicLink(at: windows.appendingPathComponent("d3d11.dll"), withDestinationURL: shared)
        for file in ["d3d11.dll", "d3d10core.dll"] { try Data("DXVK".utf8).write(to: source.appendingPathComponent(file)) }
        let package = source.deletingLastPathComponent()
        try Wine.validateDXVK(package)
        try Wine.installDXVK(from: package, into: prefix)
        XCTAssertEqual(try String(contentsOf: shared), "Wine original")
        XCTAssertEqual(try String(contentsOf: windows.appendingPathComponent("d3d11.dll")), "DXVK")
        try Wine.installDXVK(from: package, into: prefix)
        XCTAssertEqual(try String(contentsOf: windows.appendingPathComponent("d3d11.dll.spicedrum-original")), "Wine original")
        XCTAssertThrowsError(try Wine.validateDXVK(root))
    }

    func testProcessLogsAndFailureRecovery() async throws {
        let root = try fixture()
        let entry = try ShotglassFiles.create(Shotglass(name: "Process", runtime: runtime(), graphics: .wine), parent: root)
        try await Wine.execute(runtime: runtime(), arguments: ["a path with spaces"], environment: Wine.environment(for: entry), directory: root, log: entry.log)
        XCTAssertTrue(try String(contentsOf: entry.log).contains("a path with spaces"))
        do {
            try await Wine.execute(runtime: runtime(URL(fileURLWithPath: "/usr/bin/false")), arguments: [], environment: Wine.environment(for: entry), directory: root, log: entry.log)
            XCTFail("Nonzero exits must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("code 1")) }
        do { _ = try await Wine.initialize(entry, dxvk: nil); XCTFail("A successful process without a prefix must not mark a shotglass ready") }
        catch { XCTAssertFalse(try Shotglass.load(from: entry.folder).initialized) }
    }

    func testStopServerIsScopedToSelectedShotglass() async throws {
        let root = try fixture()
        let engine = root.appendingPathComponent("engine", isDirectory: true)
        try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
        let wine = engine.appendingPathComponent("wine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wine)
        let calls = root.appendingPathComponent("wineserver-calls.log")
        let server = engine.appendingPathComponent("wineserver")
        let script = "#!/bin/sh\nprintf '%s|%s\\n' \"$WINEPREFIX\" \"$*\" >> '\(calls.path)'\n"
        try Data(script.utf8).write(to: server)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)

        let engineRuntime = runtime(wine)
        let selected = try ShotglassFiles.create(Shotglass(name: "Selected", runtime: engineRuntime, graphics: .wine), parent: root)
        let other = try ShotglassFiles.create(Shotglass(name: "Other", runtime: engineRuntime, graphics: .wine), parent: root)
        try await Wine.stopServer(selected)

        let lines = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["\(selected.prefix.path)|-k", "\(selected.prefix.path)|-w"])
        XCTAssertFalse(lines.contains { $0.contains(other.prefix.path) })
    }

    func testOptionalRealWineX64Smoke() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_WINE"] else {
            throw XCTSkip("Set SPICED_RUM_TEST_WINE to a complete macOS Wine runtime to test a real x64 prefix.")
        }
        let root = try fixture()
        let engine = Runtime(name: "Integration Wine", executable: URL(fileURLWithPath: path), useRosetta: true, d3dMetal: false, version: "")
        let version = try await Wine.probe(engine)
        XCTAssertTrue(version.lowercased().contains("wine"))
        let entry = try ShotglassFiles.create(Shotglass(name: "x64 Smoke", runtime: engine, graphics: .wine), parent: root)
        let ready: ShotglassEntry
        do { ready = try await Wine.initialize(entry, dxvk: nil) }
        catch { XCTFail((try? String(contentsOf: entry.log)) ?? error.localizedDescription); throw error }
        XCTAssertTrue(ready.shotglass.initialized)
        try await Wine.execute(runtime: engine, arguments: ["cmd", "/c", "echo", "SPICED_RUM_X64_OK"], environment: Wine.environment(for: ready), directory: ready.folder, log: ready.log)
        let lines = try String(contentsOf: ready.log).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertTrue(lines.contains("SPICED_RUM_X64_OK"))
        XCTAssertTrue(try String(contentsOf: ready.prefix.appendingPathComponent("system.reg")).contains("#arch=win64"))
        if ProcessInfo.processInfo.environment["SPICED_RUM_TEST_COMPONENTS"] == "1" {
            let dependency = try XCTUnwrap(Dependencies.recommended.first { $0.rawValue == "d3dcompiler_47" })
            try await Dependencies.install(dependency, in: ready)
            try EngineInstaller.verify(ready.prefix.appendingPathComponent("drive_c/windows/system32/d3dcompiler_47.dll"), digest: "sha256:4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3")
        }
        try await Wine.execute(runtime: engine, arguments: ["wineboot", "--shutdown", "--force", "--kill"], environment: Wine.environment(for: ready), directory: ready.folder, log: ready.log)
    }

    func testEngineDownloadTrustChecks() throws {
        let folder = try fixture()
        let file = folder.appendingPathComponent("asset")
        try Data("abc".utf8).write(to: file)
        try EngineInstaller.verify(file, digest: "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try EngineInstaller.verify(file, digest: "sha256:" + String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try EngineInstaller.verify(file, digest: "sha256:bad"))
        try EngineInstaller.validateArchivePaths("wine/bin/wine\n./wine/lib/ntdll.so\n")
        XCTAssertThrowsError(try EngineInstaller.validateArchivePaths("../escape\n"))
        XCTAssertThrowsError(try EngineInstaller.validateArchivePaths("/absolute\n"))
        XCTAssertThrowsError(try EngineInstaller.validateArchivePaths("wine/../../escape\n"))
    }

    func testOptionalEngineDownloadAndSetup() async throws {
        guard ProcessInfo.processInfo.environment["SPICED_RUM_TEST_DOWNLOADS"] == "1" else {
            throw XCTSkip("Set SPICED_RUM_TEST_DOWNLOADS=1 to verify a real official engine download, graphics setup and x64 startup.")
        }
        let assets = try await EngineInstaller.releases(.wineHQ).assets
        let asset = try XCTUnwrap(assets.first { $0.name.contains("wine-staging") && $0.verifiedDownload })
        let runtime = try await EngineInstaller.install(asset, feed: .wineHQ, into: fixture()) { _, _ in }
        XCTAssertNotNil(runtime.dxvkPackage)
        XCTAssertEqual(runtime.defaultGraphics, .dxvk)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.executable.path))
        try Wine.validateDXVK(runtime.dxvkPackage)
    }

    func testOptionalBarrelWineDownloadAndSetup() async throws {
        guard ProcessInfo.processInfo.environment["SPICED_RUM_TEST_BARREL"] == "1" else {
            throw XCTSkip("Set SPICED_RUM_TEST_BARREL=1 to verify the official Barrel engine, support libraries, Vulkan driver and Windows x64 startup.")
        }
        let assets = try await EngineInstaller.releases(.barrelWine).assets
        let asset = try XCTUnwrap(assets.first(where: \.verifiedDownload))
        let engines = try fixture()
        let runtime = try await EngineInstaller.install(asset, feed: .barrelWine, into: engines) { _, _ in }
        XCTAssertTrue(runtime.dxmt)
        XCTAssertEqual(runtime.defaultGraphics, .dxmt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.executable.path))
        let manifest = try XCTUnwrap(runtime.managedRoot?.appendingPathComponent("barrel-vulkan-icd.json"))
        let icd = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])?["ICD"] as? [String: String])
        XCTAssertTrue(icd["library_path"]?.hasSuffix("libvulkan_kosmickrisp.dylib") == true)
    }

    func testSikarugirLibrariesStayPortableAndPreserveEngineFiles() async throws {
        let root = try fixture()
        let engine = root.appendingPathComponent("wswine.bundle")
        let template = engine.appendingPathComponent("support/Test.app")
        let frameworks = template.appendingPathComponent("Contents/Frameworks")
        let media = frameworks.appendingPathComponent("GStreamer.framework/Versions/1.0/lib")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: engine.appendingPathComponent("lib"), withIntermediateDirectories: true)
        for name in ["libinotify.0.dylib", "libfreetype.6.dylib"] { try Data(name.utf8).write(to: frameworks.appendingPathComponent(name)) }
        try Data("media".utf8).write(to: media.appendingPathComponent("libgstreamer-1.0.0.dylib"))
        try Data("engine original".utf8).write(to: engine.appendingPathComponent("lib/libfreetype.6.dylib"))
        try EngineInstaller.linkTemplateLibraries(template: template, engine: engine)
        try EngineInstaller.linkTemplateLibraries(template: template, engine: engine)
        try FileManager.default.createDirectory(at: engine.appendingPathComponent("bin"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: engine.appendingPathComponent("bin/wine"), withDestinationURL: URL(fileURLWithPath: "/usr/bin/printf"))
        _ = try EngineInstaller.sikarugirLaunchers(in: engine)
        let moved = root.appendingPathComponent("relocated engine")
        try FileManager.default.moveItem(at: engine, to: moved)
        let relocatedLauncher = moved.appendingPathComponent("spiced-rum-launchers/wine")
        let runtime = Runtime(name: "Launcher test", executable: relocatedLauncher, useRosetta: true, d3dMetal: false, version: "")
        let (binary, arguments) = Wine.command(runtime: runtime, arguments: ["%s", "a path with spaces; literal $value"])
        let output = try await ProcessRunner.capture(binary, arguments)
        XCTAssertEqual(output, "a path with spaces; literal $value")
        XCTAssertEqual(try String(contentsOf: moved.appendingPathComponent("lib/libfreetype.6.dylib")), "engine original")
        for lib in ["lib", "lib/wine/x86_64-unix"] {
            XCTAssertEqual(try String(contentsOf: moved.appendingPathComponent(lib + "/libinotify.0.dylib")), "libinotify.0.dylib")
            XCTAssertEqual(try String(contentsOf: moved.appendingPathComponent(lib + "/libgstreamer-1.0.0.dylib")), "media")
        }
        let external = root.appendingPathComponent("external.dylib")
        try Data().write(to: external)
        let movedTemplate = moved.appendingPathComponent("support/Test.app")
        try FileManager.default.createSymbolicLink(at: movedTemplate.appendingPathComponent("Contents/Frameworks/escape.dylib"), withDestinationURL: external)
        XCTAssertThrowsError(try EngineInstaller.linkTemplateLibraries(template: movedTemplate, engine: moved))
        let module = moved.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        try Data("SikarugirAppWine11".utf8).write(to: module)
        XCTAssertThrowsError(try EngineInstaller.validateStandaloneSikarugir(moved.appendingPathComponent("bin/wine"))) { error in
            XCTAssertTrue(error.localizedDescription.contains("publisher's own launcher"))
        }
    }

    func testReleaseAssetsAreSortedByUploadDate() throws {
        let data = Data("""
        [
          {"id":1,"name":"WS11Wine10.0_3.tar.xz","size":100,"created_at":"2025-08-21T12:30:35Z","browser_download_url":"https://github.com/old"},
          {"id":2,"name":"WS12WineSikarugir11.0_1.tar.xz","size":100,"created_at":"2026-10-17T12:00:00Z","browser_download_url":"https://github.com/new"}
        ]
        """.utf8)
        let assets = try JSONDecoder().decode([EngineAsset].self, from: data)
        XCTAssertEqual(EngineInstaller.releasePage(assets, page: 1, link: nil).assets.map(\.id), [2, 1])
        XCTAssertTrue(assets[1].requiresSikarugirLauncher)
        XCTAssertFalse(assets[0].requiresSikarugirLauncher)
    }

    func testEngineRelocationKeepsWhiskyBinLauncherSymlinks() throws {
        let root = try fixture()
        let content = root.appendingPathComponent("install/content", isDirectory: true)
        let wineRoot = content.appendingPathComponent("Libraries/Wine", isDirectory: true)
        let bin = wineRoot.appendingPathComponent("bin", isDirectory: true)
        let unix = wineRoot.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        let internalWine = unix.appendingPathComponent("wine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: internalWine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: internalWine.path)
        let publicWine = bin.appendingPathComponent("wine64")
        try FileManager.default.createSymbolicLink(atPath: publicWine.path, withDestinationPath: "../lib/wine/x86_64-unix/wine")

        let selected = try EngineInstaller.findWine(in: content)
        XCTAssertEqual(selected.standardizedFileURL, publicWine.standardizedFileURL)
        let relative = try EngineInstaller.relativeExecutablePath(in: content, executable: selected)
        XCTAssertEqual(relative, "Libraries/Wine/bin/wine64")

        let destination = root.appendingPathComponent("installed-engine", isDirectory: true)
        try FileManager.default.moveItem(at: content, to: destination)
        let relocated = destination.appendingPathComponent(relative)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: relocated.path))
        XCTAssertTrue(try relocated.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: relocated.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine").path))
    }

    func testWhiskyCommunityRuntimeReleaseFeedAndChecksums() throws {
        let hash = "c8e6a10dfeb54fc16d3dd3382ee2e9d2cec3eb1f5641613cad8b07903818cb12"
        let apiPayload = """
        [{
          "tag_name":"v4.6.4-beta.1",
          "name":"Wine Libraries v4.6.4-beta.1 (GPTK, Wine 11.16)",
          "body":"Known limitation: Steam's login stalls under this Wine base.\\n\\nSHA-256 (`Libraries.tar.gz`): `\(hash)`",
          "assets":[{
            "id":10,
            "name":"Libraries.tar.gz",
            "size":481348675,
            "digest":null,
            "browser_download_url":"https://github.com/frankea/Whisky/releases/download/v4.6.4-beta.1/Libraries.tar.gz",
            "created_at":"2026-08-29T08:27:00Z"
          }]
        }]
        """
        let releases = try JSONDecoder().decode([EngineRelease].self, from: Data(apiPayload.utf8))
        let whisky = try XCTUnwrap(EngineInstaller.releaseAssets(from: releases, feed: .whisky).first)
        let releaseNotes = """
        Known limitation: Steam's login stalls under this Wine base.

        SHA-256 (`Libraries.tar.gz`): `\(hash)`
        """
        XCTAssertEqual(whisky.digest, "sha256:\(hash)")
        XCTAssertEqual(whisky.releaseNotes, releaseNotes)
        let unrelated = EngineAsset(
            id: 11,
            name: "source.tar.gz",
            size: 100,
            digest: nil,
            browser_download_url: URL(string: "https://github.com/frankea/Whisky/releases/download/v4.6.4-beta.1/source.tar.gz")!
        )

        XCTAssertEqual(EngineFeed.whisky.repository, "frankea/Whisky")
        XCTAssertEqual(EngineInstaller.publisherChecksum(in: releaseNotes, for: "Libraries.tar.gz"), "sha256:\(hash)")
        XCTAssertEqual(whisky.displayName(in: .whisky), "Wine Libraries v4.6.4-beta.1 (GPTK, Wine 11.16)")
        XCTAssertEqual(whisky.installedName(in: .whisky), "Whisky community runtime v4.6.4-beta.1")
        XCTAssertTrue(whisky.reportsSteamLoginIssue)
        XCTAssertTrue(whisky.requiresAppleGPTKPayload)

        let page = EngineInstaller.releasePage([whisky, unrelated], feed: .whisky, page: 1, link: nil)
        XCTAssertEqual(page.assets.map(\.id), [10])
    }

    func testOptionalSikarugirDownloadAndSetup() async throws {
        guard let requested = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_SIKARUGIR"] else {
            throw XCTSkip("Set SPICED_RUM_TEST_SIKARUGIR to an engine archive name to test its real download, support libraries and Windows x64 startup.")
        }
        let assets = try await EngineInstaller.releases(.sikarugir).assets
        let asset = try XCTUnwrap(assets.first { $0.name == requested })
        let runtime = try await EngineInstaller.install(asset, feed: .sikarugir, into: fixture()) { message, _ in print(message) }
        XCTAssertEqual(runtime.defaultGraphics, .wine)
        let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: engine.appendingPathComponent("lib/libinotify.0.dylib").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: engine.appendingPathComponent("support/download-receipt.json").path))
    }

    func testOptionalWhiskyCommunityRuntimeDownloadAndSetup() async throws {
        guard let requested = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_WHISKY"] else {
            throw XCTSkip("Set SPICED_RUM_TEST_WHISKY to a Whisky Wine Libraries release tag to verify its real download, checksum and Windows x64 startup.")
        }
        let assets = try await EngineInstaller.releases(.whisky).assets
        let asset = try XCTUnwrap(assets.first { $0.releaseTag == requested && $0.verifiedDownload })
        let runtime = try await EngineInstaller.install(asset, feed: .whisky, into: fixture()) { message, _ in print(message) }
        XCTAssertTrue(runtime.name.contains(requested))
        XCTAssertTrue(runtime.version.lowercased().contains("wine"))
        XCTAssertNotNil(runtime.dxvkPackage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.managedRoot!.appendingPathComponent("download-receipt.json").path))
    }

    func testMediaPluginPathsAndLaunchArguments() async throws {
        let root = try fixture()
        var engine = runtime(URL(fileURLWithPath: "/usr/bin/printf")); engine.useRosetta = true; engine.managedRoot = root
        let framework = root.appendingPathComponent("media/GStreamer.framework")
        let lib = framework.appendingPathComponent("Versions/1.0/lib")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data().write(to: lib.appendingPathComponent("libgstreamer-1.0.0.dylib"))
        let entry = try ShotglassFiles.create(Shotglass(name: "Video", runtime: engine, graphics: .wine), parent: root)
        let env = Wine.environment(for: entry)
        XCTAssertEqual(env["GST_PLUGIN_SYSTEM_PATH_1_0"], lib.appendingPathComponent("gstreamer-1.0").path)
        XCTAssertEqual(env["GST_PLUGIN_PATH_1_0"], "")
        XCTAssertEqual(env["GST_PLUGIN_SCANNER_1_0"], framework.appendingPathComponent("Versions/1.0/libexec/gstreamer-1.0/gst-plugin-scanner").path)
        XCTAssertEqual(env["GST_REGISTRY_1_0"], entry.folder.appendingPathComponent("gstreamer-registry-x86_64-v1.bin").path)
        let (binary, args) = Wine.command(runtime: engine, arguments: ["%s", "a name; literal $value"])
        let output = try await ProcessRunner.capture(binary, args)
        XCTAssertEqual(output, "a name; literal $value")
    }

    func testOptionalH264DecodeAndWineStaging() async throws {
        let settings = ProcessInfo.processInfo.environment
        guard let wine = settings["SPICED_RUM_TEST_WINE"],
              settings["SPICED_RUM_TEST_GSTREAMER_PACKAGE"] != nil || settings["SPICED_RUM_TEST_GSTREAMER_FRAMEWORK"] != nil else {
            throw XCTSkip("Set SPICED_RUM_TEST_WINE and either SPICED_RUM_TEST_GSTREAMER_PACKAGE or SPICED_RUM_TEST_GSTREAMER_FRAMEWORK to verify native decoding and Windows H.264 decoder creation.")
        }
        let root = try fixture()
        let media = root.appendingPathComponent("media")
        let framework = media.appendingPathComponent("GStreamer.framework")
        if let package = settings["SPICED_RUM_TEST_GSTREAMER_PACKAGE"] {
            let archive = URL(fileURLWithPath: package)
            try EngineInstaller.verify(archive, digest: MediaSupport.digest)
            let expanded = root.appendingPathComponent("expanded")
            _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/sbin/pkgutil"), ["--expand-full", archive.path, expanded.path])
            try await MediaSupport.assemble(from: expanded, framework: framework)
        } else {
            _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [settings["SPICED_RUM_TEST_GSTREAMER_FRAMEWORK"]!, framework.path])
        }
        try await MediaSupport.validateH264(framework: framework, log: media.appendingPathComponent("h264.log"))
        var engine = Runtime(name: "Wine Staging media test", executable: URL(fileURLWithPath: wine), useRosetta: true, d3dMetal: false, version: "")
        engine.managedRoot = root
        let entry = try ShotglassFiles.create(Shotglass(name: "Media test", runtime: engine, graphics: .wine), parent: root)
        do {
            let ready = try await Wine.initialize(entry, dxvk: nil)
            try await Wine.execute(runtime: engine, arguments: ["cmd", "/c", "echo", "SPICED_RUM_MEDIA_OK"], environment: Wine.environment(for: ready), directory: ready.folder, log: ready.log)
            XCTAssertTrue(try String(contentsOf: ready.log).contains("SPICED_RUM_MEDIA_OK"))
            let mono = URL(fileURLWithPath: wine).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/wine/mono")
            let compiler = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: mono, includingPropertiesForKeys: nil)
                .map { $0.appendingPathComponent("lib/mono/4.5/csc.exe") }.first { FileManager.default.fileExists(atPath: $0.path) })
            let source = root.appendingPathComponent("DecoderProbe.cs")
            try """
            using System;
            using System.Runtime.InteropServices;
            class DecoderProbe {
                [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p, uint flags);
                [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr result);
                static int Main() {
                    CoInitializeEx(IntPtr.Zero, 0);
                    Guid clsid = new Guid("62ce7e72-4c71-4d20-b15d-452831a87d9d");
                    Guid iid = new Guid("00000000-0000-0000-C000-000000000046");
                    IntPtr decoder;
                    int status = CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iid, out decoder);
                    if (status < 0) { Console.WriteLine("H264_HRESULT=0x{0:X8}", status); return 1; }
                    Marshal.Release(decoder);
                    Console.WriteLine("SPICED_RUM_H264_DECODER_OK={0}", IntPtr.Size * 8);
                    return 0;
                }
            }
            """.write(to: source, atomically: true, encoding: .utf8)
            func windows(_ file: URL) -> String { "Z:" + file.path.replacingOccurrences(of: "/", with: "\\") }
            let output = root.appendingPathComponent("DecoderProbe-x64.exe")
            try await Wine.execute(runtime: engine, arguments: [compiler.path, "/nologo", "/platform:x64", "/out:" + windows(output), windows(source)], environment: Wine.environment(for: ready), directory: root, log: ready.log, timeout: 120)
            try await Wine.execute(runtime: engine, arguments: [output.path], environment: Wine.environment(for: ready), directory: root, log: ready.log, timeout: 240)
            let lines = try String(contentsOf: ready.log).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            XCTAssertTrue(lines.contains("SPICED_RUM_H264_DECODER_OK=64"))
            try await Wine.stopServer(ready)
        } catch { try? await Wine.stopServer(entry); throw error }
    }
}
