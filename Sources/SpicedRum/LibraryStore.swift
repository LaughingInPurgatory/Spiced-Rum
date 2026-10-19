import AppKit
import SwiftUI
import SpicedRumCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published var catalog: Catalog
    @Published var entries: [ShotglassEntry] = []
    @Published var selection: UUID?
    @Published var error: String?
    @Published var busy: Set<UUID> = []
    @Published var stopping: Set<UUID> = []
    @Published var messages: [UUID: String] = [:]
    @Published var storageAvailable = true
    @Published var setupBusy = false
    @Published var setupMessage = ""
    @Published var setupProgress: Double?
    @Published var waitingForHomebrew = false
    @Published var detectedGPTK: Runtime?
    @Published var gptkBetaAvailable = false
    @Published var gptkBetaVersion: String?
    var support: URL { catalogURL.deletingLastPathComponent() }
    var setupLog: URL { support.appendingPathComponent("setup.log") }
    private let catalogURL: URL
    private var attemptedGPTKPaths: Set<String> = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Spiced-Rum", isDirectory: true)
        catalogURL = support.appendingPathComponent("library.json")
        catalog = Catalog(defaultLocation: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Spiced-Rum Shotglasses", isDirectory: true))
        detectedGPTK = RuntimeDiscovery.appleGamePortingToolkit()
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
            }
            reload()
        } catch {
            // Never replace an unreadable catalog with an empty library.
            storageAvailable = false
            self.error = "Cannot load the library at \(catalogURL.path). Your files have been preserved.\n\(error.localizedDescription)"
        }
    }

    func persist(_ updated: Catalog) throws {
        guard storageAvailable else { throw RumError.message("Library storage is unavailable. Repair library.json and restart Spiced-Rum.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: catalogURL, options: .atomic)
        catalog = updated
    }

    func reload() {
        var loaded: [ShotglassEntry] = []
        var missing: [String] = []
        for folder in catalog.shotglassFolders {
            do { loaded.append(ShotglassEntry(shotglass: try Shotglass.load(from: folder), folder: folder)) }
            catch { missing.append("\(folder.path): \(error.localizedDescription)") }
        }
        entries = loaded.sorted { $0.shotglass.created > $1.shotglass.created }
        if selection == nil { selection = entries.first?.id }
        if !missing.isEmpty { error = "Some shotglasses could not be loaded. Reconnect external drives and refresh.\n" + missing.joined(separator: "\n") }
    }

    func addRuntime(_ runtime: Runtime) throws {
        var updated = catalog; updated.runtimes.append(runtime); try persist(updated)
    }

    func runtimeRemovalBlocker(for runtime: Runtime) -> String? {
        guard !setupBusy else { return "Wait for engine setup to finish before removing a runtime." }
        guard catalog.runtimes.contains(where: { $0.id == runtime.id }) else { return "This runtime is no longer registered. Refresh the runtime list and try again." }
        var currentEntries: [ShotglassEntry] = []
        for folder in catalog.shotglassFolders {
            do { currentEntries.append(ShotglassEntry(shotglass: try Shotglass.load(from: folder), folder: folder)) }
            catch { return "Spiced-Rum could not inspect every registered shotglass, so it cannot confirm this engine is unused. Reconnect its drive or repair its metadata before removing the engine.\n\(folder.path): \(error.localizedDescription)" }
        }
        let users = currentEntries.filter { $0.shotglass.runtime.id == runtime.id }.map(\.shotglass.name)
        if !users.isEmpty {
            return "\(runtime.name) is still used by \(users.joined(separator: ", ")). Change those shotglasses to another engine before removing it."
        }
        if currentEntries.contains(where: \.engineChangePending) {
            return "A shotglass has an unfinished engine change. Restore its saved environment before removing any engine."
        }
        for entry in currentEntries {
            do {
                if try ShotglassEngines.backupReferences(runtimeID: runtime.id, for: entry) {
                    return "A recoverable engine backup for \(entry.shotglass.name) refers to \(runtime.name). Delete that backup after confirming it is no longer needed."
                }
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    func runtimeRemovalPrompt(for runtime: Runtime) -> String {
        let engines = support.appendingPathComponent("Engines", isDirectory: true)
        if RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines) != nil {
            return "This removes \(runtime.name) from Spiced-Rum and deletes its downloaded engine files. Shotglasses and their app files are not changed."
        }
        return "This removes \(runtime.name) from Spiced-Rum. Its files are outside Spiced-Rum's managed engine folder and will remain on disk."
    }

    func removeRuntime(_ runtime: Runtime) throws {
        if let blocker = runtimeRemovalBlocker(for: runtime) { throw RumError.message(blocker) }
        var updated = catalog
        updated.runtimes.removeAll { $0.id == runtime.id }
        let engines = support.appendingPathComponent("Engines", isDirectory: true)
        let managedDirectory = RuntimeManagement.managedEngineDirectory(for: runtime, inside: engines)

        if let managedRoot = runtime.managedRoot?.standardizedFileURL,
           managedRoot.deletingLastPathComponent() == engines.standardizedFileURL,
           FileManager.default.fileExists(atPath: managedRoot.path), managedDirectory == nil {
            throw RumError.message("Spiced-Rum found this engine under its managed Engines folder but could not verify that the folder is safe to delete. No files were removed.")
        }

        guard let managedDirectory else { try persist(updated); return }
        let quarantine = engines.appendingPathComponent(".removing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: managedDirectory, to: quarantine)
        do { try persist(updated) }
        catch {
            try? FileManager.default.moveItem(at: quarantine, to: managedDirectory)
            throw error
        }
        do { try FileManager.default.removeItem(at: quarantine) }
        catch {
            throw RumError.message("\(runtime.name) was removed from Spiced-Rum, but macOS could not fully delete its files. They remain at \(quarantine.path). \(error.localizedDescription)")
        }
    }

    func discoverAndSetUpAppleGPTK() {
        detectedGPTK = RuntimeDiscovery.appleGamePortingToolkit()
        gptkBetaVersion = GPTKInstaller.availableEvaluationVersion()
        gptkBetaAvailable = gptkBetaVersion != nil
        guard let runtime = detectedGPTK else { return }
        let path = runtime.executable.resolvingSymlinksInPath().standardizedFileURL.path
        let betaName = gptkBetaVersion.map { "Apple GPTK \($0)" }
        let betaReady = betaName.map { name in catalog.runtimes.contains { $0.name == name && $0.managedRoot != nil } } ?? false
        let baseReady = catalog.runtimes.contains { $0.executable.resolvingSymlinksInPath().standardizedFileURL.path == path }
        guard (gptkBetaAvailable ? !betaReady : !baseReady), !setupBusy else { return }
        let attemptKey = path + (gptkBetaAvailable ? "#beta:\(gptkBetaVersion ?? "latest")" : "#base")
        guard !attemptedGPTKPaths.contains(attemptKey) else { return }
        attemptedGPTKPaths.insert(attemptKey)
        setUpAppleGPTK(runtime)
    }

    func setUpAppleGPTK(_ candidate: Runtime? = nil) {
        guard !setupBusy else { return }
        guard let candidate = candidate ?? detectedGPTK else {
            setupMessage = "Apple Game Porting Toolkit was not found. Install its evaluation environment, then choose Check again."
            return
        }
        let path = candidate.executable.resolvingSymlinksInPath().standardizedFileURL.path
        let betaAvailable = GPTKInstaller.hasDownloadedOrMountedEvaluationEnvironment()
        let betaName = GPTKInstaller.availableEvaluationVersion().map { "Apple GPTK \($0)" }
        let betaReady = betaName.map { name in catalog.runtimes.contains { $0.name == name && $0.managedRoot != nil } } ?? false
        let baseReady = catalog.runtimes.contains(where: { $0.executable.resolvingSymlinksInPath().standardizedFileURL.path == path })
        guard betaAvailable ? !betaReady : !baseReady else {
            setupMessage = "Apple Game Porting Toolkit is already registered. You can select it for new shotglasses or change an existing shotglass's engine."
            return
        }
        setupBusy = true
        error = nil
        setupMessage = betaAvailable
            ? "The downloaded GPTK evaluation image was found. Preparing a private GPTK beta runtime and leaving Apple's installed app unchanged…"
            : "Apple Game Porting Toolkit found. Checking Wine, D3DMetal, and a temporary Windows x64 environment…"
        setupProgress = nil
        Task {
            defer { setupBusy = false }
            do {
                guard await SystemSetup.rosettaAvailable() else {
                    throw RumError.message("Apple Game Porting Toolkit uses Intel Wine. Set up Rosetta 2 in Runtimes & setup, then retry GPTK setup.")
                }
                var runtime: Runtime
                if let evaluation = try await GPTKInstaller.findOrMountEvaluationEnvironment() {
                    do {
                        setupMessage = "Copying Wine's core and adding GPTK's matching beta graphics libraries. This may take a few minutes…"
                        runtime = try await GPTKInstaller.install(evaluation, using: candidate, into: support.appendingPathComponent("Engines", isDirectory: true))
                        await GPTKInstaller.unmountIfMountedBySpicedRum(evaluation)
                    } catch {
                        await GPTKInstaller.unmountIfMountedBySpicedRum(evaluation)
                        throw error
                    }
                } else {
                    guard !baseReady else {
                        throw RumError.message("GPTK is already registered, but the downloaded evaluation image could not be mounted. Open the downloaded image in Finder, then choose Check again.")
                    }
                    runtime = candidate
                }
                setupMessage = "Checking the Wine launcher and creating a temporary Windows x64 environment…"
                let wineVersion = try await Wine.probe(runtime)
                if runtime.version.isEmpty { runtime.version = wineVersion }
                let validation = support.appendingPathComponent("GPTK validation", isDirectory: true)
                try await EngineInstaller.checkX64(runtime, in: validation)
                try addRuntime(runtime)
                setupMessage = "\(runtime.name) is ready (\(runtime.version)). Spiced-Rum verified D3DMetal and a Windows x64 prefix. Select it when creating a shotglass or changing its engine."
            } catch {
                setupMessage = "Apple Game Porting Toolkit setup needs attention. The temporary x64 test failed; your existing shotglasses were not changed."
                self.error = error.localizedDescription
            }
        }
    }

    func installEngine(_ asset: EngineAsset, feed: EngineFeed, allowUnverified: Bool = false) {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Preparing engine…"; setupProgress = nil
        Task {
            defer { setupBusy = false }
            do {
                guard await SystemSetup.rosettaAvailable() else { throw RumError.message("This engine needs Rosetta 2 to translate Intel code on your Mac. Choose Set up Rosetta in Runtimes & setup, review Apple's license, then retry the engine download.") }
                let runtime = try await EngineInstaller.install(asset, feed: feed, into: support.appendingPathComponent("Engines"), allowUnverified: allowUnverified) { message, progress in
                    Task { @MainActor in self.setupMessage = message; self.setupProgress = progress }
                }
                do { try addRuntime(runtime) }
                catch { if let root = runtime.managedRoot { try? FileManager.default.removeItem(at: root) }; throw error }
                setupMessage = "\(runtime.name) is ready. Choose it when creating a shotglass or changing an existing shotglass's engine. Other installed versions are kept."
            } catch { setupMessage = "Setup needs attention"; self.error = error.localizedDescription }
        }
    }

    func installDXVK(_ asset: EngineAsset, for runtime: Runtime, allowUnverified: Bool = false) {
        manageDXVK(for: runtime) {
            try await EngineInstaller.installDXVKPackage(asset, for: runtime, allowUnverified: allowUnverified) { message, progress in
                Task { @MainActor in self.setupMessage = message; self.setupProgress = progress }
            }
        }
    }

    func selectDXVK(_ package: DXVKPackage, for runtime: Runtime) {
        manageDXVK(for: runtime) { package.folder }
    }

    private func manageDXVK(for runtime: Runtime, package: @escaping () async throws -> URL) {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Preparing DXVK…"; setupProgress = nil
        Task {
            defer { setupBusy = false }
            do {
                let packageURL = try await package()
                try await applyDXVK(packageURL, to: runtime)
                setupMessage = "DXVK \(packageURL.deletingLastPathComponent().lastPathComponent) is active for \(runtime.name) and its shotglasses."
            } catch { setupMessage = "DXVK setup needs attention"; self.error = error.localizedDescription }
        }
    }

    private func applyDXVK(_ package: URL, to runtime: Runtime) async throws {
        try Wine.validateDXVK(package)
        guard let runtimeIndex = catalog.runtimes.firstIndex(where: { $0.id == runtime.id }) else {
            throw RumError.message("This runtime is no longer registered. Refresh the runtime list and try again.")
        }
        let oldRuntime = catalog.runtimes[runtimeIndex]
        guard oldRuntime.managedRoot == runtime.managedRoot else {
            throw RumError.message("This runtime changed while DXVK was being prepared. Refresh Runtimes & setup and retry.")
        }

        var affected: [ShotglassEntry] = []
        for folder in catalog.shotglassFolders {
            let shotglass = try Shotglass.load(from: folder)
            if shotglass.runtime.id == runtime.id { affected.append(ShotglassEntry(shotglass: shotglass, folder: folder)) }
        }
        guard !affected.contains(where: \.engineChangePending) else {
            throw RumError.message("A shotglass has an unfinished engine change. Restore its backup before changing DXVK versions.")
        }
        guard !affected.contains(where: { busy.contains($0.id) }) else {
            throw RumError.message("Wait for the current shotglass operation to finish before changing DXVK versions.")
        }
        let replacesActiveDXVK = affected.contains { $0.shotglass.initialized && $0.shotglass.graphics == .dxvk }
        let oldDXVKPackage = oldRuntime.dxvkPackage
        if replacesActiveDXVK { try Wine.validateDXVK(oldDXVKPackage) }

        var updatedRuntime = oldRuntime
        updatedRuntime.dxvkPackage = package
        busy.formUnion(affected.map(\.id))
        defer { busy.subtract(affected.map(\.id)) }
        var changed: [(original: ShotglassEntry, updated: ShotglassEntry, replacedPrefixDLLs: Bool)] = []
        do {
            for original in affected {
                var updated = original
                updated.shotglass.runtime = updatedRuntime
                var replacedPrefixDLLs = false
                if original.shotglass.initialized && original.shotglass.graphics == .dxvk {
                    try await Wine.stopServer(original)
                    do {
                        try Wine.removeDXVK(from: original.prefix)
                        try Wine.installDXVK(from: package, into: original.prefix)
                        replacedPrefixDLLs = true
                    } catch {
                        let failure = error
                        do {
                            guard let oldDXVKPackage else { throw RumError.message("The previous DXVK package is unavailable.") }
                            try Wine.installDXVK(from: oldDXVKPackage, into: original.prefix)
                        }
                        catch {
                            throw RumError.message("DXVK could not be replaced and the previous DLLs could not be restored. The package is preserved at \(package.path).\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
                        }
                        throw failure
                    }
                }
                changed.append((original, updated, replacedPrefixDLLs))
                try updated.shotglass.save(in: updated.folder)
                replaceEntry(updated)
            }
            var updatedCatalog = catalog
            updatedCatalog.runtimes[runtimeIndex] = updatedRuntime
            try persist(updatedCatalog)
        } catch {
            let failure = error
            do {
                for change in changed.reversed() {
                    if change.replacedPrefixDLLs {
                        try await Wine.stopServer(change.updated)
                        guard let oldDXVKPackage else { throw RumError.message("The previous DXVK package is unavailable.") }
                        try Wine.installDXVK(from: oldDXVKPackage, into: change.original.prefix)
                    }
                    try change.original.shotglass.save(in: change.original.folder)
                    replaceEntry(change.original)
                }
            } catch {
                throw RumError.message("DXVK changed part of this runtime's shotglasses and automatic rollback could not finish. Existing packages and shotglasses were preserved.\n\(failure.localizedDescription)\nRecovery: \(error.localizedDescription)")
            }
            throw failure
        }
    }

    func installDependencyTools() {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Installing Winetricks and extraction tools with Homebrew…"; setupProgress = nil
        Task {
            defer { setupBusy = false }
            do { try await Dependencies.installTools(log: setupLog); setupMessage = "Dependency tools are ready." }
            catch { setupMessage = "Tools setup needs attention"; self.error = error.localizedDescription }
        }
    }

    func prepareVideoSupport() {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Preparing GStreamer and H.264 video playback…"; setupProgress = nil
        let runtimes = catalog.runtimes.filter { $0.managedRoot != nil }
        Task {
            defer { setupBusy = false }
            do {
                for runtime in runtimes { try await MediaSupport.prepare(runtime) }
                setupMessage = "Video support is ready. Close your Windows apps and launch them again to use the new codecs."
            } catch { setupMessage = "Video setup needs attention"; self.error = error.localizedDescription }
        }
    }

    func prepareHomebrew() {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Downloading Homebrew's official macOS installer…"; setupProgress = nil
        Task {
            defer { setupBusy = false }
            do {
                let installer = try await SystemSetup.downloadHomebrewInstaller(into: support)
                guard NSWorkspace.shared.open(installer) else { throw RumError.message("Cannot open the Homebrew installer. Open \(installer.path) in Finder to continue.") }
                waitingForHomebrew = true
                setupMessage = "In Apple's Installer, choose Continue and Install, then authorize installation with your Mac administrator account. Return to Spiced-Rum afterward; dependency tools will finish setting up automatically."
            } catch { setupMessage = "Homebrew setup needs attention"; self.error = error.localizedDescription }
        }
    }

    func resumeSetup() {
        objectWillChange.send()
        if waitingForHomebrew && Dependencies.brew != nil && !setupBusy {
            waitingForHomebrew = false; installDependencyTools()
        }
    }

    func installRosetta() {
        guard !setupBusy else { return }
        setupBusy = true; setupMessage = "Installing Rosetta 2 using Apple's software updater…"; setupProgress = nil
        Task {
            defer { setupBusy = false }
            do {
                try await ProcessRunner.run(URL(fileURLWithPath: "/usr/sbin/softwareupdate"), ["--install-rosetta", "--agree-to-license"], directory: support, log: setupLog, label: "Rosetta setup")
                guard await SystemSetup.rosettaAvailable() else { throw RumError.message("Rosetta is not available yet. Check the setup log and Apple's installation instructions.") }
                setupMessage = "Rosetta 2 is ready. You can now download an engine."
            } catch { setupMessage = "Rosetta setup needs attention"; self.error = error.localizedDescription }
        }
    }

    func installDependency(_ dependency: WindowsDependency, entry: ShotglassEntry) {
        perform(entry, message: "Installing \(dependency.title)… Complete any installer dialogs that open.") {
            if Dependencies.winetricks == nil {
                await MainActor.run { self.messages[entry.id] = "Setting up Winetricks and extraction tools first…" }
                try await Dependencies.installTools(log: entry.log)
                await MainActor.run { self.messages[entry.id] = "Installing \(dependency.title)… Complete any installer dialogs that open." }
            }
            try await Dependencies.install(dependency, in: entry)
        }
    }

    func setDefaultLocation(_ url: URL) {
        do { var updated = catalog; updated.defaultLocation = url; try persist(updated) }
        catch { self.error = error.localizedDescription }
    }

    func importShotglass() {
        guard let folder = chooseFolder(prompt: "Import Shotglass") else { return }
        do {
            let shotglass = try Shotglass.load(from: folder)
            guard !entries.contains(where: { $0.id == shotglass.id }) else { throw RumError.message("This shotglass is already in your library.") }
            var updated = catalog
            let canonical = folder.resolvingSymlinksInPath()
            guard !updated.shotglassFolders.contains(where: { $0.resolvingSymlinksInPath() == canonical }) else { throw RumError.message("This folder is already registered. Refresh the library to reload it.") }
            updated.shotglassFolders.append(folder); try persist(updated)
            reload(); selection = shotglass.id
        } catch { self.error = error.localizedDescription }
    }

    func removeShotglass(_ entry: ShotglassEntry) {
        guard !busy.contains(entry.id) else { error = "Wait for this shotglass operation to finish before moving it to Trash."; return }
        guard catalog.shotglassFolders.contains(where: { $0.standardizedFileURL == entry.folder.standardizedFileURL }) else {
            error = "This shotglass is no longer registered. Refresh the library and try again."; return
        }
        do { try ShotglassFiles.validateForRemoval(entry) }
        catch { self.error = error.localizedDescription; return }

        busy.insert(entry.id)
        messages[entry.id] = "Stopping Windows processes and moving the shotglass to Trash…"
        Task {
            defer { busy.remove(entry.id) }
            do {
                if entry.shotglass.initialized { try await Wine.stopServer(entry) }
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: entry.folder, resultingItemURL: &trashedURL)
                guard let trashedURL else {
                    throw RumError.message("macOS moved the shotglass to Trash but did not report its new location, so Spiced-Rum could not safely update the library. Refresh the library to reconcile it.")
                }

                var updated = catalog
                updated.shotglassFolders.removeAll { $0.standardizedFileURL == entry.folder.standardizedFileURL }
                do { try persist(updated) }
                catch {
                    do { try FileManager.default.moveItem(at: trashedURL as URL, to: entry.folder) }
                    catch {
                        throw RumError.message("The library could not be updated, and the shotglass could not be restored from Trash. Its files remain at \(trashedURL). Original error: \(error.localizedDescription)")
                    }
                    throw error
                }

                entries.removeAll { $0.id == entry.id }
                messages.removeValue(forKey: entry.id)
                if selection == entry.id { selection = entries.first?.id }
            } catch {
                messages[entry.id] = "Removal needs attention"
                self.error = error.localizedDescription
            }
        }
    }

    func create(name: String, runtime: Runtime, graphics: Graphics, parent: URL, dxvk: URL?) throws -> ShotglassEntry {
        if graphics == .dxvk { try Wine.validateDXVK(dxvk ?? runtime.dxvkPackage) }
        let entry = try ShotglassFiles.create(Shotglass(name: name.trimmingCharacters(in: .whitespacesAndNewlines), runtime: runtime, graphics: graphics), parent: parent)
        do {
            var updated = catalog; updated.shotglassFolders.append(entry.folder); try persist(updated)
        } catch {
            // No Wine process has touched this newly created folder yet.
            try? FileManager.default.removeItem(at: entry.folder); throw error
        }
        entries.insert(entry, at: 0); selection = entry.id
        initialize(entry, dxvk: dxvk ?? runtime.dxvkPackage)
        return entry
    }

    func initialize(_ entry: ShotglassEntry, dxvk: URL?) {
        perform(entry, message: "Creating Windows x64 environment…") {
            let ready = try await Wine.initialize(entry, dxvk: dxvk)
            await MainActor.run {
                if let index = self.entries.firstIndex(where: { $0.id == entry.id }) { self.entries[index] = ready }
            }
        }
    }

    func run(_ entry: ShotglassEntry, executable: URL, launchArguments: [String] = []) {
        guard entry.shotglass.initialized else { error = "Initialize this shotglass before running an application."; return }
        guard FileManager.default.isReadableFile(atPath: executable.path), ["exe", "msi"].contains(executable.pathExtension.lowercased()) else {
            error = "Select a readable Windows .exe or .msi file."; return
        }
        if HeroicInstaller.isSetup(executable) {
            perform(entry, message: "Extracting Heroic directly and adding its shortcut…", successMessage: "Heroic was extracted into Program Files and added as a shortcut. Its setup dialog, Start menu entries, and uninstaller were skipped.") {
                let sevenZip = try await Dependencies.ensureSevenZip(log: entry.log)
                let installed = try await HeroicInstaller.extract(executable, into: entry, using: sevenZip)
                try await MainActor.run { try self.addProgram(entry, executable: installed) }
            }
            return
        }
        let args = executable.pathExtension.lowercased() == "msi"
            ? ["msiexec", "/i", executable.path]
            : [executable.path] + launchArguments
        perform(entry, message: "Preparing video support and launching…") {
            try await Wine.execute(runtime: entry.shotglass.runtime, arguments: args, environment: Wine.environment(for: entry), directory: executable.deletingLastPathComponent(), log: entry.log)
        }
    }

    func isSteam(_ program: Program) -> Bool {
        program.name.caseInsensitiveCompare("Steam") == .orderedSame || program.path.lowercased().hasSuffix("/steam.exe")
    }

    func changeHeroicUIWorkaround(_ enabled: Bool, for program: Program, in entry: ShotglassEntry) {
        guard program.isHeroicLauncher,
              let programIndex = entry.shotglass.programs.firstIndex(where: { $0.id == program.id }) else {
            error = "This shortcut is not a saved Heroic launcher. Add the Heroic executable to this shotglass, then retry."
            return
        }
        var updated = entry
        updated.shotglass.programs[programIndex].setHeroicUIWorkaround(enabled)
        do {
            try updated.shotglass.save(in: updated.folder)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = updated }
        } catch { self.error = error.localizedDescription }
    }

    func repairHeroicUI(for program: Program, in entry: ShotglassEntry) {
        guard program.isHeroicLauncher,
              let programIndex = entry.shotglass.programs.firstIndex(where: { $0.id == program.id }) else {
            error = "This shortcut is not a saved Heroic launcher. Add the Heroic executable to this shotglass, then retry."
            return
        }
        var updated = entry
        updated.shotglass.programs[programIndex].setHeroicUIWorkaround(true)
        do {
            try updated.shotglass.save(in: updated.folder)
            replaceEntry(updated)
        } catch {
            self.error = error.localizedDescription
            return
        }
        perform(updated, message: "Stopping Windows apps and clearing Heroic's UI cache…", successMessage: "Heroic's UI cache was cleared. Launch Heroic again.") {
            try await Wine.stopServer(updated)
            _ = try HeroicUICompatibility.clearGPUCache(in: updated)
        }
    }

    func steamFixState(_ program: Program, in entry: ShotglassEntry) -> SteamWebHelperCompatibility.State {
        guard isSteam(program), let helper = bundledSteamWebHelper(),
              let executable = try? ShotglassFiles.programURL(program, in: entry) else { return .inactive }
        return SteamWebHelperCompatibility.state(in: executable.deletingLastPathComponent(), wrapper: helper)
    }

    func changeSteamFix(_ enabled: Bool, for program: Program, in entry: ShotglassEntry) {
        guard isSteam(program), let helper = bundledSteamWebHelper(),
              let executable = try? ShotglassFiles.programURL(program, in: entry) else {
            error = "This Steam shortcut no longer points to a readable Windows steam.exe. Open Show files and check the shortcut path."
            return
        }
        let steamDirectory = executable.deletingLastPathComponent()
        let success = enabled
            ? "Steam's black-window fix is enabled. Steam client auto-updates are paused until you remove the fix."
            : "Steam's original web helper and update setting have been restored. Steam can update its client again."
        perform(entry, message: enabled ? "Stopping Steam and enabling its interface fix…" : "Stopping Steam and restoring its original interface…", successMessage: success) {
            try await Wine.stopServer(entry)
            if enabled {
                try SteamWebHelperCompatibility.enable(in: steamDirectory, wrapper: helper)
            } else {
                _ = try SteamWebHelperCompatibility.disable(in: steamDirectory)
            }
        }
    }

    private func bundledSteamWebHelper() -> URL? {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("ThirdParty/steamwebhelper-wrapper.exe")
        if let packaged, FileManager.default.isReadableFile(atPath: packaged.path) { return packaged }
#if DEBUG
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/ThirdParty/steamwebhelper-wrapper.exe")
        return FileManager.default.isReadableFile(atPath: source.path) ? source : nil
#else
        return nil
#endif
    }

    func configure(_ entry: ShotglassEntry) {
        perform(entry, message: "Wine configuration open…") {
            try await Wine.execute(runtime: entry.shotglass.runtime, arguments: ["winecfg"], environment: Wine.environment(for: entry), directory: entry.folder, log: entry.log)
        }
    }

    func forceStop(_ entry: ShotglassEntry) {
        guard !stopping.contains(entry.id) else { return }
        stopping.insert(entry.id)
        messages[entry.id] = "Force-stopping Windows processes…"
        Task {
            defer { stopping.remove(entry.id) }
            do {
                try await Wine.stopServer(entry)
                messages[entry.id] = "All Windows processes in this shotglass were stopped."
            } catch {
                messages[entry.id] = "Needs attention"
                self.error = error.localizedDescription
            }
        }
    }

    func perform(_ entry: ShotglassEntry, message: String, successMessage: String = "Wine command completed", allowRecovery: Bool = false, action: @escaping () async throws -> Void) {
        guard !busy.contains(entry.id) else { return }
        guard allowRecovery || !entry.engineChangePending else { error = "An engine change was interrupted. Open Change engine and restore a backup before using this shotglass."; return }
        busy.insert(entry.id); messages[entry.id] = message
        Task {
            defer { busy.remove(entry.id) }
            do { try await action(); messages[entry.id] = successMessage }
            catch { messages[entry.id] = "Needs attention"; self.error = error.localizedDescription }
        }
    }

    func changeEngine(_ entry: ShotglassEntry, to runtime: Runtime) {
        perform(entry, message: "Preparing engine change…") {
            let updated = try await ShotglassEngines.change(entry, to: runtime) { message in
                Task { @MainActor in self.messages[entry.id] = message }
            }
            await MainActor.run { self.replaceEntry(updated) }
        }
    }

    func changeGraphics(_ entry: ShotglassEntry, to graphics: Graphics) {
        perform(entry, message: "Switching graphics and stopping this shotglass's Windows processes…", successMessage: "Graphics changed to \(graphics.rawValue).") {
            let updated = try await ShotglassGraphics.change(entry, to: graphics)
            await MainActor.run { self.replaceEntry(updated) }
        }
    }

    func restoreEngineBackup(_ backup: EngineBackup, entry: ShotglassEntry) {
        perform(entry, message: "Restoring the engine and Windows environment…", allowRecovery: true) {
            let restored = try await ShotglassEngines.restore(backup, to: entry)
            await MainActor.run { self.replaceEntry(restored) }
        }
    }

    private func replaceEntry(_ entry: ShotglassEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
    }

    func saveProgram(_ entry: ShotglassEntry, executable: URL) {
        do { try addProgram(entry, executable: executable) }
        catch { self.error = error.localizedDescription }
    }

    private func addProgram(_ entry: ShotglassEntry, executable: URL) throws {
        guard executable.pathExtension.lowercased() == "exe" else { throw RumError.message("Select a Windows .exe for a saved application.") }
        var updated = entry
        let path = ShotglassFiles.programPath(executable, in: entry)
        guard !updated.shotglass.programs.contains(where: { $0.path == path }) else { return }
        var program = Program(name: executable.deletingPathExtension().lastPathComponent, path: path)
        if program.isHeroicLauncher { program.setHeroicUIWorkaround(true) }
        updated.shotglass.programs.append(program)
        try updated.shotglass.save(in: updated.folder)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = updated }
    }

    func removeProgram(_ program: Program, from entry: ShotglassEntry) {
        do {
            var updated = entry; updated.shotglass.programs.removeAll { $0.id == program.id }
            try updated.shotglass.save(in: updated.folder)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = updated }
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
func chooseFolder(prompt: String, initial: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
    panel.prompt = prompt; panel.directoryURL = initial
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseFile(prompt: String, extensions: [String] = [], initial: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.showsHiddenFiles = true
    panel.prompt = prompt; panel.directoryURL = initial
    if !extensions.isEmpty { panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) } }
    return panel.runModal() == .OK ? panel.url : nil
}

import UniformTypeIdentifiers
