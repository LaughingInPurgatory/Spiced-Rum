import SwiftUI
import AppKit
import SpicedRumCore

struct SetupView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var showRuntime = false
    @State private var chosenSource: RuntimeSource = .sikarugir
    @State private var rosetta: Bool?
    @State private var showDownload = false
    @State private var showRosetta = false
    @State private var runtimePendingRemoval: Runtime?
    @State private var runtimeRemovalDescription = ""
    @State private var dxvkRuntime: Runtime?
    @State private var dxmtRuntime: Runtime?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Runtimes & setup").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Choose the engine. Give each game its own shotglass.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Download engine…", systemImage: "arrow.down.circle") { showDownload = true }.buttonStyle(PrimaryButtonStyle()).disabled(!store.storageAvailable || store.setupBusy)
                }
                GroupBox {
                    HStack {
                        Label(rosetta == true ? "Rosetta 2 is available" : rosetta == nil ? "Checking Rosetta 2…" : "Rosetta 2 is required for Intel runtimes", systemImage: rosetta == true ? "checkmark.circle.fill" : "cpu")
                            .foregroundStyle(rosetta == true ? .green : .secondary)
                        Spacer()
                        if rosetta == false { Button("Set up Rosetta…") { showRosetta = true }.disabled(store.setupBusy) }
                        Link("Apple setup instructions", destination: URL(string: "https://support.apple.com/en-us/102527")!)
                    }.padding(8)
                }
                if !store.setupMessage.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.setupMessage)
                            if store.setupBusy { if let progress = store.setupProgress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) } }
                            Button("Show setup log") { NSWorkspace.shared.selectFile(store.setupLog.path, inFileViewerRootedAtPath: store.support.path) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Windows dependency tools").font(.headline)
                        Text(Dependencies.winetricks != nil ? "Winetricks is available. Open a shotglass and choose Install components for Visual C++, DirectX helpers, fonts or .NET." : "Install Winetricks and its extraction tools here. Then install Windows components into individual shotglasses when a game needs them.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(Dependencies.winetricks == nil ? "Install dependency tools" : "Check / install dependency tools") { store.installDependencyTools() }.disabled(store.setupBusy)
                            if Dependencies.brew == nil { Button("Set up Homebrew…") { store.prepareHomebrew() }.disabled(store.setupBusy) }
                        }
                        if Dependencies.brew == nil {
                            Text("Homebrew is a macOS package manager used for Winetricks and extraction tools. Spiced-Rum downloads its official installer; Apple's Installer asks you to approve the system installation. Return here afterward to finish automatically.").font(.caption).foregroundStyle(.secondary)
                            Link("Homebrew installation details ↗", destination: URL(string: "https://docs.brew.sh/Installation")!)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Video playback · H.264").font(.headline)
                        Text("Managed Wine engines download GStreamer and video codecs automatically on first use. This also repairs video support for engines installed earlier. The runtime stays inside the engine folder; no administrator password is needed. Close and relaunch Windows apps afterward.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Set up video playback") { store.prepareVideoSupport() }
                            .disabled(store.setupBusy || !store.catalog.runtimes.contains { $0.managedRoot != nil })
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shotglass location").font(.headline)
                    HStack {
                        Image(systemName: "externaldrive").foregroundStyle(.orange)
                        Text(store.catalog.defaultLocation.path).lineLimit(2).textSelection(.enabled).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            if let folder = chooseFolder(prompt: "Use for New Shotglasses", initial: store.catalog.defaultLocation) { store.setDefaultLocation(folder) }
                        }.disabled(!store.storageAvailable)
                    }
                    Text("Used for new shotglasses. You can choose a different folder for each shotglass, including an external drive.").font(.caption).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Apple Game Porting Toolkit").font(.headline)
                        Text("Spiced-Rum looks for Apple's installed Wine and D3DMetal runtime, then verifies it with a disposable Windows x64 environment. You do not need to browse inside the app bundle.")
                            .font(.callout).foregroundStyle(.secondary)
                        if let runtime = store.detectedGPTK {
                            let path = runtime.executable.resolvingSymlinksInPath().standardizedFileURL.path
                            let baseRegistered = store.catalog.runtimes.contains {
                                $0.executable.resolvingSymlinksInPath().standardizedFileURL.path == path
                            }
                            let betaRegistered = store.gptkBetaVersion.map { version in
                                store.catalog.runtimes.contains { $0.name == "Apple GPTK \(version)" && $0.managedRoot != nil }
                            } ?? false
                            let ready = store.gptkBetaAvailable ? betaRegistered : baseRegistered
                            Label("Found at \(runtime.executable.path)", systemImage: ready ? "checkmark.circle.fill" : "shippingbox")
                                .font(.caption).foregroundStyle(ready ? .green : .secondary).textSelection(.enabled)
                            if store.gptkBetaAvailable {
                                Text("Newest available evaluation image: GPTK \(store.gptkBetaVersion ?? "beta"). Spiced-Rum uses this version, mounts it read-only, and installs its matching libraries into a separate engine. Apple's included license still applies.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Get Apple's latest GPTK and evaluation image. Apple may ask you to sign in; after the download finishes, Spiced-Rum detects the newest image and sets it up automatically.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Link("Download latest GPTK 4 ↗", destination: URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!)
                                Link("Evaluation environment ↗", destination: URL(string: "https://developer.apple.com/download/all/?q=evaluation%20environment%20for%20windows%20games")!)
                            }
                            Button(ready ? (store.gptkBetaAvailable ? "GPTK beta is ready" : "GPTK is ready") : (store.gptkBetaAvailable ? "Install downloaded GPTK beta" : "Set up Apple GPTK")) {
                                store.setUpAppleGPTK(runtime)
                            }
                            .disabled(ready || store.setupBusy || !store.storageAvailable)
                        } else {
                            Text(store.gptkBetaAvailable
                                 ? "The downloaded evaluation image was found, but its matching Apple Wine host app is not installed. Install Game Porting Toolkit, then check again."
                                 : "No installed GPTK Wine runtime was found. Download Apple's latest Game Porting Toolkit and evaluation environment, then return here. Spiced-Rum will choose the newest available image.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Link("Download latest GPTK 4 ↗", destination: URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!)
                                Link("Evaluation environment ↗", destination: URL(string: "https://developer.apple.com/download/all/?q=evaluation%20environment%20for%20windows%20games")!)
                            }
                            Button("Check again") { store.discoverAndSetUpAppleGPTK() }
                                .disabled(store.setupBusy || !store.storageAvailable)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox { graphicsVersionSection.padding(8) }
                Divider()
                Text("Registered runtimes").font(.title3.weight(.semibold))
                if store.catalog.runtimes.isEmpty {
                    Text("Choose Download engine above for automatic setup. Complete engines are stored in Spiced-Rum's Application Support folder.").foregroundStyle(.secondary)
                }
                Button("Advanced: register an existing runtime…") { showRuntime = true }.disabled(!store.storageAvailable)
                ForEach(store.catalog.runtimes) { runtime in
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(runtime.name).fontWeight(.medium)
                            Text(runtime.version).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let version = runtime.gptkVersion {
                                Text("D3DMetal payload · GPTK \(version)").font(.caption2).foregroundStyle(.green)
                            }
                            if let package = runtime.dxvkPackage {
                                Text("DXVK · \(dxvkVersionName(package))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(runtime.executable.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(runtime.useRosetta ? "Rosetta · x64" : "Runtime managed").font(.caption).foregroundStyle(.secondary)
                        Button("Reveal") { NSWorkspace.shared.selectFile(runtime.executable.path, inFileViewerRootedAtPath: "") }
                        Button("Remove…") { requestRuntimeRemoval(runtime) }
                            .disabled(store.setupBusy || !store.storageAvailable)
                    }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
                Divider()
                Text("Explore macOS engines").font(.title3.weight(.semibold))
                Text("These are runtime sources, not a list of verified compatible games. Obtain and configure a complete engine before registering it.").font(.callout).foregroundStyle(.secondary)
                ForEach(RuntimeSource.allCases.filter { $0 != .custom }) { source in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(source.rawValue).font(.headline)
                            Spacer()
                            Text(source.status).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source.guidance).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Link("Publisher & setup ↗", destination: source.url)
                            Spacer()
                            Button("Register installed engine…") { chosenSource = source; showRuntime = true }.disabled(!store.storageAvailable)
                        }
                    }.padding(18).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                }
                Text("Proton and GE-Proton target Linux. Their macOS-relevant patches and components need macOS builds; their Linux release archives cannot be registered as engines here.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(34)
        }
        .sheet(isPresented: $showRuntime) { AddRuntimeView(source: chosenSource) }
        .sheet(isPresented: $showDownload) { EngineDownloadView() }
        .sheet(item: $dxvkRuntime) { DXVKVersionView(runtime: $0) }
        .sheet(item: $dxmtRuntime) { DXMTVersionView(runtime: $0) }
        .sheet(isPresented: $showRosetta) { RosettaSetupView() }
        .confirmationDialog("Remove this engine?", isPresented: Binding(
            get: { runtimePendingRemoval != nil },
            set: { if !$0 { runtimePendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let runtime = runtimePendingRemoval {
                Button("Remove engine", role: .destructive) {
                    do { try store.removeRuntime(runtime) }
                    catch { store.error = error.localizedDescription }
                    runtimePendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { runtimePendingRemoval = nil }
        } message: {
            Text(runtimeRemovalDescription)
        }
        .task {
            rosetta = await SystemSetup.rosettaAvailable()
            store.discoverAndSetUpAppleGPTK()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.resumeSetup()
            store.discoverAndSetUpAppleGPTK()
        }
    }

    private func requestRuntimeRemoval(_ runtime: Runtime) {
        if let blocker = store.runtimeRemovalBlocker(for: runtime) {
            store.error = blocker
            return
        }
        runtimeRemovalDescription = store.runtimeRemovalPrompt(for: runtime)
        runtimePendingRemoval = runtime
    }

    private var graphicsVersionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Graphics versions").font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("DXVK · macOS / MoltenVK").font(.subheadline.weight(.semibold))
                Text("Only macOS DXVK releases are shown. Their Windows x64 components run in the Rosetta Wine engines that provide MoltenVK; Linux Vulkan builds are excluded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let dxvkRuntimes = store.catalog.runtimes.filter(EngineInstaller.supportsMacOSDXVK)
                if dxvkRuntimes.isEmpty {
                    Text("Install a managed x64 macOS Wine engine with MoltenVK to manage DXVK versions.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(dxvkRuntimes) { runtime in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(runtime.name).fontWeight(.medium)
                                Text(runtime.dxvkPackage.map { "Selected: DXVK · \(dxvkVersionName($0))" } ?? "No DXVK version selected")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage versions…") { dxvkRuntime = runtime }.disabled(store.setupBusy || !store.storageAvailable)
                        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("DXMT · Metal").font(.subheadline.weight(.semibold))
                Text("Barrel Wine includes the Wine support needed for DXMT. Spiced-Rum installs the latest official DXMT builtin with Barrel Wine; use this section to install newer or older DXMT builds and switch versions for its shotglasses.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let dxmtRuntimes = store.catalog.runtimes.filter(EngineInstaller.supportsDXMTVersions)
                if dxmtRuntimes.isEmpty {
                    Text("Install Barrel Wine to manage official DXMT versions here.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(dxmtRuntimes) { runtime in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(runtime.name).fontWeight(.medium)
                                Text(runtime.dxmtPackage.map { "Selected: DXMT · \(dxmtVersionName($0))" } ?? "No DXMT version selected")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage versions…") { dxmtRuntime = runtime }.disabled(store.setupBusy || !store.storageAvailable)
                        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("D3DMetal · Apple GPTK").font(.subheadline.weight(.semibold))
                Text("Apple distributes D3DMetal inside versioned GPTK evaluation images. Each version is installed as its own verified Wine engine, so a shotglass can switch versions with Change engine.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let installedVersions = store.catalog.runtimes.compactMap(\.gptkVersion)
                let versions = Array(Set(store.gptkEvaluationVersions + installedVersions))
                    .sorted { GPTKInstaller.isNewerVersion($0, than: $1) }
                if versions.isEmpty {
                    Text("No alternate GPTK evaluation images are available. Download an Apple evaluation image and keep it in Downloads to add its version here.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(versions, id: \.self) { version in
                        let installed = store.catalog.runtimes.first {
                            $0.d3dMetal && $0.gptkVersion?.localizedStandardCompare(version) == .orderedSame
                        }
                        let matchingHost = store.availableGPTKHosts.contains {
                            $0.version.localizedStandardCompare(version) == .orderedSame
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("GPTK \(version)").fontWeight(.medium)
                                Text(installed.map { "Installed as \($0.name)" } ?? (matchingHost ? "Matching Apple Wine host found" : "Matching Apple Wine host not installed"))
                                    .font(.caption).foregroundStyle(installed == nil && !matchingHost ? .orange : .secondary)
                            }
                            Spacer()
                            if installed != nil {
                                Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                            } else {
                                Button("Install version") { store.setUpAppleGPTK(evaluationVersion: version) }
                                    .disabled(!matchingHost || store.setupBusy || !store.storageAvailable || ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15)
                            }
                        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Link("Find GPTK and evaluation versions at Apple ↗", destination: URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dxvkVersionName(_ package: URL) -> String {
        let folder = package.lastPathComponent == "package" ? package.deletingLastPathComponent() : package
        return folder.lastPathComponent.hasPrefix("DXVK-") ? String(folder.lastPathComponent.dropFirst(5)) : folder.lastPathComponent
    }

    private func dxmtVersionName(_ package: URL) -> String {
        package.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "DXMT-", with: "")
    }
}

struct AddRuntimeView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State var source: RuntimeSource
    @State private var name = ""
    @State private var executable: URL?
    @State private var rosetta = true
    @State private var metal = false
    @State private var dxmt = false
    @State private var probing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a macOS runtime").font(.title2.weight(.semibold))
            Picker("Engine family", selection: $source) {
                ForEach(RuntimeSource.allCases) { Text($0.rawValue).tag($0) }
            }
            Text(source.guidance).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Publisher & installation instructions ↗", destination: source.url)
            TextField("Runtime name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Text(executable?.path ?? "Select wine, wine64, or a prepared macOS launcher").font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Choose executable…") {
                    if let file = chooseFile(prompt: "Use Runtime") { executable = file }
                }
            }
            Toggle("Run the runtime using Rosetta 2 (x86_64)", isOn: $rosetta)
            Toggle("This complete runtime already integrates D3DMetal", isOn: $metal)
            Toggle("This complete runtime already integrates DXMT", isOn: $dxmt)
            Text("Graphics capabilities are supplied by your runtime. These switches do not install graphics libraries. Launcher scripts must forward arguments and preserve WINEPREFIX.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if probing { ProgressView().controlSize(.small); Text("Checking Wine…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Verify & add") { register() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(executable == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 580).disabled(probing)
        .onAppear { if name.isEmpty { name = source.rawValue } }
        .onChange(of: source) { _, value in name = value.rawValue; metal = false; dxmt = false }
    }

    func register() {
        guard let executable else { return }
        probing = true; error = nil
        let candidate = Runtime(name: name.trimmingCharacters(in: .whitespacesAndNewlines), executable: executable, useRosetta: rosetta, d3dMetal: metal, dxmt: dxmt, version: "")
        Task {
            defer { probing = false }
            do {
                var runtime = candidate; runtime.version = try await Wine.probe(candidate)
                try store.addRuntime(runtime); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
