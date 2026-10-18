import XCTest
@testable import SpicedRumCore

final class HeroicInstallerTests: XCTestCase {
    func testRecognizesHeroicSetupButNotPortableOrInstalledExecutables() {
        XCTAssertTrue(HeroicInstaller.isSetup(URL(fileURLWithPath: "/tmp/Heroic-2.22.4-Setup-x64.exe")))
        XCTAssertTrue(HeroicInstaller.isSetup(URL(fileURLWithPath: "/tmp/heroic-setup.exe")))
        XCTAssertFalse(HeroicInstaller.isSetup(URL(fileURLWithPath: "/tmp/Heroic-2.22.4-Portable-x64.exe")))
        XCTAssertFalse(HeroicInstaller.isSetup(URL(fileURLWithPath: "/tmp/Heroic.exe")))
        XCTAssertFalse(HeroicInstaller.isSetup(URL(fileURLWithPath: "/tmp/Some-Setup.exe")))
    }

    func testOptionalRealHeroicSetupExtraction() async throws {
        guard let setupPath = ProcessInfo.processInfo.environment["SPICED_RUM_TEST_HEROIC_SETUP"] else {
            throw XCTSkip("Set SPICED_RUM_TEST_HEROIC_SETUP to validate extraction from a real Heroic setup executable.")
        }
        guard let sevenZip = Dependencies.sevenZip else { throw XCTSkip("Install 7-Zip (7zz) to validate real Heroic setup extraction.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HeroicExtractTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = ShotglassEntry(shotglass: Shotglass(name: "Heroic extraction test", runtime: Runtime(name: "Test", executable: URL(fileURLWithPath: "/usr/bin/true"), useRosetta: false, d3dMetal: false, version: "test"), graphics: .wine), folder: root)

        let executable = try await HeroicInstaller.extract(URL(fileURLWithPath: setupPath), into: entry, using: sevenZip)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: executable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: executable.deletingLastPathComponent().appendingPathComponent("resources/app.asar").path))
    }
}
