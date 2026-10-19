import Foundation

public enum RuntimeDiscovery {
    /// Finds Apple's installed Game Porting Toolkit Wine runtime without requiring
    /// users to locate its internal wine64 launcher by hand.
    public static func appleGamePortingToolkit(in searchDirectories: [URL]? = nil) -> Runtime? {
        appleGamePortingToolkits(in: searchDirectories).first
    }

    /// Finds every installed Apple GPTK Wine host, newest version first. Keeping
    /// these paired with their evaluation image prevents mixing D3DMetal versions.
    public static func appleGamePortingToolkits(in searchDirectories: [URL]? = nil) -> [Runtime] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = searchDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/opt/game-porting-toolkit", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/opt/game-porting-toolkit", isDirectory: true)
        ]
        var apps: [URL] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            if root.pathExtension == "app" {
                apps.append(root)
            } else if let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
                apps.append(contentsOf: children.filter {
                    $0.pathExtension == "app" && $0.lastPathComponent.localizedCaseInsensitiveContains("Game Porting Toolkit")
                })
            }
        }

        let rankedApps = Array(Set(apps.map { $0.standardizedFileURL }))
            .sorted {
                let left = bundleVersion(in: $0)
                let right = bundleVersion(in: $1)
                if left != right { return GPTKInstaller.isNewerVersion(left, than: right) }
                return $0.path.localizedStandardCompare($1.path) == .orderedDescending
            }

        var runtimes = rankedApps.compactMap { app in
            runtime(at: app.appendingPathComponent("Contents/Resources/wine", isDirectory: true), version: bundleVersion(in: app))
        }
        runtimes.append(contentsOf: roots.filter { $0.pathExtension != "app" }.compactMap { runtime(at: $0, version: "") })
        var seen = Set<String>()
        return runtimes.filter { seen.insert($0.executable.standardizedFileURL.path).inserted }
    }

    private static func runtime(at wineRoot: URL, version: String) -> Runtime? {
        let fm = FileManager.default
        let launchers = [wineRoot.appendingPathComponent("bin/wine64"), wineRoot.appendingPathComponent("bin/wine")]
        guard let launcher = launchers.first(where: { fm.isExecutableFile(atPath: $0.path) }) else { return nil }
        let metal = [
            wineRoot.appendingPathComponent("lib/external/D3DMetal.framework", isDirectory: true),
            wineRoot.appendingPathComponent("lib/D3DMetal.framework", isDirectory: true)
        ].contains { fm.fileExists(atPath: $0.appendingPathComponent("Versions/Current/D3DMetal").path)
            || fm.fileExists(atPath: $0.appendingPathComponent("D3DMetal").path) }
        guard metal,
              fm.isExecutableFile(atPath: launcher.deletingLastPathComponent().appendingPathComponent("wineserver").path) else { return nil }
        return Runtime(name: "Apple Game Porting Toolkit", executable: launcher, useRosetta: true, d3dMetal: true, version: version)
    }

    private static func bundleVersion(in app: URL) -> String {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return "" }
        return (values["CFBundleShortVersionString"] as? String)
            ?? (values["CFBundleVersion"] as? String)
            ?? ""
    }
}

public enum RuntimeSource: String, CaseIterable, Identifiable {
    case sikarugir = "Sikarugir / Kegworks"
    case gptk = "Apple Game Porting Toolkit"
    case staging = "Wine Staging for macOS"
    case stable = "Wine Stable / Devel for macOS"
    case whisky = "Whisky community Wine"
    case custom = "Custom macOS Wine build"
    public var id: String { rawValue }
    public var url: URL {
        let address: String
        switch self {
        case .sikarugir: address = "https://github.com/Sikarugir-App/Engines/releases"
        case .gptk: address = "https://developer.apple.com/games/game-porting-toolkit/"
        case .staging, .stable, .custom: address = "https://github.com/Gcenx/macOS_Wine_builds/releases"
        case .whisky: address = "https://github.com/frankea/Whisky/releases"
        }
        return URL(string: address)!
    }
    public var status: String {
        switch self {
        case .sikarugir: return "macOS engine family"
        case .gptk: return "Apple evaluation tools"
        case .staging: return "Additional compatibility patches"
        case .stable: return "Upstream macOS builds"
        case .whisky: return "Community-maintained Wine runtime"
        case .custom: return "Bring your own runtime"
        }
    }
    public var guidance: String {
        switch self {
        case .sikarugir:
            return "Successor to Wineskin/Kegworks, with macOS-specific engines. Use Download engine for automatic runtime-library setup and an x64 startup test. Advanced imports must already include the wrapper's required libraries. Wine 11 requires the publisher's launcher and is not supported here yet. Optional wrapper renderers are not enabled automatically. Older GPTK and Whisky engines are listed as unsupported by the publisher."
        case .gptk:
            return "Spiced-Rum detects Apple's installed Wine host and automatically looks for a downloaded evaluation-environment disk image. It mounts the image read-only, creates a separate GPTK runtime with the matching D3DMetal libraries, and verifies Windows x64 startup without changing Apple's app. GPTK 4 requires macOS 15 or later; Apple's included license applies."
        case .staging:
            return "Gcenx's macOS WineHQ packages include Wine Staging, with patches beyond stable Wine. Select wine inside the extracted Wine Staging.app bundle. These packages include MoltenVK; DXVK is selected separately per shotglass."
        case .stable:
            return "Gcenx packages Wine Stable and Devel for macOS with their dependencies. Keep the app bundle intact and choose its wine executable. Useful for comparing regressions against other engines."
        case .whisky:
            return "Download versioned Wine Libraries from the active Whisky community fork using Download engine. Releases refresh from GitHub and install side by side, so you can choose older or newer builds per shotglass. GPTK-capable builds automatically receive the newest available Apple evaluation payload during installation; a downloaded evaluation image or previously installed GPTK runtime must be available. Review each release's notes for known issues before switching a shotglass."
        case .custom:
            return "Choose wine, wine64, or a prepared launcher script from a complete macOS runtime. Linux Proton/GE-Proton binaries are not macOS runtimes. The runtime is tested with --version before registration; game compatibility still needs testing."
        }
    }
}
