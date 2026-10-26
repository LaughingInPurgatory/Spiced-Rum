import SwiftUI
import SpicedRumCore

struct GraphicsOptionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let entry: ShotglassEntry

    @State private var graphics: Graphics = .wine
    @State private var direct3D9: Direct3D9Backend = .wine
    @State private var vulkan: VulkanBackend = .runtimeDefault
    @State private var openGL: OpenGLBackend = .wine

    private var currentEntry: ShotglassEntry { store.entries.first(where: { $0.id == entry.id }) ?? entry }
    private var runtime: Runtime { currentEntry.shotglass.runtime }

    private var dxvkPackage: URL? {
        let packages = store.installedDXVKPackages()
        if let selected = currentEntry.dxvkPackage,
           let installed = packages.first(where: { $0.folder.standardizedFileURL == selected.standardizedFileURL }) {
            return installed.folder
        }
        return packages.first?.folder
    }
    private var mtld3dPackage: URL? { package(.mtld3d, currentEntry.mtld3dPackage) }
    private var zinkPackage: URL? { package(.zink, currentEntry.zinkPackage) }
    private var mtld3dAvailable: Bool { ShotglassGraphics.canUse(.mtld3d, package: mtld3dPackage, runtime: runtime) }
    private var zinkAvailable: Bool { ShotglassGraphics.canUse(.zink, package: zinkPackage, runtime: runtime) }
    private var graphicsChoices: [Graphics] {
        ShotglassGraphics.choices(for: currentEntry).filter {
            $0 != .dxvk || dxvkPackage != nil
        }
    }
    private var mtld3dConflict: ShotglassEntry? {
        guard direct3D9 == .mtld3d, let mtld3dPackage else { return nil }
        return store.entries.first {
            $0.id != currentEntry.id && $0.shotglass.runtime.id == runtime.id
                && $0.shotglass.direct3D9 == .mtld3d
                && $0.mtld3dPackage?.standardizedFileURL != mtld3dPackage.standardizedFileURL
        }
    }
    private var validationMessage: String? {
        if let mtld3dConflict {
            return "\(mtld3dConflict.shotglass.name) uses a different mtld3d Wine bridge with this shared engine. Change it to Wine default first."
        }
        do {
            try ShotglassGraphics.validateSettings(
                currentEntry, graphics: graphics, dxvkPackage: dxvkPackage,
                direct3D9: direct3D9, direct3D9Package: direct3D9 == .mtld3d ? mtld3dPackage : nil,
                direct3D12: .wine, direct3D12Package: nil, dxgiPackage: nil,
                vulkan: vulkan, openGL: openGL, openGLPackage: openGL == .zink ? zinkPackage : nil
            )
            return nil
        } catch { return error.localizedDescription }
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Graphics · \(currentEntry.shotglass.name)").font(.title2.weight(.semibold))
            Text("Choose the renderer and which backend this shotglass uses for each Windows graphics API. Download, assign, and remove engine or graphics versions in Settings. Spiced-Rum checks engine support and blocks incompatible combinations.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            GroupBox("Direct3D 10/11 renderer") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Renderer", selection: $graphics) {
                        ForEach(Graphics.allCases) { option in
                            Text(option.rawValue).tag(option).disabled(!graphicsChoices.contains(option))
                        }
                    }
                    Text(graphics == .dxvk && dxvkPackage == nil
                         ? "Install and assign a macOS DXVK version in Settings before enabling it."
                         : "The renderer is used by games that rely on Direct3D 10 or 11.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }

            GroupBox("Direct3D 9") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Backend", selection: $direct3D9) {
                        Text(Direct3D9Backend.wine.rawValue).tag(Direct3D9Backend.wine)
                        Text(Direct3D9Backend.mtld3d.rawValue).tag(Direct3D9Backend.mtld3d).disabled(!mtld3dAvailable)
                    }
                    Text(mtld3dAvailable
                         ? "mtld3d translates Direct3D 9 to Metal."
                         : "mtld3d is available after a compatible version is installed in Settings and this engine supports its Wine libraries.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }

            GroupBox("Direct3D 12") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wine default", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    if currentEntry.shotglass.direct3D12 == .vkd3dProton {
                        Text("VKD3D-Proton is no longer supported. Save to remove its DLL overrides and use Wine default. Saving stops this shotglass's Windows processes.")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("Vulkan") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Driver", selection: $vulkan) {
                        ForEach(VulkanBackend.allCases) { backend in
                            Text(backend.rawValue).tag(backend)
                                .disabled(!ShotglassGraphics.canUse(backend, runtime: runtime))
                        }
                    }
                    Text("Runtime default uses MoltenVK when available. Choose MoltenVK to set it explicitly for this shotglass.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }

            GroupBox("OpenGL") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Backend", selection: $openGL) {
                        Text(OpenGLBackend.wine.rawValue).tag(OpenGLBackend.wine)
                        Text(OpenGLBackend.zink.rawValue).tag(OpenGLBackend.zink).disabled(!zinkAvailable)
                    }
                    Text(zinkAvailable
                         ? "Zink runs OpenGL over this engine's Vulkan driver."
                         : "Install Mesa Zink in Settings and use an engine with a supported Vulkan driver.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }

            VStack(alignment: .trailing, spacing: 8) {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save graphics options") {
                        store.changeGraphicsSettings(
                            currentEntry, graphics: graphics, dxvkPackage: dxvkPackage,
                            direct3D9: direct3D9,
                            direct3D9Package: direct3D9 == .mtld3d ? mtld3dPackage : nil,
                            direct3D12: .wine, direct3D12Package: nil, dxgiPackage: nil,
                            vulkan: vulkan, openGL: openGL,
                            openGLPackage: openGL == .zink ? zinkPackage : nil
                        )
                        dismiss()
                    }.buttonStyle(PrimaryButtonStyle())
                        .disabled(store.busy.contains(entry.id) || store.setupBusy || validationMessage != nil)
                }
            }
        }
        .padding(26)
        .onAppear {
            graphics = currentEntry.shotglass.graphics
            direct3D9 = currentEntry.shotglass.direct3D9 ?? .wine
            let savedVulkan = currentEntry.shotglass.vulkan ?? .runtimeDefault
            vulkan = savedVulkan == .legacyKosmicKrisp
                ? (ShotglassGraphics.canUse(.moltenVK, runtime: runtime) ? .moltenVK : .runtimeDefault)
                : savedVulkan
            openGL = currentEntry.shotglass.openGL ?? .wine
        }
        }.frame(width: 650, height: 760)
    }

    private func package(_ source: GraphicsRuntimeSource, _ selected: URL?) -> URL? {
        let packages = store.installedGraphicsRuntimePackages(source)
        if let selected,
           let installed = packages.first(where: { $0.folder.standardizedFileURL == selected.standardizedFileURL }) {
            return installed.folder
        }
        return packages.first?.folder
    }
}

