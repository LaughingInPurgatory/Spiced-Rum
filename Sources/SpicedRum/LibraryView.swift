import SwiftUI
import AppKit
import SpicedRumCore

private let amber = Color(red: 0.94, green: 0.64, blue: 0.29)

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.medium).foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(amber.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var section = "shotglasses"
    @State private var newShotglass = false
    @State private var search = ""
    @State private var shotglassToTrash: ShotglassEntry?

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    ShotglassMark().frame(width: 25, height: 25)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spiced-Rum").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("A little spirit. More play.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 28)
                VStack(spacing: 5) {
                    nav("Your shotglasses", icon: "square.grid.2x2", value: "shotglasses", count: store.entries.count)
                    nav("Runtimes & setup", icon: "cpu", value: "runtimes")
                }
                if section == "shotglasses" && !store.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("COLLECTION").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        ForEach(store.entries) { entry in
                            HStack(spacing: 4) {
                                Button { store.selection = entry.id } label: {
                                    HStack(spacing: 8) {
                                        ShotglassMark().frame(width: 17, height: 17).opacity(store.selection == entry.id ? 1 : 0.68)
                                        Text(entry.shotglass.name).lineLimit(1)
                                        Spacer(minLength: 2)
                                        if store.busy.contains(entry.id) { ProgressView().controlSize(.mini) }
                                    }
                                    .contentShape(Rectangle())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)

                                Button { shotglassToTrash = entry } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Move \(entry.shotglass.name) to Trash")
                                .accessibilityLabel("Move \(entry.shotglass.name) to Trash")
                                .disabled(store.busy.contains(entry.id))
                            }
                        }
                    }.padding(.horizontal, 10)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Made for Apple Silicon", systemImage: "apple.logo").font(.caption)
                    Text("Developed by Laughing In Purgatory").font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("DEVELOPMENT PREVIEW  0.1").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.tertiary)
                }.padding(10)
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.075, green: 0.079, blue: 0.087))
            .navigationSplitViewColumnWidth(240)
        } detail: {
            Group {
                if section == "runtimes" { SetupView() }
                else { shotglasses }
            }.background(Color(red: 0.105, green: 0.109, blue: 0.12))
        }
        .sheet(isPresented: $newShotglass) { NewShotglassView() }
        .alert("Spiced-Rum", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Move \(shotglassToTrash?.shotglass.name ?? "Shotglass") to Trash?", isPresented: Binding(
            get: { shotglassToTrash != nil },
            set: { if !$0 { shotglassToTrash = nil } }
        ), titleVisibility: .visible) {
            Button("Move Shotglass to Trash", role: .destructive) {
                if let shotglassToTrash { store.removeShotglass(shotglassToTrash) }
                shotglassToTrash = nil
            }
            Button("Cancel", role: .cancel) { shotglassToTrash = nil }
        } message: {
            Text("Spiced-Rum will stop this shotglass's Windows processes and move its entire folder to macOS Trash, including its Windows environment, installed apps and games, settings, and backups. You can restore it from Trash. The shared Wine engine will stay installed.")
        }
    }

    func nav(_ title: String, icon: String, value: String, count: Int? = nil) -> some View {
        Button { section = value } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
            }.padding(11).background(section == value ? amber.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(section == value ? amber : .secondary)
        }.buttonStyle(.plain)
    }

    var shotglasses: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your shotglasses").font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("A home for your Windows games and apps.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Import shotglass folder…") { store.importShotglass() }
                        Button("Refresh library") { store.reload() }
                    } label: { Image(systemName: "ellipsis").padding(5) }.menuStyle(.borderlessButton).fixedSize()
                    Button { newShotglass = true } label: { Label("New shotglass", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!store.storageAvailable)
                }
                if store.entries.isEmpty { emptyState }
                else {
                    TextField("Find a shotglass", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], spacing: 16) {
                        ForEach(store.entries.filter { search.isEmpty || $0.shotglass.name.localizedCaseInsensitiveContains(search) }) { entry in
                            shotglassCard(entry)
                        }
                    }
                    if let entry = store.entries.first(where: { $0.id == store.selection }) { ShotglassDetail(entry: entry) }
                }
            }.padding(34)
        }
    }

    var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(amber.opacity(0.07)).frame(width: 150, height: 150)
                Circle().stroke(amber.opacity(0.16), lineWidth: 1).frame(width: 118, height: 118)
                ShotglassMark().frame(width: 58, height: 58)
            }
            Text("Good games deserve a good shotglass.").font(.system(size: 23, weight: .medium, design: .rounded))
            Text("Create a separate Windows environment for a game, Steam,\nor an app. Keep each one's settings and files together.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
            Button("Create your first shotglass") { newShotglass = true }.buttonStyle(PrimaryButtonStyle()).controlSize(.large).disabled(!store.storageAvailable)
            Button("Set up a Wine runtime", systemImage: "arrow.right") { section = "runtimes" }.buttonStyle(.plain).foregroundStyle(.secondary)
            HStack(spacing: 28) {
                Label("Windows x64", systemImage: "gamecontroller")
                Label("Your choice of folder", systemImage: "externaldrive")
                Label("Metal graphics", systemImage: "sparkles")
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 25)
        }.frame(maxWidth: .infinity).padding(.vertical, 54)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.06)))
    }

    func shotglassCard(_ entry: ShotglassEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { store.selection = entry.id } label: {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        ShotglassMark().frame(width: 34, height: 38).frame(width: 48, height: 52).background(amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.shotglass.name).font(.headline).lineLimit(1)
                        Text(entry.shotglass.runtime.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack {
                        Text("x64").font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 3).background(.white.opacity(0.06), in: Capsule())
                        Text(entry.shotglass.graphics.rawValue).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(store.selection == entry.id ? amber.opacity(0.65) : .white.opacity(0.07)))
                    .contentShape(RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)

            Circle()
                .fill(entry.shotglass.initialized ? .green.opacity(0.75) : amber)
                .frame(width: 6, height: 6)
                .offset(x: -18, y: 8)

            Button { shotglassToTrash = entry } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.red.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Move \(entry.shotglass.name) to Trash")
            .accessibilityLabel("Move \(entry.shotglass.name) to Trash")
            .disabled(store.busy.contains(entry.id))
            .offset(x: -9, y: 49)
        }
    }
}

