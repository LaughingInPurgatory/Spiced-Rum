import SwiftUI
import AppKit
import SpicedRumCore

struct EngineDownloadView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var feed: EngineFeed = .wineHQ
    @State private var assets: [EngineAsset] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""
    @State private var nextPage: Int?
    @State private var legacyAsset: EngineAsset?
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Download an engine").font(.title2.weight(.semibold))
            Text("Start with Wine Staging for most games. Spiced-Rum downloads the complete macOS engine, sets up available graphics components, and tests a Windows x64 environment before adding it.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Publisher", selection: $feed) { ForEach(EngineFeed.allCases) { Text($0.rawValue).tag($0) } }.disabled(store.setupBusy)
            if feed == .whisky {
                Text("This downloads the Wine Libraries runtime from the active Whisky community fork, not the Whisky app. Releases refresh from GitHub and install side by side. GPTK-capable releases need Apple's evaluation payload; Spiced-Rum finds and mounts its downloaded disk image or reuses an already installed GPTK payload, then keeps Apple's license files with the engine. These runtimes require macOS 15 or later.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15 {
                    Text("This Mac is running an older macOS version; Whisky community runtimes cannot be installed here.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if feed == .sikarugir {
                Text("Spiced-Rum automatically prepares support libraries for standalone-compatible builds. Wine 11 requires Sikarugir's own launcher and is currently unavailable here. Supported builds start with Wine default graphics; optional wrapper renderers are not enabled. Newest uploads appear first.").font(.caption).foregroundStyle(.secondary)
            }
            if feed == .barrelWine {
                Text("Barrel Wine is built from CrossOver Wine sources for Apple Silicon and macOS 14+. Spiced-Rum installs its matching macOS support libraries and the latest official DXMT builtin automatically. You can keep older and newer DXMT versions side by side and switch them in Runtimes & setup.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Filter versions or engine names", text: $filter).textFieldStyle(.roundedBorder)
            if loading && assets.isEmpty { ProgressView("Checking publisher releases…").frame(maxWidth: .infinity, minHeight: 100) }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(assets.filter {
                            filter.isEmpty
                                || $0.name.localizedCaseInsensitiveContains(filter)
                                || $0.displayName(in: feed).localizedCaseInsensitiveContains(filter)
                                || ($0.releaseTag?.localizedCaseInsensitiveContains(filter) ?? false)
                        }) { asset in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(asset.displayName(in: feed)).fontWeight(.medium).lineLimit(2)
                                    if feed == .whisky, let tag = asset.releaseTag { Text("Runtime release \(tag) · \(asset.name)").font(.caption).foregroundStyle(.secondary) }
                                    if feed == .barrelWine, let tag = asset.releaseTag { Text("Wine build \(tag) · support libraries and latest DXMT set up automatically").font(.caption).foregroundStyle(.secondary) }
                                    if asset.id == assets.first(where: { $0.name.contains("wine-staging") && $0.verifiedDownload })?.id { Text("Recommended starting point").font(.caption).foregroundStyle(.orange) }
                                    if asset.requiresSikarugirLauncher { Text("Requires Sikarugir's launcher · not yet supported").font(.caption).foregroundStyle(.orange) }
                                    if asset.requiresAppleGPTKPayload { Text("GPTK-capable · Apple's evaluation payload is attached automatically during install").font(.caption).foregroundStyle(.orange) }
                                    if asset.reportsSteamLoginIssue { Text("Preview caveat: this release reports that Steam login can stall. Keep another engine for Steam.").font(.caption).foregroundStyle(.orange) }
                                    Text("\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)) · \(asset.verifiedDownload ? "SHA-256 verified download" : "Publisher checksum unavailable")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(asset.verifiedDownload ? "Install & set up" : "Install legacy download…") {
                                    if asset.verifiedDownload { store.installEngine(asset, feed: feed) }
                                    else { legacyAsset = asset }
                                }.disabled(store.setupBusy || asset.requiresSikarugirLauncher || (feed == .whisky && ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15))
                            }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        }
                        if loading { ProgressView("Loading older releases…") }
                        if nextPage != nil {
                            Button("Load older releases") { Task { await load(reset: false) } }.disabled(loading || store.setupBusy)
                        } else if !loading { Text("End of the publisher's available release history.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(height: 280)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Retry loading releases") { Task { await load(reset: assets.isEmpty) } }.disabled(loading)
            }
            if !store.setupMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.setupMessage).font(.callout)
                    if store.setupBusy { if let progress = store.setupProgress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) } }
                }
            }
            if !store.setupBusy, let error = store.error { ScrollView { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }.frame(maxHeight: 100) }
            Text("Older and newer engines install side by side. Existing shotglasses keep their engine until you choose Change engine. Spiced-Rum attaches the newest available Apple GPTK payload when installing a GPTK-capable Whisky release.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Refresh newest releases") { Task { await load() } }.disabled(loading || store.setupBusy)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.setupBusy)
            }
        }.padding(28).frame(width: 680)
        .task(id: feed) { await load() }
        .interactiveDismissDisabled(store.setupBusy)
        .confirmationDialog("Install a release without a publisher checksum?", isPresented: Binding(get: { legacyAsset != nil }, set: { if !$0 { legacyAsset = nil } }), titleVisibility: .visible) {
            if let asset = legacyAsset { Button("Install from publisher") { store.installEngine(asset, feed: feed, allowUnverified: true); legacyAsset = nil } }
            Button("Cancel", role: .cancel) { legacyAsset = nil }
        } message: {
            Text("This older download comes from the selected publisher's HTTPS release page, but has no published SHA-256 checksum. Spiced-Rum can record its checksum and test Windows startup, but cannot verify it against a publisher checksum. Install only if you trust this release.")
        }
    }

    func load(reset: Bool = true) async {
        let requestedFeed = feed
        let page = reset ? 1 : (nextPage ?? 1)
        if reset { generation = UUID(); assets = []; nextPage = nil }
        let requestGeneration = generation
        loading = true; error = nil
        do {
            let result = try await EngineInstaller.releases(requestedFeed, page: page)
            guard requestedFeed == feed, generation == requestGeneration, !Task.isCancelled else { return }
            var seen = Set(assets.map(\.id))
            assets.append(contentsOf: result.assets.filter { seen.insert($0.id).inserted })
            nextPage = result.nextPage
        }
        catch { guard requestedFeed == feed, generation == requestGeneration, !Task.isCancelled else { return }; self.error = error.localizedDescription }
        loading = false
    }
}

