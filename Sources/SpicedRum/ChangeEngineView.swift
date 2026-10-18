import SwiftUI
import SpicedRumCore

struct ChangeEngineView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let entry: ShotglassEntry
    @State private var runtimeID: UUID?
    @State private var backups: [EngineBackup] = []
    @State private var downloading = false
    @State private var deleting: EngineBackup?
    @State private var restoring: EngineBackup?
    @State private var error: String?
    private var runtime: Runtime? { store.catalog.runtimes.first { $0.id == runtimeID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Change shotglass engine").font(.title2.weight(.semibold))
            Text("\(entry.shotglass.name) · Currently using \(entry.shotglass.runtime.name)").foregroundStyle(.secondary)
            if entry.engineChangePending {
                Text("An engine change was interrupted. Restore a Wine environment backup below before using this shotglass.").foregroundStyle(.orange)
            } else {
                Picker("Installed engine", selection: $runtimeID) {
                    ForEach(store.catalog.runtimes) { engine in Text("\(engine.name) — \(engine.version)").tag(Optional(engine.id)) }
                }
                Button("Download older or newer engines…") { downloading = true }
                if let runtime { Text("Graphics after switching: \(runtime.defaultGraphics.rawValue)").font(.callout) }
                Text("Save your work and close this shotglass's Windows apps first. Spiced-Rum stops remaining Windows processes, backs up Wine's system files, registry and drive mappings, then updates the environment for the selected engine. Installed app/game folders and user files are excluded from the backup and stay in place.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("The Wine environment backup needs free disk space. It stays until you delete it after checking that your apps work.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Wine environment backups").font(.headline)
            Text("Restoring reverts Windows system files and registry while keeping app/game files and shortcuts. Apps installed after that backup may need repair because their registry entries can be newer.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    if backups.isEmpty { Text("No engine backups yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(backups) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.shotglass.runtime.name).fontWeight(.medium)
                                Text(backup.created.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { restoring = backup }
                            Button("Delete backup", role: .destructive) { deleting = backup }
                        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(maxHeight: 160)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if !entry.engineChangePending {
                    Button("Back up Wine & change engine") {
                        if let runtime { store.changeEngine(entry, to: runtime); dismiss() }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(runtime == nil || runtime?.id == entry.shotglass.runtime.id || store.busy.contains(entry.id))
                }
            }
        }.padding(28).frame(width: 660)
        .onAppear { runtimeID = entry.shotglass.runtime.id; loadBackups() }
        .sheet(isPresented: $downloading) { EngineDownloadView() }
        .confirmationDialog("Delete this Wine environment backup?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let backup = deleting {
                Button("Delete backup", role: .destructive) {
                    do { try ShotglassEngines.delete(backup, from: entry); loadBackups() }
                    catch { self.error = error.localizedDescription }
                    deleting = nil
                }
            }
        } message: { Text("This removes only the selected backup. The current shotglass, installed apps and engine remain in place. You won't be able to restore this snapshot afterward.") }
        .confirmationDialog("Restore this Wine environment?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
            if let backup = restoring {
                Button("Restore Wine environment") {
                    store.restoreEngineBackup(backup, entry: entry); dismiss()
                    restoring = nil
                }
            }
        } message: { Text("Save and close Windows apps first. Windows files and registry return to the backup's state. App/game folders stay in place. Spiced-Rum also backs up the current Wine environment before a normal restore.") }
    }

    func loadBackups() {
        do { backups = try ShotglassEngines.backups(for: entry) }
        catch { self.error = error.localizedDescription }
    }
}
