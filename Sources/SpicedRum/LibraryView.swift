import SwiftUI
import AppKit
import SpicedRumCore

private let amber = Color(red: 0.94, green: 0.64, blue: 0.29)

private struct SidebarActionButton: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                    .offset(y: -30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .zIndex(hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private enum ShotglassEditMode: String, Identifiable {
    case rename, duplicate
    var id: String { rawValue }
    var title: String { self == .rename ? "Rename Shotglass" : "Duplicate Shotglass" }
    var action: String { self == .rename ? "Rename" : "Duplicate" }
}

private struct ShotglassEditRequest: Identifiable {
    let entry: ShotglassEntry
    let mode: ShotglassEditMode
    var id: String { "\(entry.id.uuidString)-\(mode.id)" }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.medium).foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(amber.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.45)
    }
}

private struct ShotglassNameView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let entry: ShotglassEntry
    let mode: ShotglassEditMode
    @State private var name: String

    init(entry: ShotglassEntry, mode: ShotglassEditMode) {
        self.entry = entry
        self.mode = mode
        _name = State(initialValue: mode == .rename ? entry.shotglass.name : "\(entry.shotglass.name) Copy")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode.title).font(.title2.weight(.semibold))
            TextField("Shotglass name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if mode == .duplicate {
                Text("Copies the Windows environment, installed apps and games, settings, and shortcuts. Wine environment backups are not copied. This may need as much free space as the original shotglass.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(mode.action, action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy.contains(entry.id))
            }
        }
        .padding(26)
        .frame(width: 440)
    }

    private func save() {
        if mode == .rename { store.renameShotglass(entry, to: name) }
        else { store.duplicateShotglass(entry, name: name) }
        dismiss()
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section = "shotglasses"
    @State private var newShotglass = false
    @State private var shotglassToTrash: ShotglassEntry?
    @State private var editingShotglass: ShotglassEditRequest?
    @State private var showStartupIntro = true

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
                if section == "shotglasses" {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("SHOTGLASSES").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            SidebarActionButton(title: "Add a new shotglass", symbol: "plus", disabled: !store.storageAvailable) { newShotglass = true }
                            SidebarActionButton(title: "Refresh the shotglass list", symbol: "arrow.clockwise") { store.reload() }
                            SidebarActionButton(title: "Import an existing shotglass folder", symbol: "square.and.arrow.down") { store.importShotglass() }
                        }
                        .buttonStyle(.plain)

                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(store.entries) { entry in
                                    HStack(spacing: 7) {
                                        Button { store.selection = entry.id } label: {
                                            HStack(spacing: 8) {
                                                ShotglassMark().frame(width: 17, height: 17)
                                                    .opacity(store.selection == entry.id ? 1 : 0.68)
                                                Text(entry.shotglass.name).lineLimit(1)
                                                Spacer(minLength: 0)
                                                if store.busy.contains(entry.id) { ProgressView().controlSize(.mini) }
                                            }
                                            .contentShape(Rectangle())
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Circle()
                                            .fill(entry.shotglass.initialized ? .green.opacity(0.8) : amber)
                                            .frame(width: 8, height: 8)
                                            .help(entry.shotglass.initialized ? "Ready" : "Setup needed")
                                            .accessibilityLabel(entry.shotglass.initialized ? "Ready" : "Setup needed")

                                        Button { shotglassToTrash = entry } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20, height: 22)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Move \(entry.shotglass.name) to Trash")
                                        .accessibilityLabel("Move \(entry.shotglass.name) to Trash")
                                        .disabled(store.busy.contains(entry.id))
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(store.selection == entry.id ? amber.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .contextMenu {
                                        Button("Rename…", systemImage: "pencil") { editingShotglass = ShotglassEditRequest(entry: entry, mode: .rename) }
                                            .disabled(store.busy.contains(entry.id))
                                        Button("Duplicate…", systemImage: "plus.square.on.square") { editingShotglass = ShotglassEditRequest(entry: entry, mode: .duplicate) }
                                            .disabled(store.busy.contains(entry.id))
                                    }
                                }
                                if store.entries.isEmpty {
                                    Text("No shotglasses yet").font(.caption).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 6)
                                }
                            }
                        }.frame(maxHeight: .infinity)
                    }.padding(.horizontal, 10)
                }
                Spacer()
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.075, green: 0.079, blue: 0.087))
            .navigationSplitViewColumnWidth(270)
        } detail: {
            ZStack {
                Group {
                    if section == "runtimes" { SetupView() }
                    else if let entry = store.entries.first(where: { $0.id == store.selection }) {
                        ScrollView { ShotglassDetail(entry: entry).padding(34) }
                    } else {
                        shotglassSelectionEmptyState
                    }
                }.background(Color(red: 0.105, green: 0.109, blue: 0.12))

                if showStartupIntro && !reduceMotion {
                    RumPouringIntroView {
                        withAnimation(.easeInOut(duration: 0.55)) { showStartupIntro = false }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
        }
        .sheet(isPresented: $newShotglass) { NewShotglassView() }
        .sheet(item: $editingShotglass) { request in ShotglassNameView(entry: request.entry, mode: request.mode) }
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

    var shotglassSelectionEmptyState: some View {
        VStack(spacing: 12) {
            ShotglassMark().frame(width: 44, height: 44).opacity(0.7)
            Text(store.entries.isEmpty ? "No shotglasses yet" : "Select a shotglass")
                .font(.title2.weight(.semibold))
            Text(store.entries.isEmpty ? "Create one from the Shotglasses panel." : "Choose a shotglass in the side panel to view its details and controls.")
                .foregroundStyle(.secondary)
            if store.entries.isEmpty {
                Button("New shotglass") { newShotglass = true }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!store.storageAvailable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShotglassDetail: View {
    @EnvironmentObject var store: LibraryStore
    let entry: ShotglassEntry
    @State private var showDependencies = false
    @State private var showEngineChange = false
    @State private var showDXVKVersions = false
    @State private var showForceStopConfirmation = false
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
            }
            HStack(spacing: 16) {
                Label(entry.shotglass.runtime.name, systemImage: "cpu")
                Label(entry.shotglass.graphics.rawValue, systemImage: "display")
                Label("Windows x64", systemImage: "gamecontroller")
            }
            .font(.caption).foregroundStyle(.secondary)
            if entry.engineChangePending && !store.busy.contains(entry.id) {
                Text("An engine change was interrupted. Open Change engine to restore a Wine environment backup.").foregroundStyle(.orange)
            } else if !entry.shotglass.initialized {
                Text("This shotglass has not finished setup. If DXVK was selected, choose its extracted package again when retrying.").foregroundStyle(.secondary)
                Button("Retry initialization") {
                    let dxvk = entry.shotglass.graphics == .dxvk ? (entry.dxvkPackage ?? chooseFolder(prompt: "Choose DXVK Package")) : nil
                    if entry.shotglass.graphics != .dxvk || dxvk != nil { store.initialize(entry, dxvk: dxvk) }
                }.disabled(store.busy.contains(entry.id))
            } else {
                HStack {
                    Button("Run installer or executable…", systemImage: "play.fill") {
                        if let file = chooseFile(prompt: "Run in Shotglass", extensions: ["exe", "msi"]) { store.run(entry, executable: file) }
                    }.buttonStyle(PrimaryButtonStyle())
                    Button("Wine configuration") { store.configure(entry) }
                    Menu {
                        ForEach(ShotglassGraphics.choices(for: entry)) { graphics in
                            Button {
                                if graphics == .dxvk && entry.dxvkPackage == nil { showDXVKVersions = true }
                                else { store.changeGraphics(entry, to: graphics) }
                            } label: {
                                if graphics == entry.shotglass.graphics { Label(graphics.rawValue, systemImage: "checkmark") }
                                else { Text(graphics.rawValue) }
                            }
                        }
                    } label: {
                        Label("Graphics: \(entry.shotglass.graphics.rawValue)", systemImage: "display")
                    }.help("Change graphics for this shotglass. Windows processes stop before the switch.")
                    if EngineInstaller.supportsMacOSDXVK(entry.shotglass.runtime) || entry.dxvkPackage != nil {
                        Button("DXVK version…", systemImage: "square.stack.3d.up") { showDXVKVersions = true }
                            .help("Choose a DXVK version for this shotglass. Other shotglasses are not changed.")
                    }
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
        .sheet(isPresented: $showDXVKVersions) { DXVKVersionView(entry: entry) }
        .confirmationDialog("Force Stop \(entry.shotglass.name)?", isPresented: $showForceStopConfirmation, titleVisibility: .visible) {
            Button("Force Stop All Windows Apps", role: .destructive) { store.forceStop(entry) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will immediately stop every Windows process running in this shotglass. Unsaved game or app progress may be lost. Other shotglasses will not be affected.")
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
