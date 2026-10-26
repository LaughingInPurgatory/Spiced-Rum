import Foundation

public enum Wine {
    public static func checkExecutable(_ url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw RumError.message("The Wine executable is missing or is not executable at \(url.path). Select wine or wine64 from a complete macOS runtime.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4) ?? Data()
        if Array(magic) == [0x7f, 0x45, 0x4c, 0x46] {
            throw RumError.message("This is a Linux executable. Proton and Proton-GE require Linux; choose a macOS Wine build instead.")
        }
    }

    public static func environment(for entry: ShotglassEntry) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Do not inherit another Wine session's prefix or renderer overrides.
        for key in ["WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINESERVER", "WINELOADER", "WINEDLLPATH_PREPEND", "WINEMSYNC", "DXVK_CONFIG_FILE", "DXVK_LOG_PATH", "GRAPHICS_BACKEND", "VK_DRIVER_FILES", "VK_ICD_FILENAMES", "GALLIUM_DRIVER"] { env.removeValue(forKey: key) }
        env["WINEPREFIX"] = entry.prefix.path
        let runtime = entry.shotglass.runtime
        let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        let launcher = runtime.executable.deletingLastPathComponent().lastPathComponent
        let wineBin = ["spiced-rum-launchers", "spiced-rum-barrel-launchers"].contains(launcher) ? engine.appendingPathComponent("bin").path : runtime.executable.deletingLastPathComponent().path
        env["PATH"] = runtime.executable.deletingLastPathComponent().path + ":" + wineBin + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["WINEDEBUG"] = "-all,err+all"
        if FileManager.default.fileExists(atPath: engine.appendingPathComponent("barrel-wine.json").path) {
            env["WINEMSYNC"] = "1"
            env["WINEBOOT_HIDE_DIALOG"] = "1"
            env["ROSETTA_ADVERTISE_AVX"] = "1"
        }
        if let framework = MediaSupport.framework(for: entry.shotglass.runtime) {
            env.merge(MediaSupport.environment(framework: framework, registry: entry.folder.appendingPathComponent("gstreamer-registry-x86_64-v1.bin"))) { _, new in new }
        }
        switch entry.shotglass.graphics {
        case .wine: break
        case .dxvk:
            // macOS DXVK packages use Wine's DXGI rather than upstream DXVK's DXGI.
            env["WINEDLLOVERRIDES"] = "dxgi=b;d3d11,d3d10core=n,b"
            env["DXVK_LOG_PATH"] = entry.folder.path
        case .metal:
            env["WINEDLLOVERRIDES"] = "dxgi,d3d11,d3d12=n,b"
        case .dxmt:
            env["WINEDLLOVERRIDES"] = "dxgi,d3d10core,d3d11,winemetal=b"
            if let package = runtime.dxmtPackage {
                env["WINEDLLPATH_PREPEND"] = package.path
                env["WINEMSYNC"] = "1"
            }
        }
        var overrides = [env["WINEDLLOVERRIDES"]].compactMap { $0 }.filter { !$0.isEmpty }
        if entry.shotglass.direct3D9 == .mtld3d { overrides.append("d3d9=n,b") }
        if entry.shotglass.direct3D12 == .vkd3dProton { overrides.append("dxgi,d3d12,d3d12core=n,b") }
        if entry.shotglass.openGL == .zink { overrides.append("opengl32=n,b") }
        if !overrides.isEmpty { env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";") }
        if entry.shotglass.openGL == .zink { env["GALLIUM_DRIVER"] = "zink" }
        switch entry.shotglass.vulkan {
        case .legacyKosmicKrisp, .moltenVK, .runtimeDefault, nil:
            if let manifest = EngineInstaller.moltenVKManifest(for: runtime) {
                env["VK_DRIVER_FILES"] = manifest.path
                env["VK_ICD_FILENAMES"] = manifest.path
            }
        }
        return env
    }

    public static func command(runtime: Runtime, arguments: [String]) -> (URL, [String]) {
        if runtime.executable.deletingLastPathComponent().lastPathComponent == "spiced-rum-barrel-launchers" {
            return runtime.useRosetta
                ? (URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", runtime.executable.path] + arguments)
                : (runtime.executable, arguments)
        }
        if let framework = MediaSupport.framework(for: runtime) {
            let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
            // Our Sikarugir launchers set a different dyld path. Launch their native
            // payload directly here with both the media and engine libraries prepared.
            let executable = runtime.executable.deletingLastPathComponent().lastPathComponent == "spiced-rum-launchers"
                ? engine.appendingPathComponent("bin/" + runtime.executable.lastPathComponent) : runtime.executable
            // Wine's GNU libiconv must not replace macOS libiconv used by GLib.
            // Engine libraries belong in the fallback search, after system paths.
            let fallbackLibraries = engine.appendingPathComponent("lib").path + ":/usr/local/lib:/usr/lib"
            return MediaSupport.command(executable, arguments: arguments, libraries: framework.appendingPathComponent("Versions/1.0/lib").path, rosetta: runtime.useRosetta, fallbackLibraries: fallbackLibraries)
        }
        return runtime.useRosetta
            ? (URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", runtime.executable.path] + arguments)
            : (runtime.executable, arguments)
    }

    public static func execute(runtime: Runtime, arguments: [String], environment: [String: String], directory: URL, log: URL, timeout: TimeInterval? = nil) async throws {
        try checkExecutable(runtime.executable)
        try await MediaSupport.prepare(runtime)
        var environment = environment
        if let framework = MediaSupport.framework(for: runtime) {
            let prefix = environment["WINEPREFIX"].map { URL(fileURLWithPath: $0) }
            environment.merge(MediaSupport.environment(framework: framework, registry: (prefix?.deletingLastPathComponent() ?? directory).appendingPathComponent("gstreamer-registry-x86_64-v1.bin"))) { _, new in new }
        }
        let (binary, args) = command(runtime: runtime, arguments: arguments)
        try await ProcessRunner.run(binary, args, environment: environment, directory: directory, log: log, label: runtime.name, timeout: timeout)
    }

    public static func probe(_ runtime: Runtime) async throws -> String {
        try checkExecutable(runtime.executable)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Probe has no access to an existing prefix. A runtime is still external code chosen by the user.
        let (binary, args) = command(runtime: runtime, arguments: ["--version"])
        let environment = ["PATH": runtime.executable.deletingLastPathComponent().path + ":/usr/bin:/bin", "HOME": NSHomeDirectory(), "WINEPREFIX": folder.appendingPathComponent("prefix").path]
        let version = try await ProcessRunner.capture(binary, args, environment: environment, timeout: 60).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.lowercased().contains("wine"), version.count < 2000 else {
            let output = version.isEmpty ? "(The process produced no output.)" : String(version.prefix(1500))
            throw RumError.message("Wine --version did not report a valid version. Check that this is a complete macOS runtime and that its required translation support is available.\n\(output)")
        }
        return version
    }

    public static func initialize(_ entry: ShotglassEntry, dxvk: URL?, updating: Bool = false) async throws -> ShotglassEntry {
        if entry.shotglass.graphics == .metal && !entry.shotglass.runtime.d3dMetal {
            throw RumError.message("D3DMetal requires a runtime with D3DMetal already integrated.")
        }
        if entry.shotglass.graphics == .dxmt && !entry.shotglass.runtime.dxmt {
            throw RumError.message("DXMT requires a runtime or launcher with DXMT already integrated.")
        }
        if entry.shotglass.graphics == .dxmt, let package = entry.shotglass.runtime.dxmtPackage { try validateDXMT(package) }
        if entry.shotglass.graphics == .dxvk { try validateDXVK(dxvk) }
        if entry.shotglass.direct3D9 == .mtld3d { try validateMTLD3D(entry.mtld3dPackage); try validateMTLD3DRuntime(entry.shotglass.runtime, package: entry.mtld3dPackage) }
        if entry.shotglass.direct3D12 == .vkd3dProton {
            try validateVKD3DProton(entry.vkd3dProtonPackage)
            try validateDXGI(entry.dxgiPackage)
            guard EngineInstaller.supportsVKD3DProton(entry.shotglass.runtime) else {
                throw RumError.message("VKD3D-Proton needs an engine with a working Wine Vulkan bridge and Vulkan driver.")
            }
            guard entry.shotglass.graphics == .wine else {
                throw RumError.message("VKD3D-Proton requires Wine default graphics. Change away from DXVK, DXMT, or D3DMetal first.")
            }
        }
        if entry.shotglass.openGL == .zink {
            try validateZink(entry.zinkPackage)
            guard EngineInstaller.supportsMoltenVK(entry.shotglass.runtime) else {
                throw RumError.message("Zink needs a Vulkan driver included with the selected engine.")
            }
        }
        if (entry.shotglass.vulkan == .moltenVK || entry.shotglass.vulkan == .legacyKosmicKrisp)
            && !EngineInstaller.supportsMoltenVK(entry.shotglass.runtime) {
            throw RumError.message("This engine does not include a MoltenVK driver manifest.")
        }
        // Renderer DLLs are installed only after Wine creates its original prefix.
        var plain = entry
        plain.shotglass.graphics = .wine
        plain.shotglass.direct3D9 = .wine; plain.shotglass.direct3D12 = .wine
        plain.shotglass.vulkan = .runtimeDefault; plain.shotglass.openGL = .wine
        try await execute(runtime: entry.shotglass.runtime, arguments: ["wineboot", updating ? "--update" : "--init"], environment: environment(for: plain), directory: entry.folder, log: entry.log, timeout: 180)
        // wineboot can return before setup children finish and the registry is flushed.
        // Wait on this prefix's server, rather than checking half-written files.
        let server = entry.shotglass.runtime.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
        if FileManager.default.isExecutableFile(atPath: server.path) {
            var serverRuntime = entry.shotglass.runtime; serverRuntime.executable = server
            let (binary, args) = command(runtime: serverRuntime, arguments: ["-w"])
            try await ProcessRunner.run(binary, args, environment: environment(for: plain), directory: entry.folder, log: entry.log, label: "Waiting for Windows setup", timeout: 120)
        }
        guard FileManager.default.fileExists(atPath: entry.prefix.appendingPathComponent("system.reg").path),
              FileManager.default.fileExists(atPath: entry.prefix.appendingPathComponent("drive_c/windows/system32").path) else {
            throw RumError.message("Wine did not finish creating the prefix. Review the session log, then retry initialization.")
        }
        let registry = try String(contentsOf: entry.prefix.appendingPathComponent("system.reg"), encoding: .utf8)
        guard registry.contains("#arch=win64") else { throw RumError.message("This runtime created a 32-bit prefix. Spiced-Rum requires a Windows x64-capable macOS engine.") }
        if entry.shotglass.graphics == .dxvk, let dxvk { try installDXVK(from: dxvk, into: entry.prefix) }
        if entry.shotglass.graphics == .dxmt, let package = entry.shotglass.runtime.dxmtPackage { try installDXMT(from: package, into: entry.prefix) }
        if entry.shotglass.direct3D9 == .mtld3d, let package = entry.mtld3dPackage {
            try installMTLD3DRuntime(from: package, for: entry.shotglass.runtime)
            try installMTLD3D(from: package, into: entry.prefix, runtime: entry.shotglass.runtime)
        }
        if entry.shotglass.direct3D12 == .vkd3dProton, let package = entry.vkd3dProtonPackage, let dxgi = entry.dxgiPackage {
            try installVKD3DProton(from: package, dxgi: dxgi, into: entry.prefix)
        }
        if entry.shotglass.openGL == .zink, let package = entry.zinkPackage { try installZink(from: package, into: entry.prefix) }
        var ready = entry; ready.shotglass.initialized = true
        try ready.shotglass.save(in: ready.folder)
        return ready
    }

    public static func stopServer(_ entry: ShotglassEntry) async throws {
        var serverRuntime = entry.shotglass.runtime
        serverRuntime.executable = serverRuntime.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
        try checkExecutable(serverRuntime.executable)
        for args in [["-k"], ["-w"]] {
            let (binary, arguments) = command(runtime: serverRuntime, arguments: args)
            do {
                try await ProcessRunner.run(binary, arguments, environment: environment(for: entry), directory: entry.folder, log: entry.log, label: "Stopping this shotglass's Windows processes", timeout: 30)
            } catch {
                // -k exits 1 if no server exists. The mandatory -w below verifies shutdown.
                if args == ["-w"] { throw error }
            }
        }
    }

    public static func removeDXVK(from prefix: URL) throws {
        let fm = FileManager.default
        for target in ["system32", "syswow64"] {
            for dll in ["d3d11.dll", "d3d10core.dll"] {
                let file = prefix.appendingPathComponent("drive_c/windows/\(target)/\(dll)")
                let backup = file.appendingPathExtension("spicedrum-original")
                if (try? fm.attributesOfItem(atPath: file.path)) != nil { try fm.removeItem(at: file) }
                if (try? fm.attributesOfItem(atPath: backup.path)) != nil { try fm.moveItem(at: backup, to: file) }
            }
        }
    }

    public static func removeDXMT(from prefix: URL) throws {
        let fm = FileManager.default
        for target in ["system32", "syswow64"] {
            let file = prefix.appendingPathComponent("drive_c/windows/\(target)/winemetal.dll")
            let backup = file.appendingPathExtension("spicedrum-original")
            if (try? fm.attributesOfItem(atPath: file.path)) != nil { try fm.removeItem(at: file) }
            if (try? fm.attributesOfItem(atPath: backup.path)) != nil { try fm.moveItem(at: backup, to: file) }
        }
    }

    public static func validateMTLD3D(_ folder: URL?) throws {
        guard let folder, EngineInstaller.isGraphicsPackage(folder, source: .mtld3d) else {
            throw RumError.message("Install a complete mtld3d release from Runtimes & setup first.")
        }
    }

    public static func validateMTLD3DRuntime(_ runtime: Runtime, package: URL?) throws {
        guard let package, runtime.managedRoot != nil else {
            throw RumError.message("mtld3d needs an installed package and a Spiced-Rum-managed Wine engine.")
        }
        let wineRoot = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: wineRoot.appendingPathComponent("lib/wine", isDirectory: true).path) else {
            throw RumError.message("This engine does not include the Wine library tree needed by mtld3d.")
        }
        if runtime.useRosetta {
            guard FileManager.default.isReadableFile(atPath: package.appendingPathComponent("wine/x86_64-unix/mtld3d.so").path),
                  FileManager.default.isReadableFile(atPath: package.appendingPathComponent("wine/x86_64-windows/mtld3d.dll").path) else {
                throw RumError.message("This mtld3d release does not include the x86_64 Wine bridge required by this engine.")
            }
        } else {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            guard os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 4) else {
                throw RumError.message("mtld3d's arm64 Wine bridge requires macOS 26.4 or later. On an older macOS version, use an x86_64 Wine engine through Rosetta 2.")
            }
            guard FileManager.default.isReadableFile(atPath: package.appendingPathComponent("wine/aarch64-unix/mtld3d.so").path),
                  FileManager.default.isReadableFile(atPath: package.appendingPathComponent("wine/aarch64-windows/mtld3d.dll").path)
                    || FileManager.default.isReadableFile(atPath: package.appendingPathComponent("wine/x86_64-windows/mtld3d.dll").path) else {
                throw RumError.message("This mtld3d release does not include the arm64 Unix bridge and 64-bit Wine files required by this engine.")
            }
        }
    }

    public static func validateVKD3DProton(_ folder: URL?) throws {
        guard let folder, EngineInstaller.isGraphicsPackage(folder, source: .vkd3dProton),
              EngineInstaller.vkd3dProtonDLL(folder, named: "d3d12.dll") != nil,
              EngineInstaller.vkd3dProtonDLL(folder, named: "d3d12core.dll") != nil else {
            throw RumError.message("Install a VKD3D-Proton release containing the 64-bit d3d12.dll and d3d12core.dll first.")
        }
    }

    public static func validateDXGI(_ folder: URL?) throws {
        guard let folder, EngineInstaller.isGraphicsPackage(folder, source: .dxgi), EngineInstaller.dxgiDLL(folder) != nil else {
            throw RumError.message("Install a DXVK release containing the 64-bit DXGI DLL required by VKD3D-Proton first.")
        }
    }

    public static func validateZink(_ folder: URL?) throws {
        guard let folder, EngineInstaller.isGraphicsPackage(folder, source: .zink) else {
            throw RumError.message("Install a Mesa Zink package containing both 32-bit and 64-bit OpenGL DLLs first.")
        }
    }

    public static func installMTLD3DRuntime(from package: URL, for runtime: Runtime) throws {
        try validateMTLD3D(package); try validateMTLD3DRuntime(runtime, package: package)
        let wineRoot = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        let defaultTree = wineRoot.appendingPathComponent("lib/wine", isDirectory: true)
        let specializedTree = defaultTree.appendingPathComponent("d3d9/mtld3d", isDirectory: true)
        let tree = FileManager.default.fileExists(atPath: specializedTree.path) ? specializedTree : defaultTree
        let hostArch = runtime.useRosetta ? "x86_64" : "aarch64"
        let windowsSource = !runtime.useRosetta && !FileManager.default.fileExists(atPath: package.appendingPathComponent("wine/aarch64-windows/mtld3d.dll").path) ? "x86_64" : hostArch
        let mappings = [
            ("wine/i386-windows/mtld3d.dll", "i386-windows/mtld3d.dll"),
            ("wine/\(windowsSource)-windows/mtld3d.dll", "\(hostArch)-windows/mtld3d.dll"),
            ("wine/\(hostArch)-unix/mtld3d.so", "\(hostArch)-unix/mtld3d.so")
        ]
        for (source, destination) in mappings {
            let input = package.appendingPathComponent(source)
            guard FileManager.default.isReadableFile(atPath: input.path) else {
                throw RumError.message("This mtld3d release does not include the \(hostArch) Wine bridge required by this engine.")
            }
            try installEngineFile(input, at: tree.appendingPathComponent(destination))
        }
    }

    public static func installMTLD3D(from package: URL, into prefix: URL, runtime: Runtime) throws {
        try installMTLD3DRuntime(from: package, for: runtime)
        let hostArch = runtime.useRosetta ? "x86_64" : "aarch64"
        for (architecture, target) in [(hostArch, "system32"), ("i386", "syswow64")] {
            var dll = package.appendingPathComponent("native/\(architecture)-windows/d3d9.dll")
            if !FileManager.default.isReadableFile(atPath: dll.path), architecture == "aarch64" {
                dll = package.appendingPathComponent("native/x86_64-windows/d3d9.dll")
            }
            guard FileManager.default.isReadableFile(atPath: dll.path) else {
                throw RumError.message("mtld3d is missing its \(architecture) Direct3D 9 DLL.")
            }
            try installPrefixDLL(dll, into: prefix, directory: target, name: "d3d9.dll")
            var markerName = target == "system32" && hostArch == "aarch64" ? "system32-arm64" : target
            let marker = package.appendingPathComponent("prefix-markers/\(markerName)/mtld3d.dll")
            if FileManager.default.isReadableFile(atPath: marker.path) {
                try installPrefixDLL(marker, into: prefix, directory: target, name: "mtld3d.dll")
            } else if target == "system32" && hostArch == "aarch64" {
                markerName = "system32"
                let amd64Marker = package.appendingPathComponent("prefix-markers/\(markerName)/mtld3d.dll")
                if FileManager.default.isReadableFile(atPath: amd64Marker.path) {
                    try installPrefixDLL(amd64Marker, into: prefix, directory: target, name: "mtld3d.dll")
                }
            }
        }
    }

    public static func removeMTLD3D(from prefix: URL) throws {
        for target in ["system32", "syswow64"] {
            removePrefixDLL(from: prefix, directory: target, name: "d3d9.dll")
            removePrefixDLL(from: prefix, directory: target, name: "mtld3d.dll")
        }
    }

    public static func installVKD3DProton(from package: URL, dxgi: URL, into prefix: URL) throws {
        try validateVKD3DProton(package); try validateDXGI(dxgi)
        guard let dxgiDLL = EngineInstaller.dxgiDLL(dxgi) else { throw RumError.message("DXVK's 64-bit dxgi.dll is missing.") }
        try installPrefixDLL(dxgiDLL, into: prefix, directory: "system32", name: "dxgi.dll")
        for name in ["d3d12.dll", "d3d12core.dll"] {
            guard let source = EngineInstaller.vkd3dProtonDLL(package, named: name) else {
                throw RumError.message("VKD3D-Proton is missing its 64-bit \(name).")
            }
            try installPrefixDLL(source, into: prefix, directory: "system32", name: name)
        }
    }

    public static func removeVKD3DProton(from prefix: URL) throws {
        for name in ["d3d12.dll", "d3d12core.dll"] { removePrefixDLL(from: prefix, directory: "system32", name: name) }
        removePrefixDLL(from: prefix, directory: "system32", name: "dxgi.dll")
    }

    public static func installZink(from package: URL, into prefix: URL) throws {
        try validateZink(package)
        for (architecture, target) in [("x64", "system32"), ("x86", "syswow64")] {
            guard let opengl = EngineInstaller.zinkOpenGLDLL(package, architecture: architecture) else {
                throw RumError.message("Mesa Zink is missing its \(architecture) opengl32.dll.")
            }
            let architectureRoot = opengl.deletingLastPathComponent()
            for name in ["opengl32.dll", "libgallium_wgl.dll", "libglapi.dll", "dxil.dll"] {
                let source = architectureRoot.appendingPathComponent(name)
                guard FileManager.default.isReadableFile(atPath: source.path) else { continue }
                try installPrefixDLL(source, into: prefix, directory: target, name: name)
            }
        }
    }

    public static func removeZink(from prefix: URL) throws {
        for target in ["system32", "syswow64"] {
            for name in ["opengl32.dll", "libgallium_wgl.dll", "libglapi.dll", "dxil.dll"] { removePrefixDLL(from: prefix, directory: target, name: name) }
        }
    }

    private static func installEngineFile(_ source: URL, at destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = destination.appendingPathExtension("spicedrum-original")
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            if (try? fm.attributesOfItem(atPath: backup.path)) == nil { try fm.moveItem(at: destination, to: backup) }
            else { try fm.removeItem(at: destination) }
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func installPrefixDLL(_ source: URL, into prefix: URL, directory: String, name: String) throws {
        let fm = FileManager.default
        let destination = prefix.appendingPathComponent("drive_c/windows/\(directory)/\(name)")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = destination.appendingPathExtension("spicedrum-original")
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            if (try? fm.attributesOfItem(atPath: backup.path)) == nil { try fm.moveItem(at: destination, to: backup) }
            else { try fm.removeItem(at: destination) }
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func removePrefixDLL(from prefix: URL, directory: String, name: String) {
        let fm = FileManager.default
        let destination = prefix.appendingPathComponent("drive_c/windows/\(directory)/\(name)")
        let backup = destination.appendingPathExtension("spicedrum-original")
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil { try? fm.removeItem(at: destination) }
        if (try? fm.attributesOfItem(atPath: backup.path)) != nil { try? fm.moveItem(at: backup, to: destination) }
    }

    public static func validateDXVK(_ folder: URL?) throws {
        guard let folder else { throw RumError.message("Choose an extracted macOS DXVK package containing x64/d3d11.dll and x64/d3d10core.dll. Its Wine runtime must also supply MoltenVK.") }
        for arch in ["x64", "x32"] {
            if arch == "x32" && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(arch).path) { continue }
            for dll in ["d3d11.dll", "d3d10core.dll"] {
                guard FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("\(arch)/\(dll)").path) else {
                    throw RumError.message("DXVK package is missing \(arch)/\(dll).")
                }
            }
        }
    }

    public static func validateDXMT(_ folder: URL) throws {
        for relative in ["x86_64-unix/winemetal.so", "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll"] {
            guard FileManager.default.isReadableFile(atPath: folder.appendingPathComponent(relative).path) else {
                throw RumError.message("DXMT package is missing its Wine builtin component \(relative).")
            }
        }
    }

    public static func installDXVK(from source: URL, into prefix: URL) throws {
        let fm = FileManager.default
        for (arch, target) in [("x64", "system32"), ("x32", "syswow64")] {
            let folder = source.appendingPathComponent(arch)
            guard fm.fileExists(atPath: folder.path) else { continue }
            for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where ["d3d11.dll", "d3d10core.dll"].contains(file.lastPathComponent) {
                let destination = prefix.appendingPathComponent("drive_c/windows/\(target)/\(file.lastPathComponent)")
                let backup = destination.appendingPathExtension("spicedrum-original")
                // Move Wine's symlink itself; never write through it into the shared runtime.
                if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
                    if (try? fm.attributesOfItem(atPath: backup.path)) == nil { try fm.moveItem(at: destination, to: backup) }
                    else { try fm.removeItem(at: destination) }
                }
                try fm.copyItem(at: file, to: destination)
            }
        }
    }

    public static func installDXMT(from source: URL, into prefix: URL) throws {
        try validateDXMT(source)
        let fm = FileManager.default
        for (arch, target) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
            let sourceDLL = source.appendingPathComponent("\(arch)/winemetal.dll")
            let destination = prefix.appendingPathComponent("drive_c/windows/\(target)/winemetal.dll")
            let backup = destination.appendingPathExtension("spicedrum-original")
            if fm.isReadableFile(atPath: sourceDLL.path) {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
                    if (try? fm.attributesOfItem(atPath: backup.path)) == nil { try fm.moveItem(at: destination, to: backup) }
                    else { try fm.removeItem(at: destination) }
                }
                try fm.copyItem(at: sourceDLL, to: destination)
            } else if (try? fm.attributesOfItem(atPath: backup.path)) != nil {
                if (try? fm.attributesOfItem(atPath: destination.path)) != nil { try fm.removeItem(at: destination) }
                try fm.moveItem(at: backup, to: destination)
            }
        }
    }
}
