import Foundation

public struct EngineBackup: Identifiable {
    public let folder: URL
    public let shotglass: Shotglass
    public let created: Date
    public var id: String { folder.lastPathComponent }
}

public enum ShotglassEngines {
    private struct PendingChange: Codable { let backupID: String; let runtime: Runtime }
    // App/game folders, ProgramData and user profiles deliberately stay outside the snapshot.
    static let environmentPaths = ["drive_c/windows", "system.reg", "user.reg", "userdef.reg", "dosdevices", ".update-timestamp", "winetricks.log"]
    private struct Manifest: Codable { let version: Int; let paths: [String] }

    private static func validate(_ backup: EngineBackup, for entry: ShotglassEntry) throws {
        let root = entry.folder.appendingPathComponent("engine-backups").resolvingSymlinksInPath().path + "/"
        guard backup.shotglass.id == entry.id, UUID(uuidString: backup.id) != nil,
              backup.folder.resolvingSymlinksInPath().path == root + backup.id else { throw RumError.message("Choose an engine backup belonging to this shotglass.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: backup.folder.appendingPathComponent("environment.json")))
        guard manifest.version == 1, manifest.paths == environmentPaths else { throw RumError.message("This backup uses an unsupported environment format.") }
    }

    public static func backups(for entry: ShotglassEntry) throws -> [EngineBackup] {
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]).compactMap { folder in
            guard UUID(uuidString: folder.lastPathComponent) != nil, let shotglass = try? Shotglass.load(from: folder), shotglass.id == entry.id,
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent("environment.json").path) else { return nil }
            return EngineBackup(folder: folder, shotglass: shotglass, created: (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }.sorted { $0.created > $1.created }
    }

    public static func backupReferences(runtimeID: UUID, for entry: ShotglassEntry) throws -> Bool {
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("environment.json").path) {
            let saved: Shotglass
            do { saved = try Shotglass.load(from: folder) }
            catch { throw RumError.message("Cannot verify engine backups for \(entry.shotglass.name). Resolve or remove the unreadable backup at \(folder.path) before removing an engine.") }
            guard saved.id == entry.id else {
                throw RumError.message("An engine backup in \(entry.shotglass.name) has mismatched shotglass metadata. Inspect \(folder.path) before removing an engine.")
            }
            if saved.runtime.id == runtimeID { return true }
        }
        return false
    }

