import Foundation

public enum MediaSupport {
    static let version = "1.28.8"
    static let packageURL = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.8/gstreamer-1.0-1.28.8-universal.pkg")!
    static let digest = "sha256:d371ab04a7632713626836c2fc234e863cc98484c74c473eba99b0fbd9b3a3fe"

    public static func framework(for runtime: Runtime) -> URL? {
        let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        let support = engine.appendingPathComponent("support", isDirectory: true)
        let templates = (try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)) ?? []
        let templateFrameworks = templates.filter { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Template-") }
            .map { $0.appendingPathComponent("Contents/Frameworks/GStreamer.framework") }
        let candidates = [runtime.managedRoot?.appendingPathComponent("media/GStreamer.framework")]
            + templateFrameworks
            + [engine.appendingPathComponent("lib/GStreamer.framework")]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Versions/1.0/lib/libgstreamer-1.0.0.dylib").path)
        }
    }

    static func environment(framework: URL, registry: URL) -> [String: String] {
        let root = framework.appendingPathComponent("Versions/1.0")
        var env: [String: String] = [:]
        for (key, value) in ["GST_PLUGIN_SYSTEM_PATH": root.appendingPathComponent("lib/gstreamer-1.0").path,
                             "GST_PLUGIN_PATH": "",
                             "GST_PLUGIN_SCANNER": root.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path,
                             "GST_REGISTRY": registry.path] {
            env[key] = value; env[key + "_1_0"] = value
        }
        return env
    }

    static func command(_ executable: URL, arguments: [String], libraries: String, rosetta: Bool, fallbackLibraries: String = "/usr/local/lib:/usr/lib") -> (URL, [String]) {
        // System arch and shells strip inherited DYLD variables. Set them in the
        // shell immediately before exec; paths and arguments remain separate values.
        let args = ["-c", "export DYLD_LIBRARY_PATH=\"$1\"; export DYLD_FALLBACK_LIBRARY_PATH=\"$2\"; shift 2; exec \"$@\"", "Spiced-Rum", libraries, fallbackLibraries, executable.path] + arguments
        return rosetta ? (URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/bin/sh"] + args)
                       : (URL(fileURLWithPath: "/bin/sh"), args)
    }

    public static func prepare(_ runtime: Runtime) async throws {
        guard let managed = runtime.managedRoot, framework(for: runtime) == nil else { return }
        let engine = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: engine.appendingPathComponent("lib/wine/x86_64-unix/winegstreamer.so").path) else { return }
        let fm = FileManager.default
        let staging = managed.appendingPathComponent(".media-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let (download, response) = try await URLSession.shared.download(from: packageURL)
        defer { try? fm.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RumError.message("GStreamer video support could not be downloaded. Connect to the internet and retry; Spiced-Rum needs this runtime for H.264 videos in Windows apps.")
        }
        try EngineInstaller.verify(download, digest: digest)
        let archive = staging.appendingPathComponent("gstreamer.pkg")
        try fm.moveItem(at: download, to: archive)
        let expanded = staging.appendingPathComponent("expanded")
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/sbin/pkgutil"), ["--expand-full", archive.path, expanded.path])
        let content = staging.appendingPathComponent("media", isDirectory: true)
        let framework = content.appendingPathComponent("GStreamer.framework")
        try await assemble(from: expanded, framework: framework)
        try await validateH264(framework: framework, log: content.appendingPathComponent("h264-check.log"))
        struct Receipt: Encodable { let version: String; let source: URL; let sha256: String }
        try JSONEncoder().encode(Receipt(version: version, source: packageURL, sha256: digest))
            .write(to: content.appendingPathComponent("download-receipt.json"), options: .atomic)
        let destination = managed.appendingPathComponent("media", isDirectory: true)
        // Concurrent first launches can download twice; atomic publication keeps one complete copy.
        do { try fm.moveItem(at: content, to: destination) }
        catch { if self.framework(for: runtime) == nil { throw error } }
    }

    static func assemble(from expanded: URL, framework: URL) async throws {
        let parts = try FileManager.default.contentsOfDirectory(at: expanded, includingPropertiesForKeys: nil).filter { $0.pathExtension == "pkg" }
        guard let base = parts.first(where: { $0.lastPathComponent.hasPrefix("osx-framework-") }) else {
            throw RumError.message("The GStreamer package has an unexpected layout. Its runtime has not been installed.")
        }
        // Merge the verified package's payloads without running installer scripts or
        // writing to /Library. Preserve the runtime's original notices and resources.
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [base.appendingPathComponent("Payload").path, framework.path])
        let playbackParts: Set<String> = ["base-system-1.0", "base-crypto", "gstreamer-1.0-core", "gstreamer-1.0-system", "gstreamer-1.0-playback", "gstreamer-1.0-codecs", "gstreamer-1.0-codecs-gpl", "gstreamer-1.0-codecs-restricted", "gstreamer-1.0-codecs-gpl-restricted", "gstreamer-1.0-libav", "gstreamer-1.0-net"]
        // Playback needs codecs and system integration, not Python/GTK bindings,
        // editing tools or analytics plugins with separate host dependencies.
        let selected = parts.filter { playbackParts.contains($0.lastPathComponent.replacingOccurrences(of: "-\(version)-universal.pkg", with: "")) }
        guard selected.count == playbackParts.count else { throw RumError.message("The GStreamer package is missing playback components.") }
        for part in selected {
            _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [part.appendingPathComponent("Payload").path, framework.appendingPathComponent("Versions/1.0").path])
        }
        _ = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/ditto"), [expanded.appendingPathComponent("Resources").path, framework.appendingPathComponent("Versions/1.0/share/spiced-rum/installer-resources").path])
    }

    static func validateH264(framework: URL, log: URL) async throws {
        let root = framework.appendingPathComponent("Versions/1.0")
        let (binary, args) = command(root.appendingPathComponent("bin/gst-launch-1.0"), arguments: ["-q", "videotestsrc", "num-buffers=3", "!", "video/x-raw,format=I420,width=64,height=64,framerate=1/1", "!", "x264enc", "!", "h264parse", "!", "avdec_h264", "!", "fakesink"], libraries: root.appendingPathComponent("lib").path, rosetta: true)
        var env = ProcessInfo.processInfo.environment
        env.merge(environment(framework: framework, registry: log.deletingLastPathComponent().appendingPathComponent("registry-x86_64.bin"))) { _, new in new }
        do { try await ProcessRunner.run(binary, args, environment: env, directory: log.deletingLastPathComponent(), log: log, label: "H.264 encode/decode check", timeout: 240) }
        catch { throw RumError.message("GStreamer could not decode the H.264 test video under Rosetta.\n\(error.localizedDescription)\n\(String(((try? String(contentsOf: log)) ?? "").suffix(2000)))") }
    }
}
