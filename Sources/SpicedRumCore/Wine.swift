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
        for key in ["WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINESERVER", "WINELOADER", "WINEDLLPATH_PREPEND", "WINEMSYNC", "DXVK_CONFIG_FILE", "DXVK_LOG_PATH"] { env.removeValue(forKey: key) }
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
        let process = Process()
        let (binary, args) = command(runtime: runtime, arguments: ["--version"])
        process.executableURL = binary; process.arguments = args
        process.environment = ["PATH": runtime.executable.deletingLastPathComponent().path + ":/usr/bin:/bin", "HOME": NSHomeDirectory(), "WINEPREFIX": folder.appendingPathComponent("prefix").path]
        let log = folder.appendingPathComponent("probe.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        process.standardOutput = output; process.standardError = output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { if process.isRunning { process.terminate() } }
        }
        let version = (try String(contentsOf: log, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0, version.lowercased().contains("wine"), version.count < 2000 else {
            throw RumError.message("Wine did not report a valid version. Check that this is a complete macOS runtime and that Rosetta is installed for Intel runtimes.\n\(String(version.prefix(500)))")
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
        // Renderer DLLs are installed only after Wine creates its original prefix.
        var plain = entry; plain.shotglass.graphics = .wine
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