struct RosettaSetupView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var agreed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up Rosetta 2").font(.title2.weight(.semibold))
            Text("The downloadable Wine engines contain Intel code. Apple's Rosetta 2 translates that code for your Apple Silicon Mac. Spiced-Rum will use Apple's software updater to install it.")
            Text("Apple requires acceptance of its license. Review the terms before continuing. The installer may require administrator authorization or an internet connection.").foregroundStyle(.secondary)
            Link("Apple software license agreements ↗", destination: URL(string: "https://www.apple.com/legal/sla/")!)
            Link("Apple's Rosetta installation guide ↗", destination: URL(string: "https://support.apple.com/en-us/102527")!)
            Toggle("I have reviewed and agree to Apple's Rosetta 2 license terms", isOn: $agreed)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Install Rosetta 2") { store.installRosetta(); dismiss() }.buttonStyle(PrimaryButtonStyle()).disabled(!agreed || store.setupBusy)
            }
        }.padding(28).frame(width: 560)
    }
}

struct DependencyView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let entry: ShotglassEntry
    @State private var dependencies = Dependencies.recommended
    @State private var selectedID = "vcrun2022"
    @State private var filter = ""
    @State private var listError: String?

    private var filteredDependencies: [WindowsDependency] {
        dependencies.filter {
            filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter)
                || $0.rawValue.localizedCaseInsensitiveContains(filter)
                || $0.category.localizedCaseInsensitiveContains(filter)
        }
    }

    private var filteredCategories: [String] { Array(Set(filteredDependencies.map(\.category))).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Winetricks components and tweaks").font(.title2.weight(.semibold))
            Text("Selected items install only into “\(entry.shotglass.name)”. Close its running Windows apps first. Start with Visual C++ 2015–2022 when a game reports missing VCRUNTIME or MSVCP files.")
                .foregroundStyle(.secondary)
            TextField("Search Winetricks verbs", text: $filter).textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    Section(category.replacingOccurrences(of: "_", with: " ").capitalized) {
                        ForEach(filteredDependencies.filter { $0.category == category }) { item in
                            Button { selectedID = item.id } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).lineLimit(2)
                                        Text(item.rawValue).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    if selectedID == item.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.listStyle(.inset).frame(height: 245)
            if let listError { Text(listError).font(.caption).foregroundStyle(.orange) }
            Text("Winetricks lists applications, benchmarks, DLLs, fonts and settings supported by the installed version. Some entries run installers or change Windows settings; choose the item your app asks for. The shader compiler can fix D3DCOMPILER_47 errors, DirectX 9 helpers provide D3DX9 libraries, and .NET 4.8 is only for apps that require it. Avoid installing multiple Visual C++ versions in one shotglass.").font(.caption).foregroundStyle(.secondary)
            if Dependencies.winetricks == nil {
                Text(Dependencies.brew != nil ? "Spiced-Rum will automatically install Winetricks and its extraction tools with Homebrew before installing this component." : "Homebrew is needed to install Winetricks and its extraction tools. Follow its installer once, then return here; Spiced-Rum handles the remaining setup.").font(.callout)
                HStack {
                    Button("Install dependency tools") { store.installDependencyTools() }.disabled(store.setupBusy)
                    if Dependencies.brew == nil { Button("Set up Homebrew…") { store.prepareHomebrew() }.disabled(store.setupBusy) }
                }
                if store.setupBusy { ProgressView(store.setupMessage) }
                if store.waitingForHomebrew { Text(store.setupMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Text("Winetricks downloads installers from their upstream sources and verifies its recipe checksums. Complete any license or setup dialogs that appear. Installation can take several minutes; details are written to the shotglass's log.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install selected item") {
                    guard let dependency = dependencies.first(where: { $0.id == selectedID }) else { return }
                    store.installDependency(dependency, entry: entry); dismiss()
                }.buttonStyle(PrimaryButtonStyle())
                    .disabled((Dependencies.winetricks == nil && Dependencies.brew == nil) || store.busy.contains(entry.id) || store.setupBusy)
            }
        }.padding(28).frame(width: 600)
        .task(id: Dependencies.winetricks?.path) { await loadDependencies() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.resumeSetup() }
    }

    private func loadDependencies() async {
        guard Dependencies.winetricks != nil else { return }
        do {
            let values = try await Dependencies.listAll()
            guard !Task.isCancelled else { return }
            dependencies = values
            if !values.contains(where: { $0.id == selectedID }) { selectedID = values.first?.id ?? "" }
            listError = nil
        } catch {
            guard !Task.isCancelled else { return }
            listError = "Could not refresh Winetricks' list. The common components remain available. \(error.localizedDescription)"
        }
    }
}

struct DXVKVersionView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let runtime: Runtime
    @State private var assets: [EngineAsset] = []
    @State private var installed: [DXVKPackage] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""
    @State private var nextPage: Int?
    @State private var uncheckedAsset: EngineAsset?
    @State private var generation = UUID()

    private var currentRuntime: Runtime { store.catalog.runtimes.first(where: { $0.id == runtime.id }) ?? runtime }
    private var currentPackagePath: String? { currentRuntime.dxvkPackage?.standardizedFileURL.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DXVK versions · \(runtime.name)").font(.title2.weight(.semibold))
            Text("Choose a macOS DXVK build for this runtime. Spiced-Rum downloads it from Gcenx’s DXVK-macOS releases, checks the publisher’s SHA-256 when available, and applies it to shotglasses using DXVK with this runtime. Other shotglasses keep their selected renderer. D3DMetal updates with its GPTK engine.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Gcenx DXVK-macOS release source ↗", destination: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases")!)
            if !installed.isEmpty {
                Text("Installed versions").font(.headline)
                ForEach(installed) { package in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(package.title).fontWeight(.medium)
                            if package.folder.standardizedFileURL.path == currentPackagePath { Text("Currently selected").font(.caption).foregroundStyle(.green) }
                        }
                        Spacer()
                        Button(package.folder.standardizedFileURL.path == currentPackagePath ? "Selected" : "Use version") {
                            store.selectDXVK(package, for: currentRuntime)
                        }.disabled(store.setupBusy || package.folder.standardizedFileURL.path == currentPackagePath)
                    }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("Available downloads").font(.headline)
            TextField("Filter DXVK releases", text: $filter).textFieldStyle(.roundedBorder)
            if loading && assets.isEmpty { ProgressView("Checking DXVK releases…").frame(maxWidth: .infinity, minHeight: 90) }
            else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(assets.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || ($0.releaseTag?.localizedCaseInsensitiveContains(filter) ?? false) }) { asset in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.releaseTag ?? asset.name).fontWeight(.medium).lineLimit(2)
                                    Text("\(asset.name) · \(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)) · \(asset.verifiedDownload ? "publisher SHA-256" : "no publisher checksum")")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if let package = installed.first(where: { $0.releaseTag != nil && $0.releaseTag == asset.releaseTag }) {
                                    Button(package.folder.standardizedFileURL.path == currentPackagePath ? "Selected" : "Use installed") {
                                        store.selectDXVK(package, for: currentRuntime)
                                    }.disabled(store.setupBusy || package.folder.standardizedFileURL.path == currentPackagePath)
                                } else {
                                    Button(asset.verifiedDownload ? "Download & apply" : "Install legacy release…") {
                                        if asset.verifiedDownload { store.installDXVK(asset, for: currentRuntime) }
                                        else { uncheckedAsset = asset }
                                    }.disabled(store.setupBusy)
                                }
                            }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if loading { ProgressView("Loading older releases…") }
                        if nextPage != nil { Button("Load older releases") { Task { await load(reset: false) } }.disabled(loading || store.setupBusy) }
                    }
                }.frame(height: 225)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { Task { await load() } }.disabled(loading) }
            if store.setupBusy {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.setupMessage).font(.callout)
                    if let progress = store.setupProgress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
                }
            }
            if !store.setupBusy, let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Refresh releases") { Task { await load() } }.disabled(loading || store.setupBusy)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.setupBusy)
            }
        }.padding(28).frame(width: 700)
            .task { installed = EngineInstaller.installedDXVKPackages(for: currentRuntime); await load() }
            .interactiveDismissDisabled(store.setupBusy)
            .confirmationDialog("Install DXVK without a publisher checksum?", isPresented: Binding(get: { uncheckedAsset != nil }, set: { if !$0 { uncheckedAsset = nil } }), titleVisibility: .visible) {
                if let asset = uncheckedAsset {
                    Button("Install from Gcenx") { store.installDXVK(asset, for: currentRuntime, allowUnverified: true); uncheckedAsset = nil }
                }
                Button("Cancel", role: .cancel) { uncheckedAsset = nil }
            } message: {
                Text("The archive comes from Gcenx’s HTTPS release page, but this release has no publisher checksum. Spiced-Rum can record its local checksum and validate its DLL layout, but cannot authenticate the download against a publisher checksum. Install only if you trust this release.")
            }
    }

    private func load(reset: Bool = true) async {
        let page = reset ? 1 : (nextPage ?? 1)
        if reset { generation = UUID(); assets = []; nextPage = nil }
        let requestGeneration = generation
        loading = true; error = nil
        do {
            let result = try await EngineInstaller.dxvkReleases(page: page)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            var seen = Set(assets.map(\.id))
            assets.append(contentsOf: result.assets.filter { seen.insert($0.id).inserted })
            nextPage = result.nextPage
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct DXMTVersionView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let runtime: Runtime
    @State private var installed: [DXMTPackage] = []
    @State private var assets: [EngineAsset] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""
    @State private var nextPage: Int?
    @State private var generation = UUID()
    @State private var uncheckedAsset: EngineAsset?

    private var currentRuntime: Runtime { store.catalog.runtimes.first(where: { $0.id == runtime.id }) ?? runtime }
    private var currentPackagePath: String { currentRuntime.dxmtPackage?.standardizedFileURL.path ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DXMT versions · \(runtime.name)").font(.title2.weight(.semibold))
            Text("DXMT translates Direct3D 10/11 to Metal. Spiced-Rum downloads the official Wine builtin release and keeps versions side by side. Changing the selected version updates this engine and its shotglasses, stops any running Wine processes in those shotglasses, and restores Wine's original winemetal.dll when you switch away from DXMT.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Official 3Shain DXMT releases ↗", destination: URL(string: "https://github.com/3Shain/dxmt/releases")!)
            if !installed.isEmpty {
                Text("Installed versions").font(.headline)
                ForEach(installed) { package in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(package.title).fontWeight(.medium)
                            if package.folder.standardizedFileURL.path == currentPackagePath { Text("Currently selected").font(.caption).foregroundStyle(.green) }
                        }
                        Spacer()
                        Button(package.folder.standardizedFileURL.path == currentPackagePath ? "Selected" : "Use version") {
                            store.selectDXMT(package, for: currentRuntime)
                        }.disabled(store.setupBusy || package.folder.standardizedFileURL.path == currentPackagePath)
                    }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("Available downloads").font(.headline)
            TextField("Filter DXMT releases", text: $filter).textFieldStyle(.roundedBorder)
            if loading && assets.isEmpty { ProgressView("Checking official DXMT releases…").frame(maxWidth: .infinity, minHeight: 90) }
            else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(assets.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || ($0.releaseTag?.localizedCaseInsensitiveContains(filter) ?? false) }) { asset in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.releaseTag ?? asset.name).fontWeight(.medium).lineLimit(2)
                                    Text("\(asset.name) · \(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)) · \(asset.verifiedDownload ? "publisher SHA-256" : "no publisher checksum")")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if let package = installed.first(where: { $0.releaseTag != nil && $0.releaseTag == asset.releaseTag }) {
                                    Button(package.folder.standardizedFileURL.path == currentPackagePath ? "Selected" : "Use installed") {
                                        store.selectDXMT(package, for: currentRuntime)
                                    }.disabled(store.setupBusy || package.folder.standardizedFileURL.path == currentPackagePath)
                                } else {
                                    Button(asset.verifiedDownload ? "Download & apply" : "Install legacy release…") {
                                        if asset.verifiedDownload { store.installDXMT(asset, for: currentRuntime) }
                                        else { uncheckedAsset = asset }
                                    }.disabled(store.setupBusy)
                                }
                            }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if loading { ProgressView("Loading older releases…") }
                        if nextPage != nil { Button("Load older releases") { Task { await load(reset: false) } }.disabled(loading || store.setupBusy) }
                    }
                }.frame(height: 225)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { Task { await load() } }.disabled(loading) }
            if store.setupBusy {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.setupMessage).font(.callout)
                    if let progress = store.setupProgress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
                }
            }
            if !store.setupBusy, let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Refresh releases") { Task { await load() } }.disabled(loading || store.setupBusy)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.setupBusy)
            }
        }.padding(28).frame(width: 700)
            .task { installed = EngineInstaller.installedDXMTPackages(for: currentRuntime); await load() }
            .onChange(of: store.setupBusy) { _, busy in
                if !busy { installed = EngineInstaller.installedDXMTPackages(for: currentRuntime) }
            }
            .interactiveDismissDisabled(store.setupBusy)
            .confirmationDialog("Install DXMT without a publisher checksum?", isPresented: Binding(get: { uncheckedAsset != nil }, set: { if !$0 { uncheckedAsset = nil } }), titleVisibility: .visible) {
                if let asset = uncheckedAsset {
                    Button("Install from 3Shain") { store.installDXMT(asset, for: currentRuntime, allowUnverified: true); uncheckedAsset = nil }
                }
                Button("Cancel", role: .cancel) { uncheckedAsset = nil }
            } message: {
                Text("This archive comes from 3Shain's HTTPS release page, but has no publisher checksum. Spiced-Rum records its local checksum and validates the Wine builtin layout, but cannot authenticate the archive against a publisher checksum. Install only if you trust this release.")
            }
    }

    private func load(reset: Bool = true) async {
        let page = reset ? 1 : (nextPage ?? 1)
        if reset { generation = UUID(); assets = []; nextPage = nil }
        let requestGeneration = generation
        loading = true; error = nil
        do {
            let result = try await EngineInstaller.dxmtReleases(page: page)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            var seen = Set(assets.map(\.id))
            assets.append(contentsOf: result.assets.filter { seen.insert($0.id).inserted })
            nextPage = result.nextPage
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