struct ShotglassDetail: View {
    @EnvironmentObject var store: LibraryStore
    let entry: ShotglassEntry
    @State private var showDependencies = false
    @State private var showEngineChange = false
    @State private var showForceStopConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var steamFixProgram: Program?
    @State private var enableSteamFix: Bool?
    @State private var heroicRepairProgram: Program?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.shotglass.name).font(.title2.weight(.semibold))
                    Text(store.messages[entry.id] ?? (entry.shotglass.initialized ? "Ready to launch" : "Initialization required")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.busy.contains(entry.id) { ProgressView().controlSize(.small) }
                Button("Show files", systemImage: "folder") { NSWorkspace.shared.open(entry.folder) }
                Button("Logs", systemImage: "text.alignleft") { NSWorkspace.shared.selectFile(entry.log.path, inFileViewerRootedAtPath: entry.folder.path) }
                Button(role: .destructive) { showForceStopConfirmation = true } label: {
                    Label("Force Stop", systemImage: "stop.fill")
                }.disabled(!entry.shotglass.initialized || store.stopping.contains(entry.id))
                Button("Change engine…", systemImage: "cpu") { showEngineChange = true }.disabled(store.busy.contains(entry.id))
                Menu {
                    Button(role: .destructive) { showRemoveConfirmation = true } label: {
                        Label("Move Shotglass to Trash…", systemImage: "trash")
                    }.disabled(store.busy.contains(entry.id))
                } label: {
                    Image(systemName: "ellipsis").padding(5)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if entry.engineChangePending {
                Text("An engine change was interrupted. Open Change engine to restore a Wine environment backup.").foregroundStyle(.orange)
            } else if !entry.shotglass.initialized {
                Text("This shotglass has not finished setup. If DXVK was selected, choose its extracted package again when retrying.").foregroundStyle(.secondary)
                Button("Retry initialization") {
                    let dxvk = entry.shotglass.graphics == .dxvk ? (entry.shotglass.runtime.dxvkPackage ?? chooseFolder(prompt: "Choose DXVK Package")) : nil
                    if entry.shotglass.graphics != .dxvk || dxvk != nil { store.initialize(entry, dxvk: dxvk) }
                }.disabled(store.busy.contains(entry.id))
            } else {
                HStack {
                    Button("Run installer or executable…", systemImage: "play.fill") {
                        if let file = chooseFile(prompt: "Run in Shotglass", extensions: ["exe", "msi"]) { store.run(entry, executable: file) }
                    }.buttonStyle(PrimaryButtonStyle())
                    Button("Wine configuration") { store.configure(entry) }
                    Button("Install components…") { showDependencies = true }
                    Spacer()
                    Button("Add application…", systemImage: "plus") {
                        if let file = chooseFile(prompt: "Add Application", extensions: ["exe"], initial: entry.prefix.appendingPathComponent("drive_c")) { store.saveProgram(entry, executable: file) }
                    }
                }.disabled(store.busy.contains(entry.id))
                if entry.shotglass.programs.isEmpty {
                    Text("Run a Windows installer, then add its installed .exe here. Heroic setup files are extracted directly to bypass its unreliable running-app check.")
                        .font(.callout).foregroundStyle(.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                }
                ForEach(entry.shotglass.programs) { program in
                        HStack(spacing: 12) {
                        Image(systemName: "app.dashed").font(.title2).foregroundStyle(amber)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(program.name).fontWeight(.medium)
                            Text(program.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if store.isSteam(program), store.steamFixState(program, in: entry) == .active {
                            Label("Steam UI fix on · client updates paused", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.green).lineLimit(1)
                        } else if store.isSteam(program), store.steamFixState(program, in: entry) == .helperChanged {
                            Label("Steam helper changed · restore available", systemImage: "exclamationmark.circle.fill")
                                .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        }
                        if program.isHeroicLauncher && program.heroicUIWorkaroundEnabled {
                            Label("Heroic software renderer on", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.green).lineLimit(1)
                        }
                        Button("Launch", systemImage: "play.fill") {
                            do { store.run(entry, executable: try ShotglassFiles.programURL(program, in: entry), launchArguments: program.launchArguments) }
                            catch { store.error = error.localizedDescription }
                        }.disabled(store.busy.contains(entry.id))
                        Menu {
                            if store.isSteam(program) {
                                switch store.steamFixState(program, in: entry) {
                                case .inactive:
                                    Button("Fix Steam's black login window…", systemImage: "sparkles") {
                                        steamFixProgram = program; enableSteamFix = true
                                    }
                                case .active:
                                    Button("Remove Steam UI fix…", systemImage: "arrow.uturn.backward") {
                                        steamFixProgram = program; enableSteamFix = false
                                    }
                                case .helperChanged:
                                    Button("Restore saved Steam helper…", systemImage: "arrow.uturn.backward") {
                                        steamFixProgram = program; enableSteamFix = false
                                    }
                                case .needsRecovery:
                                    Button("Review Steam fix recovery…", systemImage: "exclamationmark.triangle") {
                                        store.error = "Spiced-Rum found an incomplete Steam UI fix. Open Show files and inspect Steam/bin/cef/cef.win64. Spiced-Rum left those files untouched so the saved original can be recovered safely."
                                    }
                                }
                                Divider()
                            }
                            if program.isHeroicLauncher {
                                Button(program.heroicUIWorkaroundEnabled ? "Remove Heroic software renderer" : "Use Heroic software renderer") {
                                    store.changeHeroicUIWorkaround(!program.heroicUIWorkaroundEnabled, for: program, in: entry)
                                }
                                Button("Repair Heroic blank window…", systemImage: "sparkles") {
                                    heroicRepairProgram = program
                                }
                                Divider()
                            }
                            Button("Remove shortcut") { store.removeProgram(program, from: entry) }
                        } label: { Image(systemName: "ellipsis") }.fixedSize()
                    }.padding(12).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            Text(entry.folder.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .sheet(isPresented: $showDependencies) { DependencyView(entry: entry) }
        .sheet(isPresented: $showEngineChange) { ChangeEngineView(entry: entry) }
        .confirmationDialog("Force Stop \(entry.shotglass.name)?", isPresented: $showForceStopConfirmation, titleVisibility: .visible) {
            Button("Force Stop All Windows Apps", role: .destructive) { store.forceStop(entry) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will immediately stop every Windows process running in this shotglass. Unsaved game or app progress may be lost. Other shotglasses will not be affected.")
        }
        .confirmationDialog("Move \(entry.shotglass.name) to Trash?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Move Shotglass to Trash", role: .destructive) { store.removeShotglass(entry) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Spiced-Rum will stop this shotglass's Windows processes and move its entire folder to macOS Trash, including its Windows environment, installed apps and games, settings, and backups. You can restore it from Trash. The shared Wine engine will stay installed.")
        }
        .confirmationDialog("Repair Heroic's blank window?", isPresented: Binding(
            get: { heroicRepairProgram != nil },
            set: { if !$0 { heroicRepairProgram = nil } }
        ), titleVisibility: .visible) {
            if let heroicRepairProgram {
        Button("Stop apps and clear Heroic cache", role: .destructive) {
                    store.repairHeroicUI(for: heroicRepairProgram, in: entry)
                    self.heroicRepairProgram = nil
                }
            }
            Button("Cancel", role: .cancel) { heroicRepairProgram = nil }
        } message: {
            Text("Spiced-Rum will stop every Windows process in this shotglass, remove only Heroic's regenerable GPU cache from its Windows profiles, and launch Heroic's interface with Chromium's CPU-based ANGLE/SwiftShader renderer. This affects Heroic's interface only, not games launched from it. Unsaved work in other apps in this shotglass may be lost. Heroic settings, games, and other shotglasses are untouched.")
        }
        .confirmationDialog("Steam black-window compatibility", isPresented: Binding(
            get: { steamFixProgram != nil && enableSteamFix != nil },
            set: { if !$0 { steamFixProgram = nil; enableSteamFix = nil } }
        ), titleVisibility: .visible) {
            if let steamFixProgram, enableSteamFix == true {
                Button("Enable Steam interface fix") {
                    store.changeSteamFix(true, for: steamFixProgram, in: entry)
                    self.steamFixProgram = nil; enableSteamFix = nil
                }
            } else if let steamFixProgram {
                Button("Restore original Steam files") {
                    store.changeSteamFix(false, for: steamFixProgram, in: entry)
                    self.steamFixProgram = nil; enableSteamFix = nil
                }
            }
            Button("Cancel", role: .cancel) { steamFixProgram = nil; enableSteamFix = nil }
        } message: {
            if enableSteamFix == true {
                Text("Spiced-Rum will stop Windows processes in this shotglass, save Steam's original web helper, and install a small helper that disables Chromium GPU rendering and runs Steam's browser UI in one process. Steam client auto-updates will be paused while the fix is enabled; your games keep the shotglass's selected graphics engine. Remove the fix to restore the saved helper and previous Steam setting.")
            } else {
                Text("Spiced-Rum will stop Windows processes in this shotglass and restore Steam's saved web helper and previous steam.cfg setting. If Steam replaced its helper while the fix was enabled, Spiced-Rum keeps that updated file alongside the restored original.")
            }
        }
    }
}
