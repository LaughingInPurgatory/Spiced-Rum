import Foundation

public enum ShotglassGraphics {
    public static func choices(for runtime: Runtime) -> [Graphics] {
        var choices: [Graphics] = [.wine]
        if runtime.dxvkPackage != nil, (try? Wine.validateDXVK(runtime.dxvkPackage)) != nil { choices.append(.dxvk) }
        if runtime.d3dMetal { choices.append(.metal) }
        if runtime.dxmt {
            if let package = runtime.dxmtPackage {
                if (try? Wine.validateDXMT(package)) != nil { choices.append(.dxmt) }
            } else {
                choices.append(.dxmt)
            }
        }
        return choices
    }

    public static func choices(for entry: ShotglassEntry) -> [Graphics] {
        var choices = choices(for: entry.shotglass.runtime)
        let hasSelectedPackage = (try? Wine.validateDXVK(entry.dxvkPackage)) != nil
        if !choices.contains(.dxvk), (hasSelectedPackage || EngineInstaller.supportsMacOSDXVK(entry.shotglass.runtime)) {
            choices.append(.dxvk)
        }
        return choices
    }

    public static func change(_ entry: ShotglassEntry, to graphics: Graphics) async throws -> ShotglassEntry {
        guard !entry.engineChangePending else {
            throw RumError.message("Restore the pending engine backup before changing graphics for this shotglass.")
        }
        guard choices(for: entry).contains(graphics) else {
            throw RumError.message("This engine does not provide the selected graphics component. Choose an option listed for its runtime.")
        }
        guard graphics != .dxvk || (try? Wine.validateDXVK(entry.dxvkPackage)) != nil else {
            throw RumError.message("This shotglass does not have a DXVK version selected. Choose one with DXVK version… first.")
        }
        if graphics == .dxmt, let package = entry.shotglass.runtime.dxmtPackage { try Wine.validateDXMT(package) }
        guard entry.shotglass.graphics != graphics else { return entry }

        if !entry.shotglass.initialized {
            var changed = entry
            changed.shotglass.graphics = graphics
            try changed.shotglass.save(in: changed.folder)
            return changed
        }

        let previous = entry.shotglass.graphics
        let oldDXVK = entry.dxvkPackage
        let oldDXMT = entry.shotglass.runtime.dxmtPackage
        if previous == .dxvk { try Wine.validateDXVK(oldDXVK) }
        if previous == .dxmt, let oldDXMT { try Wine.validateDXMT(oldDXMT) }
        try await Wine.stopServer(entry)

        var changed = entry
        changed.shotglass.graphics = graphics
        do {
            if previous == .dxvk { try Wine.removeDXVK(from: entry.prefix) }
            if previous == .dxmt, oldDXMT != nil { try Wine.removeDXMT(from: entry.prefix) }
            if graphics == .dxvk, let package = entry.dxvkPackage {
                try Wine.installDXVK(from: package, into: entry.prefix)
            }
            if graphics == .dxmt, let package = entry.shotglass.runtime.dxmtPackage {
                try Wine.installDXMT(from: package, into: entry.prefix)
            }
            try changed.shotglass.save(in: changed.folder)
            return changed
        } catch {
            let failure = error
            do {
                if previous == .dxvk, let oldDXVK {
                    // installDXVK preserves the Wine DLLs restored by removeDXVK and
                    // replaces any partially copied new DLLs with the old version.
                    try Wine.installDXVK(from: oldDXVK, into: entry.prefix)
                } else if graphics == .dxvk {
                    try Wine.removeDXVK(from: entry.prefix)
                }
                if previous == .dxmt, let oldDXMT {
                    try Wine.installDXMT(from: oldDXMT, into: entry.prefix)
                } else if graphics == .dxmt, oldDXMT != nil {
                    try Wine.removeDXMT(from: entry.prefix)
                }
                try entry.shotglass.save(in: entry.folder)
            } catch {
                throw RumError.message("The graphics change failed and the previous setup could not be restored. The shotglass files were left in place.\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw RumError.message("The graphics change failed. The previous renderer has been restored.\n\(failure.localizedDescription)")
        }
    }

    public static func selectDXVK(_ entry: ShotglassEntry, package: URL) async throws -> ShotglassEntry {
        guard !entry.engineChangePending else {
            throw RumError.message("Restore the pending engine backup before changing DXVK for this shotglass.")
        }
        guard EngineInstaller.supportsMacOSDXVK(entry.shotglass.runtime) || entry.dxvkPackage != nil else {
            throw RumError.message("This shotglass's engine does not provide the macOS MoltenVK support required by DXVK.")
        }
        try Wine.validateDXVK(package)
        if entry.shotglass.graphics == .dxvk,
           entry.dxvkPackage?.standardizedFileURL == package.standardizedFileURL { return entry }

        var changed = entry
        changed.shotglass.dxvkPackage = package
        changed.shotglass.graphics = .dxvk
        guard entry.shotglass.initialized else {
            try changed.shotglass.save(in: changed.folder)
            return changed
        }

        let previousGraphics = entry.shotglass.graphics
        let previousPackage = entry.dxvkPackage
        if previousGraphics == .dxvk { try Wine.validateDXVK(previousPackage) }
        let previousDXMT = entry.shotglass.runtime.dxmtPackage
        if previousGraphics == .dxmt, let previousDXMT { try Wine.validateDXMT(previousDXMT) }
        try await Wine.stopServer(entry)
        do {
            if previousGraphics == .dxvk { try Wine.removeDXVK(from: entry.prefix) }
            if previousGraphics == .dxmt, previousDXMT != nil { try Wine.removeDXMT(from: entry.prefix) }
            try Wine.installDXVK(from: package, into: entry.prefix)
            try changed.shotglass.save(in: changed.folder)
            return changed
        } catch {
            let failure = error
            do {
                if previousGraphics == .dxvk, let previousPackage {
                    try Wine.removeDXVK(from: entry.prefix)
                    try Wine.installDXVK(from: previousPackage, into: entry.prefix)
                } else {
                    try Wine.removeDXVK(from: entry.prefix)
                }
                if previousGraphics == .dxmt, let previousDXMT {
                    try Wine.installDXMT(from: previousDXMT, into: entry.prefix)
                }
                try entry.shotglass.save(in: entry.folder)
            } catch {
                throw RumError.message("DXVK could not be changed for this shotglass and its previous graphics files could not be restored. The installed packages were preserved.\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw RumError.message("DXVK could not be changed for this shotglass. Its previous graphics files were restored.\n\(failure.localizedDescription)")
        }
    }
}