    public static func backupReferences(dxvkPackage packageURL: URL, for entry: ShotglassEntry) throws -> Bool {
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("environment.json").path) {
            let saved: Shotglass
            do { saved = try Shotglass.load(from: folder) }
            catch { throw RumError.message("Cannot verify engine backups for \(entry.shotglass.name). Resolve or remove the unreadable backup at \(folder.path) before removing a DXVK version.") }
            guard saved.id == entry.id else {
                throw RumError.message("An engine backup in \(entry.shotglass.name) has mismatched shotglass metadata. Inspect \(folder.path) before removing a DXVK version.")
            }
            let savedPackage = saved.dxvkPackage ?? saved.runtime.dxvkPackage
            if savedPackage?.standardizedFileURL == packageURL.standardizedFileURL { return true }
        }
        return false
    }

    public static func backupReferences(graphicsPackage packageURL: URL,
                                        source: GraphicsRuntimeSource,
                                        for entry: ShotglassEntry) throws -> Bool {
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("environment.json").path) {
            let saved: Shotglass
            do { saved = try Shotglass.load(from: folder) }
            catch { throw RumError.message("Cannot verify engine backups for \(entry.shotglass.name). Resolve or remove the unreadable backup at \(folder.path) before removing graphics versions.") }
            guard saved.id == entry.id else {
                throw RumError.message("An engine backup in \(entry.shotglass.name) has mismatched shotglass metadata. Inspect \(folder.path) before removing graphics versions.")
            }
            let savedPackage: URL?
            switch source {
            case .mtld3d: savedPackage = saved.mtld3dPackage
            case .vkd3dProton: savedPackage = saved.vkd3dProtonPackage
            case .dxgi: savedPackage = saved.dxgiPackage
            case .zink: savedPackage = saved.zinkPackage
            }
            if savedPackage?.standardizedFileURL == packageURL.standardizedFileURL { return true }
        }
        return false
    }

    public static func backupReferences(dxmtPackage packageURL: URL, for entry: ShotglassEntry) throws -> Bool {
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("environment.json").path) {
            let saved: Shotglass
            do { saved = try Shotglass.load(from: folder) }
            catch { throw RumError.message("Cannot verify engine backups for \(entry.shotglass.name). Resolve or remove the unreadable backup at \(folder.path) before removing DXMT versions.") }
            guard saved.id == entry.id else {
                throw RumError.message("An engine backup in \(entry.shotglass.name) has mismatched shotglass metadata. Inspect \(folder.path) before removing DXMT versions.")
            }
            if saved.runtime.dxmtPackage?.standardizedFileURL == packageURL.standardizedFileURL { return true }
        }
        return false
    }

    static func snapshot(_ entry: ShotglassEntry) throws -> EngineBackup {
        let fm = FileManager.default
        let values = try entry.prefix.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw RumError.message("The shotglass must have its own Windows prefix folder before its engine can be changed.") }
        let root = entry.folder.appendingPathComponent("engine-backups", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staging = root.appendingPathComponent(".incomplete-" + id, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging.appendingPathComponent("prefix", isDirectory: true), withIntermediateDirectories: false)
        for path in environmentPaths {
            let source = entry.prefix.appendingPathComponent(path)
            guard (try? fm.attributesOfItem(atPath: source.path)) != nil else { continue }
            let destination = staging.appendingPathComponent("prefix/" + path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
        }
        try JSONEncoder().encode(Manifest(version: 1, paths: environmentPaths)).write(to: staging.appendingPathComponent("environment.json"), options: .atomic)
        try entry.shotglass.save(in: staging)
        let destination = root.appendingPathComponent(id, isDirectory: true)
        try fm.moveItem(at: staging, to: destination)
        return EngineBackup(folder: destination, shotglass: entry.shotglass, created: Date())
    }

    private static func restoreFiles(_ backup: EngineBackup, to entry: ShotglassEntry) throws -> ShotglassEntry {
        let fm = FileManager.default
        try validate(backup, for: entry)
        let staging = entry.folder.appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        let displaced = entry.folder.appendingPathComponent(".replaced-environment-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: backup.folder.appendingPathComponent("prefix", isDirectory: true), to: staging)
        var replaced: [String] = []
        var installed: [String] = []
        var restored = entry
        restored.shotglass.runtime = backup.shotglass.runtime; restored.shotglass.graphics = backup.shotglass.graphics
        restored.shotglass.dxvkPackage = backup.shotglass.dxvkPackage
        restored.shotglass.direct3D9 = backup.shotglass.direct3D9
        restored.shotglass.direct3D12 = backup.shotglass.direct3D12
        restored.shotglass.vulkan = backup.shotglass.vulkan
        restored.shotglass.openGL = backup.shotglass.openGL
        restored.shotglass.mtld3dPackage = backup.shotglass.mtld3dPackage
        restored.shotglass.vkd3dProtonPackage = backup.shotglass.vkd3dProtonPackage
        restored.shotglass.dxgiPackage = backup.shotglass.dxgiPackage
        restored.shotglass.zinkPackage = backup.shotglass.zinkPackage
        restored.shotglass.initialized = backup.shotglass.initialized
        do {
            for path in environmentPaths {
                let current = entry.prefix.appendingPathComponent(path)
                let previous = displaced.appendingPathComponent(path)
                if (try? fm.attributesOfItem(atPath: current.path)) != nil {
                    try fm.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: current, to: previous); replaced.append(path)
                }
                let saved = staging.appendingPathComponent(path)
                if (try? fm.attributesOfItem(atPath: saved.path)) != nil {
                    try fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: saved, to: current); installed.append(path)
                }
            }
            try restored.shotglass.save(in: entry.folder)
        } catch {
            // Preserve displaced files if rollback itself fails; the snapshot also remains intact.
            do {
                for path in installed.reversed() { try fm.removeItem(at: entry.prefix.appendingPathComponent(path)) }
                for path in replaced.reversed() { try fm.moveItem(at: displaced.appendingPathComponent(path), to: entry.prefix.appendingPathComponent(path)) }
                try? fm.removeItem(at: displaced)
            } catch { throw RumError.message("Environment recovery needs attention. Saved files remain at \(displaced.path).\n\(error.localizedDescription)") }
            throw error
        }
        try? fm.removeItem(at: displaced)
        return restored
    }

    public static func change(_ entry: ShotglassEntry, to runtime: Runtime, status: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ShotglassEntry {
        guard !entry.engineChangePending else { throw RumError.message("Restore the interrupted engine change before switching again.") }
        guard runtime.id != entry.shotglass.runtime.id else { return entry }
        status("Checking the selected engine…")
        _ = try await Wine.probe(runtime)
        if runtime.defaultGraphics == .dxvk { try Wine.validateDXVK(runtime.dxvkPackage) }
        var changed = entry
        changed.shotglass.runtime = runtime; changed.shotglass.graphics = runtime.defaultGraphics
        changed.shotglass.dxvkPackage = nil
        changed.shotglass.direct3D9 = .wine; changed.shotglass.mtld3dPackage = nil
        changed.shotglass.direct3D12 = .wine; changed.shotglass.vkd3dProtonPackage = nil
        changed.shotglass.dxgiPackage = nil
        changed.shotglass.vulkan = .runtimeDefault
        changed.shotglass.openGL = .wine; changed.shotglass.zinkPackage = nil
        if !entry.shotglass.initialized && !FileManager.default.fileExists(atPath: entry.prefix.path) {
            // No Windows environment exists to migrate or back up yet.
            try changed.shotglass.save(in: changed.folder)
            return changed
        }
        status("Stopping this shotglass's Windows processes…")
        try await Wine.stopServer(entry)
        status("Backing up the Windows environment…")
        let backup = try snapshot(entry)
        let marker = entry.folder.appendingPathComponent("engine-change.json")
        try JSONEncoder().encode(PendingChange(backupID: backup.id, runtime: runtime)).write(to: marker, options: .atomic)
        do {
            if entry.shotglass.graphics == .dxvk { try Wine.removeDXVK(from: entry.prefix) }
            if entry.shotglass.direct3D9 == .mtld3d { try Wine.removeMTLD3D(from: entry.prefix) }
            if entry.shotglass.direct3D12 == .vkd3dProton { try Wine.removeVKD3DProton(from: entry.prefix) }
            if entry.shotglass.openGL == .zink { try Wine.removeZink(from: entry.prefix) }
            status("Updating the Windows environment and graphics…")
            let ready = try await Wine.initialize(changed, dxvk: runtime.dxvkPackage, updating: entry.shotglass.initialized)
            try FileManager.default.removeItem(at: marker)
            return ready
        } catch {
            let failure = error
            do {
                try await Wine.stopServer(changed)
                _ = try restoreFiles(backup, to: entry)
                try FileManager.default.removeItem(at: marker)
            } catch {
                throw RumError.message("The engine change could not finish and automatic recovery failed. Open Change engine and restore the backup. It is preserved at \(backup.folder.path).\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw RumError.message("The engine change failed. The previous engine and Windows environment have been restored.\n\(failure.localizedDescription)")
        }
    }

    public static func restore(_ backup: EngineBackup, to entry: ShotglassEntry) async throws -> ShotglassEntry {
        try validate(backup, for: entry)
        let marker = entry.folder.appendingPathComponent("engine-change.json")
        if entry.engineChangePending {
            let pending = try JSONDecoder().decode(PendingChange.self, from: Data(contentsOf: marker))
            var active = entry; active.shotglass.runtime = pending.runtime
            try await Wine.stopServer(active)
        } else {
            try await Wine.stopServer(entry)
            // Manual restores get an undo snapshot of the current state too.
            _ = try snapshot(entry)
            try JSONEncoder().encode(PendingChange(backupID: backup.id, runtime: entry.shotglass.runtime)).write(to: marker, options: .atomic)
        }
        let restored = try restoreFiles(backup, to: entry)
        try FileManager.default.removeItem(at: marker)
        return restored
    }

    public static func delete(_ backup: EngineBackup, from entry: ShotglassEntry) throws {
        try validate(backup, for: entry)
        if entry.engineChangePending {
            let pending = try JSONDecoder().decode(PendingChange.self, from: Data(contentsOf: entry.folder.appendingPathComponent("engine-change.json")))
            guard pending.backupID != backup.id else { throw RumError.message("This backup is needed to recover an interrupted engine change. Restore it before deleting it.") }
        }
        try FileManager.default.removeItem(at: backup.folder)
    }
}
