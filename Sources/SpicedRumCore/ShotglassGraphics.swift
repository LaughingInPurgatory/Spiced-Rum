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

    public static func change(_ entry: ShotglassEntry, to graphics: Graphics) async throws -> ShotglassEntry {
        guard !entry.engineChangePending else {
            throw RumError.message("Restore the pending engine backup before changing graphics for this shotglass.")
        }
        guard choices(for: entry.shotglass.runtime).contains(graphics) else {
            throw RumError.message("This engine does not provide the selected graphics component. Choose an option listed for its runtime.")
        }
        guard graphics != .dxvk || (try? Wine.validateDXVK(entry.shotglass.runtime.dxvkPackage)) != nil else {
            throw RumError.message("This shotglass's DXVK package is missing or incomplete. Install a DXVK version in Runtimes & setup first.")
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
        let oldDXVK = entry.shotglass.runtime.dxvkPackage
        let oldDXMT = entry.shotglass.runtime.dxmtPackage
        if previous == .dxvk { try Wine.validateDXVK(oldDXVK) }
        if previous == .dxmt, let oldDXMT { try Wine.validateDXMT(oldDXMT) }
        try await Wine.stopServer(entry)

        var changed = entry
        changed.shotglass.graphics = graphics
        do {
            if previous == .dxvk { try Wine.removeDXVK(from: entry.prefix) }
            if previous == .dxmt, oldDXMT != nil { try Wine.removeDXMT(from: entry.prefix) }
            if graphics == .dxvk, let package = entry.shotglass.runtime.dxvkPackage {
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
}