struct GraphicsRuntimeVersionView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let source: GraphicsRuntimeSource

    @State private var assets: [EngineAsset] = []
    @State private var installed: [GraphicsRuntimePackage] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""
    @State private var nextPage: Int?
    @State private var uncheckedAsset: EngineAsset?
    @State private var packagePendingRemoval: GraphicsRuntimePackage?
    @State private var generation = UUID()

    private var filteredAssets: [EngineAsset] {
        assets.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || ($0.releaseTag?.localizedCaseInsensitiveContains(filter) ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("\(source.title) versions").font(.title2.weight(.semibold))
            Text("Download, assign, and remove versions here. Assigning one also enables that backend when the shotglass engine supports it. The shotglass Graphics panel chooses which renderer and API backend to use.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(source.description).font(.caption).foregroundStyle(.secondary)
            Link("Official release source ↗", destination: URL(string: "https://github.com/\(source.repository)/releases")!)

            if !installed.isEmpty {
                Text("Installed versions").font(.headline)
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(installed) { package in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(package.title).fontWeight(.medium)
                                    let users = store.entries.filter { uses(package, in: $0) }.map { $0.shotglass.name }
                                    Text(users.isEmpty ? "Not assigned to a shotglass" : "Used by \(users.joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if !store.entries.isEmpty {
                                    Menu("Assign to shotglass") {
                                        ForEach(store.entries) { entry in
                                            Button(entry.shotglass.name) { store.selectGraphicsRuntime(package, for: entry) }
                                                .disabled(uses(package, in: entry) || store.setupBusy)
                                        }
                                    }.disabled(store.setupBusy)
                                }
                                Button(role: .destructive) { packagePendingRemoval = package } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .help(store.entries.contains(where: { uses(package, in: $0) })
                                      ? "Change the shotglass graphics selection before removing this version."
                                      : "Remove this installed version.")
                                .disabled(store.setupBusy || store.entries.contains(where: { uses(package, in: $0) }))
                            }.padding(9).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxHeight: 170)
            }

            Text("Available downloads").font(.headline)
            TextField("Filter releases", text: $filter).textFieldStyle(.roundedBorder)
            if loading && assets.isEmpty { ProgressView("Checking publisher releases…").frame(maxWidth: .infinity, minHeight: 80) }
            else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filteredAssets) { asset in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.releaseTag ?? asset.name).fontWeight(.medium).lineLimit(2)
                                    Text("\(asset.name) · \(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)) · \(asset.verifiedDownload ? "publisher SHA-256" : "no publisher checksum")")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if let package = installed.first(where: { $0.releaseTag == asset.releaseTag && asset.releaseTag != nil }) {
                                    Text(package.title).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Button(asset.verifiedDownload ? "Download" : "Install legacy release…") {
                                        if asset.verifiedDownload { store.installGraphicsRuntime(asset, source: source) }
                                        else { uncheckedAsset = asset }
                                    }.disabled(store.setupBusy)
                                }
                            }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if loading { ProgressView("Loading older releases…") }
                        if nextPage != nil { Button("Load older releases") { Task { await load(reset: false) } }.disabled(loading || store.setupBusy) }
                    }
                }.frame(height: 210)
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
        }.padding(26).frame(width: 700)
            .task { installed = store.installedGraphicsRuntimePackages(source); await load() }
            .onChange(of: store.setupBusy) { wasBusy, isBusy in
                if wasBusy && !isBusy { installed = store.installedGraphicsRuntimePackages(source) }
            }
            .onChange(of: store.entries.map(\.shotglass.id)) { _, _ in
                installed = store.installedGraphicsRuntimePackages(source)
            }
            .interactiveDismissDisabled(store.setupBusy)
            .confirmationDialog("Install a release without a publisher checksum?", isPresented: Binding(get: { uncheckedAsset != nil }, set: { if !$0 { uncheckedAsset = nil } }), titleVisibility: .visible) {
                if let asset = uncheckedAsset {
                    Button("Install from publisher") { store.installGraphicsRuntime(asset, source: source, allowUnverified: true); uncheckedAsset = nil }
                }
                Button("Cancel", role: .cancel) { uncheckedAsset = nil }
            } message: {
                Text("This archive is from the publisher's HTTPS release page, but has no publisher checksum. Spiced-Rum can record its local checksum and validate the package layout, but cannot verify the download against a publisher checksum.")
            }
            .confirmationDialog("Remove this graphics version?", isPresented: Binding(get: { packagePendingRemoval != nil }, set: { if !$0 { packagePendingRemoval = nil } }), titleVisibility: .visible) {
                if let package = packagePendingRemoval {
                    Button("Remove version", role: .destructive) {
                        if store.removeGraphicsRuntimePackage(package) {
                            installed = store.installedGraphicsRuntimePackages(source)
                        }
                        packagePendingRemoval = nil
                    }
                }
                Button("Cancel", role: .cancel) { packagePendingRemoval = nil }
            } message: {
                Text("Spiced-Rum will remove only this downloaded version. Shotglass and engine files remain in place. Versions selected by a shotglass or saved in an engine backup cannot be deleted.")
            }
    }

    private func uses(_ package: GraphicsRuntimePackage, in entry: ShotglassEntry) -> Bool {
        let selected: URL?
        switch source {
        case .mtld3d: selected = entry.mtld3dPackage
        case .vkd3dProton: selected = entry.vkd3dProtonPackage
        case .dxgi: selected = entry.dxgiPackage
        case .zink: selected = entry.zinkPackage
        }
        return selected?.standardizedFileURL == package.folder.standardizedFileURL
    }

    private func load(reset: Bool = true) async {
        let page = reset ? 1 : (nextPage ?? 1)
        if reset { generation = UUID(); assets = []; nextPage = nil }
        let requestedGeneration = generation
        loading = true; error = nil
        do {
            let result = try await EngineInstaller.graphicsRuntimeReleases(source, page: page)
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            var seen = Set(assets.map(\.id))
            assets.append(contentsOf: result.assets.filter { seen.insert($0.id).inserted })
            nextPage = result.nextPage
        } catch {
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
