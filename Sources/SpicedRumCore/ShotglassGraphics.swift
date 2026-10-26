import Foundation

public enum ShotglassGraphics {
    public static func choices(for runtime: Runtime) -> [Graphics] {
        var choices: [Graphics] = [.wine]
        if runtime.dxvkPackage != nil && (try? Wine.validateDXVK(runtime.dxvkPackage)) != nil { choices.append(.dxvk) }
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

    public static func canUse(_ backend: Direct3D9Backend, package: URL?, runtime: Runtime) -> Bool {
        switch backend {
        case .wine: return true
        case .mtld3d: return (try? Wine.validateMTLD3D(package)) != nil && (try? Wine.validateMTLD3DRuntime(runtime, package: package)) != nil
        }
    }

    public static func canUse(_ backend: Direct3D12Backend, package: URL?, dxgiPackage: URL?, runtime: Runtime) -> Bool {
        switch backend {
        case .wine: return true
        case .vkd3dProton:
            return (try? Wine.validateVKD3DProton(package)) != nil
                && (try? Wine.validateDXGI(dxgiPackage)) != nil
                && EngineInstaller.supportsVKD3DProton(runtime)
        }
    }

    public static func canUse(_ backend: VulkanBackend, runtime: Runtime) -> Bool {
        switch backend {
        case .runtimeDefault: return true
        case .moltenVK: return EngineInstaller.supportsMoltenVK(runtime)
        case .legacyKosmicKrisp: return false
        }
    }

    public static func canUse(_ backend: OpenGLBackend, package: URL?, runtime: Runtime) -> Bool {
        switch backend {
        case .wine: return true
        case .zink:
            return (try? Wine.validateZink(package)) != nil
                && EngineInstaller.supportsMoltenVK(runtime)
        }
    }

    public static func validateSettings(_ entry: ShotglassEntry,
                                        graphics: Graphics,
                                        dxvkPackage: URL?,
                                        direct3D9: Direct3D9Backend,
                                        direct3D9Package: URL?,
                                        direct3D12: Direct3D12Backend,
                                        direct3D12Package: URL?,
                                        dxgiPackage: URL?,
                                        vulkan: VulkanBackend,
                                        openGL: OpenGLBackend,
                                        openGLPackage: URL?) throws {
        guard !entry.engineChangePending else {
            throw RumError.message("Restore the pending engine backup before changing graphics for this shotglass.")
        }
        switch graphics {
        case .wine: break
        case .dxvk:
            guard EngineInstaller.supportsMacOSDXVK(entry.shotglass.runtime) || entry.dxvkPackage != nil else {
                throw RumError.message("This engine does not provide the macOS Vulkan support required by DXVK.")
            }
            try Wine.validateDXVK(dxvkPackage)
        case .metal:
            guard entry.shotglass.runtime.d3dMetal else { throw RumError.message("D3DMetal requires a runtime with D3DMetal already integrated.") }
        case .dxmt:
            guard entry.shotglass.runtime.dxmt else { throw RumError.message("DXMT requires a runtime with DXMT support.") }
            if let package = entry.shotglass.runtime.dxmtPackage { try Wine.validateDXMT(package) }
        }
        try validateAPIBackends(
            entry, direct3D9: direct3D9, direct3D9Package: direct3D9Package,
            direct3D12: direct3D12, direct3D12Package: direct3D12Package, dxgiPackage: dxgiPackage,
            vulkan: vulkan, openGL: openGL, openGLPackage: openGLPackage
        )
    }

    private static func validateAPIBackends(_ entry: ShotglassEntry,
                                            direct3D9: Direct3D9Backend,
                                            direct3D9Package: URL?,
                                            direct3D12: Direct3D12Backend,
                                            direct3D12Package: URL?,
                                            dxgiPackage: URL?,
                                            vulkan: VulkanBackend,
                                            openGL: OpenGLBackend,
                                            openGLPackage: URL?) throws {
        guard canUse(direct3D9, package: direct3D9Package, runtime: entry.shotglass.runtime) else {
            throw RumError.message("Install a compatible mtld3d package and Wine engine support before selecting it for Direct3D 9.")
        }
        guard canUse(direct3D12, package: direct3D12Package, dxgiPackage: dxgiPackage, runtime: entry.shotglass.runtime) else {
            throw RumError.message("VKD3D-Proton needs its 64-bit DLLs, the matching DXVK DXGI bridge, and a Wine Vulkan driver this engine can load.")
        }
        guard canUse(vulkan, runtime: entry.shotglass.runtime) else {
            throw RumError.message("This engine does not include the selected Vulkan driver.")
        }
        guard canUse(openGL, package: openGLPackage, runtime: entry.shotglass.runtime) else {
            throw RumError.message("Zink needs its 32-bit and 64-bit package and a Vulkan driver supported by this engine.")
        }
        guard direct3D12 != .vkd3dProton || entry.shotglass.graphics == .wine else {
            throw RumError.message("VKD3D-Proton needs the Wine default Direct3D 10/11 renderer because DXVK, DXMT, and D3DMetal use a different DXGI or Direct3D 12 implementation.")
        }
    }

    public static func changeSettings(_ entry: ShotglassEntry,
                                      graphics: Graphics,
                                      dxvkPackage: URL?,
                                      direct3D9: Direct3D9Backend,
                                      direct3D9Package: URL?,
                                      direct3D12: Direct3D12Backend,
                                      direct3D12Package: URL?,
                                      dxgiPackage: URL?,
                                      vulkan: VulkanBackend,
                                      openGL: OpenGLBackend,
                                      openGLPackage: URL?) async throws -> ShotglassEntry {
        var candidate = entry
        candidate.shotglass.graphics = graphics
        if graphics == .dxvk { candidate.shotglass.dxvkPackage = dxvkPackage }
        try validateSettings(
            candidate, graphics: graphics, dxvkPackage: dxvkPackage,
            direct3D9: direct3D9, direct3D9Package: direct3D9Package,
            direct3D12: direct3D12, direct3D12Package: direct3D12Package, dxgiPackage: dxgiPackage,
            vulkan: vulkan, openGL: openGL, openGLPackage: openGLPackage
        )
        var updated = entry
        do {
            let mustDisableVKD3DFirst = graphics != .wine && entry.shotglass.direct3D12 == .vkd3dProton
            if mustDisableVKD3DFirst {
                updated = try await changeAPIBackends(
                    updated, direct3D9: direct3D9, direct3D9Package: direct3D9Package,
                    direct3D12: direct3D12, direct3D12Package: direct3D12Package, dxgiPackage: dxgiPackage,
                    vulkan: vulkan, openGL: openGL, openGLPackage: openGLPackage
                )
            }
            updated = try await change(updated, to: graphics, dxvkPackage: dxvkPackage)
            if !mustDisableVKD3DFirst {
                updated = try await changeAPIBackends(
                    updated, direct3D9: direct3D9, direct3D9Package: direct3D9Package,
                    direct3D12: direct3D12, direct3D12Package: direct3D12Package, dxgiPackage: dxgiPackage,
                    vulkan: vulkan, openGL: openGL, openGLPackage: openGLPackage
                )
            }
            return updated
        } catch {
            let failure = error
            do {
                if updated.shotglass.graphics != entry.shotglass.graphics
                    || updated.dxvkPackage?.standardizedFileURL != entry.dxvkPackage?.standardizedFileURL {
                    updated = try await change(updated, to: entry.shotglass.graphics, dxvkPackage: entry.dxvkPackage)
                }
                if updated.shotglass.direct3D9 != entry.shotglass.direct3D9
                    || updated.shotglass.mtld3dPackage != entry.shotglass.mtld3dPackage
                    || updated.shotglass.direct3D12 != entry.shotglass.direct3D12
                    || updated.shotglass.vkd3dProtonPackage != entry.shotglass.vkd3dProtonPackage
                    || updated.shotglass.dxgiPackage != entry.shotglass.dxgiPackage
                    || updated.shotglass.vulkan != entry.shotglass.vulkan
                    || updated.shotglass.openGL != entry.shotglass.openGL
                    || updated.shotglass.zinkPackage != entry.shotglass.zinkPackage {
                    updated = try await changeAPIBackends(
                        updated,
                        direct3D9: entry.shotglass.direct3D9 ?? .wine,
                        direct3D9Package: entry.mtld3dPackage,
                        direct3D12: entry.shotglass.direct3D12 ?? .wine,
                        direct3D12Package: entry.vkd3dProtonPackage,
                        dxgiPackage: entry.dxgiPackage,
                        vulkan: entry.shotglass.vulkan ?? .runtimeDefault,
                        openGL: entry.shotglass.openGL ?? .wine,
                        openGLPackage: entry.zinkPackage
                    )
                }
                if updated.shotglass.dxvkPackage != entry.shotglass.dxvkPackage {
                    updated.shotglass.dxvkPackage = entry.shotglass.dxvkPackage
                    try updated.shotglass.save(in: updated.folder)
                }
            } catch {
                throw RumError.message("The graphics change failed and the previous settings could not be restored.\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw failure
        }
    }

    public static func changeAPIBackends(_ entry: ShotglassEntry,
                                         direct3D9: Direct3D9Backend,
                                         direct3D9Package: URL?,
                                         direct3D12: Direct3D12Backend,
                                         direct3D12Package: URL?,
                                         dxgiPackage: URL?,
                                         vulkan: VulkanBackend,
                                         openGL: OpenGLBackend,
                                         openGLPackage: URL?) async throws -> ShotglassEntry {
        try validateAPIBackends(
            entry, direct3D9: direct3D9, direct3D9Package: direct3D9Package,
            direct3D12: direct3D12, direct3D12Package: direct3D12Package, dxgiPackage: dxgiPackage,
            vulkan: vulkan, openGL: openGL, openGLPackage: openGLPackage
        )

        var changed = entry
        changed.shotglass.direct3D9 = direct3D9
        changed.shotglass.mtld3dPackage = direct3D9 == .mtld3d ? direct3D9Package : nil
        changed.shotglass.direct3D12 = direct3D12
        changed.shotglass.vkd3dProtonPackage = direct3D12Package
        changed.shotglass.dxgiPackage = dxgiPackage
        changed.shotglass.vulkan = vulkan
        changed.shotglass.openGL = openGL
        changed.shotglass.zinkPackage = openGL == .zink ? openGLPackage : nil
        guard changed.shotglass.direct3D9 != entry.shotglass.direct3D9
            || changed.shotglass.mtld3dPackage != entry.shotglass.mtld3dPackage
            || changed.shotglass.direct3D12 != entry.shotglass.direct3D12
            || changed.shotglass.vkd3dProtonPackage != entry.shotglass.vkd3dProtonPackage
            || changed.shotglass.dxgiPackage != entry.shotglass.dxgiPackage
            || changed.shotglass.vulkan != entry.shotglass.vulkan
            || changed.shotglass.openGL != entry.shotglass.openGL
            || changed.shotglass.zinkPackage != entry.shotglass.zinkPackage else { return entry }

        guard entry.shotglass.initialized else {
            try changed.shotglass.save(in: changed.folder)
            return changed
        }
        try await Wine.stopServer(entry)
        do {
            if entry.shotglass.direct3D9 == .mtld3d { try Wine.removeMTLD3D(from: entry.prefix) }
            if entry.shotglass.direct3D12 == .vkd3dProton { try Wine.removeVKD3DProton(from: entry.prefix) }
            if entry.shotglass.openGL == .zink { try Wine.removeZink(from: entry.prefix) }
            if direct3D9 == .mtld3d, let direct3D9Package {
                try Wine.installMTLD3D(from: direct3D9Package, into: entry.prefix, runtime: entry.shotglass.runtime)
            }
            if direct3D12 == .vkd3dProton, let direct3D12Package, let dxgiPackage {
                try Wine.installVKD3DProton(from: direct3D12Package, dxgi: dxgiPackage, into: entry.prefix)
            }
            if openGL == .zink, let openGLPackage { try Wine.installZink(from: openGLPackage, into: entry.prefix) }
            try changed.shotglass.save(in: changed.folder)
            return changed
        } catch {
            let failure = error
            do {
                if direct3D9 == .mtld3d { try Wine.removeMTLD3D(from: entry.prefix) }
                if direct3D12 == .vkd3dProton { try Wine.removeVKD3DProton(from: entry.prefix) }
                if openGL == .zink { try Wine.removeZink(from: entry.prefix) }
                if entry.shotglass.direct3D9 == .mtld3d, let package = entry.mtld3dPackage {
                    try Wine.installMTLD3D(from: package, into: entry.prefix, runtime: entry.shotglass.runtime)
                }
                if entry.shotglass.direct3D12 == .vkd3dProton, let package = entry.vkd3dProtonPackage {
                    if let dxgi = entry.dxgiPackage { try Wine.installVKD3DProton(from: package, dxgi: dxgi, into: entry.prefix) }
                }
                if entry.shotglass.openGL == .zink, let package = entry.zinkPackage { try Wine.installZink(from: package, into: entry.prefix) }
                try entry.shotglass.save(in: entry.folder)
            } catch {
                throw RumError.message("The graphics change failed and the previous API backends could not be restored. The shotglass files were left in place.\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw RumError.message("The graphics change failed. The previous API backends were restored.\n\(failure.localizedDescription)")
        }
    }

    public static func change(_ entry: ShotglassEntry, to graphics: Graphics, dxvkPackage: URL? = nil) async throws -> ShotglassEntry {
        guard !entry.engineChangePending else {
            throw RumError.message("Restore the pending engine backup before changing graphics for this shotglass.")
        }
        let choices = choices(for: entry)
        guard choices.contains(graphics) || (graphics == .dxvk && EngineInstaller.supportsMacOSDXVK(entry.shotglass.runtime)) else {
            throw RumError.message("This engine does not provide the selected graphics component. Choose an option listed for its runtime.")
        }
        let selectedDXVK = dxvkPackage ?? entry.dxvkPackage
        guard graphics != .dxvk || (try? Wine.validateDXVK(selectedDXVK)) != nil else {
            throw RumError.message("This shotglass does not have a DXVK version selected. Install and assign one in Settings first.")
        }
        guard graphics == .wine || entry.shotglass.direct3D12 != .vkd3dProton else {
            throw RumError.message("VKD3D-Proton needs the Wine default Direct3D 10/11 renderer. Change the Direct3D 12 backend to Wine default before changing graphics.")
        }
        if graphics == .dxmt, let package = entry.shotglass.runtime.dxmtPackage { try Wine.validateDXMT(package) }
        let changingDXVKVersion = graphics == .dxvk
            && selectedDXVK?.standardizedFileURL != entry.dxvkPackage?.standardizedFileURL
        guard entry.shotglass.graphics != graphics || changingDXVKVersion else { return entry }

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
        if graphics == .dxvk { changed.shotglass.dxvkPackage = selectedDXVK }
        do {
            if previous == .dxvk { try Wine.removeDXVK(from: entry.prefix) }
            if previous == .dxmt, oldDXMT != nil { try Wine.removeDXMT(from: entry.prefix) }
            if graphics == .dxvk, let package = selectedDXVK {
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
