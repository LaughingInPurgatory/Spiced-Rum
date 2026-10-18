import XCTest
@testable import SpicedRumCore

final class RuntimeDiscoveryTests: XCTestCase {
    func testParsesAppleGPTKEvaluationImageVersion() {
        XCTAssertEqual(GPTKInstaller.versionFromImageName("Game_Porting_Toolkit_4.0_beta_3"), "4.0 beta 3")
        XCTAssertEqual(GPTKInstaller.versionFromImageName("Evaluation environment for Windows games 4.0 beta 3"), "4.0 beta 3")
        XCTAssertNil(GPTKInstaller.versionFromImageName("unrelated image"))
    }

    func testChoosesNewestEvaluationImageIncludingBetaNumberAndFinalRelease() {
        XCTAssertEqual(GPTKInstaller.newestVersion(in: ["4.0 beta 3", "4.0 beta 10", "3.9"]), "4.0 beta 10")
        XCTAssertEqual(GPTKInstaller.newestVersion(in: ["4.0 beta 10", "4.0", "3.9"]), "4.0")
        XCTAssertEqual(GPTKInstaller.newestVersion(in: ["4.0 beta 3", "4.1 alpha 1"]), "4.1 alpha 1")
    }

    func testPrefersNewestInstalledAppleGPTKBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumGPTKVersions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, version) in [("Game Porting Toolkit beta 3.app", "4.0 beta 3"), ("Game Porting Toolkit beta 10.app", "4.0 beta 10")] {
            let app = root.appendingPathComponent(name)
            let info = app.appendingPathComponent("Contents/Info.plist")
            let wineRoot = app.appendingPathComponent("Contents/Resources/wine")
            let bin = wineRoot.appendingPathComponent("bin")
            let metal = wineRoot.appendingPathComponent("lib/external/D3DMetal.framework/Versions/Current/D3DMetal")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: metal.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
            try plist.write(to: info)
            for file in [bin.appendingPathComponent("wine64"), bin.appendingPathComponent("wineserver")] {
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            try Data().write(to: metal)
        }

        let runtime = try XCTUnwrap(RuntimeDiscovery.appleGamePortingToolkit(in: [root]))
        XCTAssertTrue(runtime.executable.path.contains("beta 10.app"))
        XCTAssertEqual(runtime.version, "4.0 beta 10")
    }

    func testFindsInstalledAppleGPTKBundleAndItsBundledMediaRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumGPTK-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wineRoot = root.appendingPathComponent("Game Porting Toolkit.app/Contents/Resources/wine")
        let bin = wineRoot.appendingPathComponent("bin")
        let metalBinary = wineRoot.appendingPathComponent("lib/external/D3DMetal.framework/Versions/Current/D3DMetal")
        let gstreamer = wineRoot.appendingPathComponent("lib/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metalBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gstreamer.deletingLastPathComponent(), withIntermediateDirectories: true)
        for file in [bin.appendingPathComponent("wine64"), bin.appendingPathComponent("wineserver")] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try Data().write(to: metalBinary)
        try Data().write(to: gstreamer)

        let runtime = try XCTUnwrap(RuntimeDiscovery.appleGamePortingToolkit(in: [root]))
        XCTAssertEqual(runtime.executable.standardizedFileURL, bin.appendingPathComponent("wine64").standardizedFileURL)
        XCTAssertTrue(runtime.useRosetta)
        XCTAssertTrue(runtime.d3dMetal)
        XCTAssertEqual(MediaSupport.framework(for: runtime)?.standardizedFileURL, wineRoot.appendingPathComponent("lib/GStreamer.framework").standardizedFileURL)
    }

    func testDoesNotTreatWineWithoutD3DMetalAsGPTK() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumOtherWine-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wineRoot = root.appendingPathComponent("Game Porting Toolkit.app/Contents/Resources/wine")
        let bin = wineRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine64", "wineserver"] {
            let file = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        XCTAssertNil(RuntimeDiscovery.appleGamePortingToolkit(in: [root]))
    }

    func testGPTKBetaIsCopiedIntoPrivateOverlayWithoutChangingInstalledApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumGPTKInstall-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceWine = root.appendingPathComponent("Game Porting Toolkit.app/Contents/Resources/wine")
        let baseBin = sourceWine.appendingPathComponent("bin")
        let oldWineLib = sourceWine.appendingPathComponent("lib/wine")
        let oldExternal = sourceWine.appendingPathComponent("lib/external")
        let gstreamer = sourceWine.appendingPathComponent("lib/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib")
        let share = sourceWine.appendingPathComponent("share/wine")
        for directory in [baseBin, oldWineLib, oldExternal, gstreamer.deletingLastPathComponent(), share] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for name in ["wine64", "wineserver"] {
            let executable = baseBin.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        try Data("old Wine graphics".utf8).write(to: oldWineLib.appendingPathComponent("old.dll"))
        try Data("old D3DMetal".utf8).write(to: oldExternal.appendingPathComponent("old-framework"))
        try Data().write(to: gstreamer)

        let volume = root.appendingPathComponent("Evaluation environment for Windows games 4.0 beta 3")
        let libraries = volume.appendingPathComponent("redist/lib")
        let newDLL = libraries.appendingPathComponent("wine/x86_64-windows/d3d11.dll")
        let newSO = libraries.appendingPathComponent("wine/x86_64-unix/d3d11.so")
        let newD3DMetal = libraries.appendingPathComponent("external/D3DMetal.framework/Versions/A/D3DMetal")
        for file in [newDLL, libraries.appendingPathComponent("external/libd3dshared.dylib"), newD3DMetal] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("beta component".utf8).write(to: file)
        }
        try FileManager.default.createDirectory(at: newSO.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: newSO.path, withDestinationPath: "../../external/libd3dshared.dylib")
        for notice in ["License.rtf", "Acknowledgements.rtf", "Read Me.rtf"] {
            try Data(notice.utf8).write(to: volume.appendingPathComponent(notice))
        }
        let base = Runtime(name: "Apple Game Porting Toolkit", executable: baseBin.appendingPathComponent("wine64"), useRosetta: true, d3dMetal: true, version: "wine-test")
        let evaluation = GPTKEvaluationEnvironment(libraries: libraries, volume: volume, version: "4.0 beta 3", mountedBySpicedRum: false, volumesMountedBySpicedRum: [])

        let runtime = try await GPTKInstaller.install(evaluation, using: base, into: root.appendingPathComponent("Engines"))
        let managed = try XCTUnwrap(runtime.managedRoot)
        XCTAssertTrue(runtime.d3dMetal)
        XCTAssertEqual(runtime.gptkVersion, "4.0 beta 3")
        XCTAssertEqual(try String(contentsOf: managed.appendingPathComponent("wine/lib/wine/x86_64-windows/d3d11.dll")), "beta component")
        XCTAssertEqual(try String(contentsOf: managed.appendingPathComponent("wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal")), "beta component")
        XCTAssertTrue(try managed.appendingPathComponent("wine/lib/wine/x86_64-unix/d3d11.so").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(try String(contentsOf: managed.appendingPathComponent("wine/lib/wine/old.dll")), "old Wine graphics")
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.appendingPathComponent("GPTK Payload/License.rtf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.appendingPathComponent("GPTK Payload/spiced-rum-gptk-payload.json").path))
        XCTAssertEqual(try String(contentsOf: oldWineLib.appendingPathComponent("old.dll")), "old Wine graphics")
        XCTAssertEqual(try String(contentsOf: oldExternal.appendingPathComponent("old-framework")), "old D3DMetal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.appendingPathComponent("wine/lib/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib").path))
        let reusable = try XCTUnwrap(GPTKInstaller.installedEvaluationPayload(in: managed.deletingLastPathComponent()))
        XCTAssertEqual(reusable.version, "4.0 beta 3")
        XCTAssertTrue(reusable.libraries.path.hasSuffix("wine/lib"))
    }

    func testGPTKPayloadAttachesToCommunityWineWithoutReplacingItsWineCore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumGPTKAttach-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("install/content", isDirectory: true)
        let engine = content.appendingPathComponent("Libraries/Whisky runtime", isDirectory: true)
        let wine = engine.appendingPathComponent("Wine", isDirectory: true)
        let bin = wine.appendingPathComponent("bin", isDirectory: true)
        let wineLibraries = wine.appendingPathComponent("lib/wine", isDirectory: true)
        let external = wine.appendingPathComponent("lib/external", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wineLibraries.appendingPathComponent("x86_64-windows"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wineLibraries.appendingPathComponent("x86_64-unix"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let unixWine = wineLibraries.appendingPathComponent("x86_64-unix/wine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: unixWine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unixWine.path)
        let wine64 = bin.appendingPathComponent("wine64")
        try FileManager.default.createSymbolicLink(atPath: wine64.path, withDestinationPath: "../lib/wine/x86_64-unix/wine")
        try Data("community Wine core".utf8).write(to: wineLibraries.appendingPathComponent("ntdll.so"))
        try Data("community DXVK component".utf8).write(to: external.appendingPathComponent("dxvk.dylib"))

        let volume = root.appendingPathComponent("Evaluation environment for Windows games 4.0 beta 10")
        let libraries = volume.appendingPathComponent("redist/lib", isDirectory: true)
        let payloadDLL = libraries.appendingPathComponent("wine/x86_64-windows/d3d11.dll")
        let payloadSO = libraries.appendingPathComponent("wine/x86_64-unix/d3d11.so")
        let payloadShared = libraries.appendingPathComponent("external/libd3dshared.dylib")
        let payloadMetal = libraries.appendingPathComponent("external/D3DMetal.framework/Versions/A/D3DMetal")
        for file in [payloadDLL, payloadShared, payloadMetal] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("Apple GPTK payload".utf8).write(to: file)
        }
        try FileManager.default.createDirectory(at: payloadSO.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: payloadSO.path, withDestinationPath: "../../external/libd3dshared.dylib")
        try Data("Apple license".utf8).write(to: volume.appendingPathComponent("License.rtf"))

        let relative = try EngineInstaller.relativeExecutablePath(in: content, executable: wine64)
        let managedEngine = root.appendingPathComponent("installed-Whisky", isDirectory: true)
        try FileManager.default.moveItem(at: content, to: managedEngine)
        let relocatedWineRoot = managedEngine.appendingPathComponent("Libraries/Whisky runtime/Wine", isDirectory: true)
        let relocatedWineLibraries = relocatedWineRoot.appendingPathComponent("lib/wine", isDirectory: true)
        let relocatedExternal = relocatedWineRoot.appendingPathComponent("lib/external", isDirectory: true)
        var base = Runtime(name: "Whisky community runtime", executable: managedEngine.appendingPathComponent(relative), useRosetta: false, d3dMetal: false, version: "wine-11.16")
        base.managedRoot = managedEngine
        let evaluation = GPTKEvaluationEnvironment(libraries: libraries, volume: volume, version: "4.0 beta 10", mountedBySpicedRum: false, volumesMountedBySpicedRum: [])
        let runtime = try await GPTKInstaller.attachPayload(evaluation, to: base)

        XCTAssertTrue(runtime.d3dMetal)
        XCTAssertEqual(runtime.gptkVersion, "4.0 beta 10")
        XCTAssertEqual(runtime.version, "wine-11.16")
        XCTAssertEqual(try String(contentsOf: relocatedWineLibraries.appendingPathComponent("ntdll.so")), "community Wine core")
        XCTAssertEqual(try String(contentsOf: relocatedExternal.appendingPathComponent("dxvk.dylib")), "community DXVK component")
        XCTAssertEqual(try String(contentsOf: relocatedWineLibraries.appendingPathComponent("x86_64-windows/d3d11.dll")), "Apple GPTK payload")
        XCTAssertEqual(try String(contentsOf: relocatedExternal.appendingPathComponent("D3DMetal.framework/Versions/A/D3DMetal")), "Apple GPTK payload")
        XCTAssertTrue(try relocatedWineLibraries.appendingPathComponent("x86_64-unix/d3d11.so").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedEngine.appendingPathComponent("GPTK Payload/License.rtf").path))
        XCTAssertEqual(runtime.executable.standardizedFileURL, managedEngine.appendingPathComponent(relative).standardizedFileURL)
    }

    func testOptionalInstalledGPTKBetaWindowsX64Smoke() async throws {
        guard ProcessInfo.processInfo.environment["SPICED_RUM_TEST_GPTK_BETA"] == "1" else {
            throw XCTSkip("Set SPICED_RUM_TEST_GPTK_BETA=1 to validate an installed Apple GPTK beta runtime.")
        }
        let base = try XCTUnwrap(RuntimeDiscovery.appleGamePortingToolkit())
        let foundEvaluation = try await GPTKInstaller.findOrMountEvaluationEnvironment()
        let evaluation = try XCTUnwrap(foundEvaluation)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpicedRumRealGPTK-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var runtime = try await GPTKInstaller.install(evaluation, using: base, into: root.appendingPathComponent("Engines"))
        runtime.version = try await Wine.probe(runtime)
        try await EngineInstaller.checkX64(runtime, in: root.appendingPathComponent("Validation"))
        XCTAssertTrue(runtime.version.lowercased().contains("wine"))
    }
}
