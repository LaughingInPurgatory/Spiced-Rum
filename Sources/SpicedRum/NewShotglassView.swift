import SwiftUI
import SpicedRumCore

struct NewShotglassView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var runtimeID: UUID?
    @State private var graphics: Graphics = .wine
    @State private var location: URL?
    @State private var dxvk: URL?
    @State private var dxvkPackages: [DXVKPackage] = []
    @State private var error: String?
    @State private var addRuntime = false
    @State private var downloadEngine = false
    @State private var manageDXVKVersions = false
    var runtime: Runtime? { store.catalog.runtimes.first { $0.id == runtimeID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                ShotglassMark().frame(width: 34, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A fresh shotglass").font(.title2.weight(.semibold))
                    Text("One Windows x64 environment. Your choice of home.").foregroundStyle(.secondary)
                }
            }
            TextField("Shotglass name, e.g. Steam or My Games", text: $name).textFieldStyle(.roundedBorder)
            if store.catalog.runtimes.isEmpty {
                Text("Download a gaming engine first. Spiced-Rum will install its files and configure its graphics components for you.").foregroundStyle(.secondary)
            } else {
                Picker("Runtime", selection: $runtimeID) {
                    ForEach(store.catalog.runtimes) { runtime in Text(runtime.name).tag(Optional(runtime.id)) }
                }
            }
            HStack {
                Button("Download an engine…") { downloadEngine = true }
                Button("Advanced import…") { addRuntime = true }
            }
            Picker("Graphics", selection: $graphics) {
                Text("Runtime default").tag(Graphics.wine)
                if let runtime, EngineInstaller.supportsMacOSDXVK(runtime) || runtime.dxvkPackage != nil {
                    Text("DXVK → MoltenVK → Metal").tag(Graphics.dxvk)
                }
                if runtime?.d3dMetal == true { Text("D3DMetal → Metal (DirectX 11/12)").tag(Graphics.metal) }
                if runtime?.dxmt == true { Text("DXMT → Metal (DirectX 10/11)").tag(Graphics.dxmt) }
            }
            if graphics == .dxvk {
                Text("Choose a macOS-compatible DXVK version for this shotglass. Its choice stays independent from other shotglasses using the same engine.").font(.caption).foregroundStyle(.secondary)
                if !dxvkPackages.isEmpty {
                    Picker("DXVK version", selection: $dxvk) {
                        ForEach(dxvkPackages) { package in Text(package.title).tag(Optional(package.folder)) }
                    }
                }
                HStack {
                    Text(dxvk?.lastPathComponent ?? "No DXVK package selected").foregroundStyle(.secondary)
                    Spacer()
                    if runtime.map(EngineInstaller.supportsMacOSDXVK) == true {
                        Button("Manage versions…") { manageDXVKVersions = true }
                    }
                    Button("Choose extracted DXVK…") { if let folder = chooseFolder(prompt: "Use DXVK Package") { dxvk = folder } }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Shotglass location").font(.headline)
                HStack {
                    Text((location ?? store.catalog.defaultLocation).path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button("Choose…") { if let folder = chooseFolder(prompt: "Create Shotglass Here", initial: location ?? store.catalog.defaultLocation) { location = folder } }
                }
                Text("A new .spicedrum folder will hold the Windows drive, settings, shortcuts and logs.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create shotglass") {
                    guard let runtime else { return }
                    do {
                        _ = try store.create(name: name, runtime: runtime, graphics: graphics, parent: location ?? store.catalog.defaultLocation, dxvk: dxvk)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(runtime == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (graphics == .dxvk && dxvk == nil))
            }
        }.padding(30).frame(width: 560)
        .onAppear {
            if let first = store.catalog.runtimes.first {
                runtimeID = first.id
                loadDXVKPackages(for: first, chooseDefault: true)
            }
        }
        .onChange(of: runtimeID) { _, _ in
            graphics = runtime?.defaultGraphics ?? .wine
            if let runtime { loadDXVKPackages(for: runtime, chooseDefault: true) }
        }
        .onChange(of: store.catalog.runtimes.count) { _, _ in if runtimeID == nil { runtimeID = store.catalog.runtimes.last?.id } }
        .sheet(isPresented: $addRuntime) { AddRuntimeView(source: .sikarugir) }
        .sheet(isPresented: $downloadEngine) { EngineDownloadView() }
        .sheet(isPresented: $manageDXVKVersions, onDismiss: {
            if let runtime { loadDXVKPackages(for: runtime, chooseDefault: true) }
        }) {
            DXVKVersionView()
        }
    }

    private func loadDXVKPackages(for runtime: Runtime, chooseDefault: Bool) {
        dxvkPackages = store.installedDXVKPackages()
        guard chooseDefault else { return }
        if let current = dxvkPackages.first(where: { $0.folder.standardizedFileURL == dxvk?.standardizedFileURL }) {
            dxvk = current.folder
        } else if let inherited = runtime.dxvkPackage,
                  (try? Wine.validateDXVK(inherited)) != nil {
            dxvk = inherited
        } else {
            dxvk = dxvkPackages.first?.folder
        }
    }
}
