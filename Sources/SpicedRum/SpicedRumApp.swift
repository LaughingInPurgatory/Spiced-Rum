import SwiftUI
import AppKit

@main
struct SpicedRumApp: App {
    @StateObject private var store = LibraryStore()
    init() {
        if let iconURL = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    var body: some Scene {
        WindowGroup("Spiced-Rum") {
            LibraryView().environmentObject(store)
                .frame(minWidth: 960, minHeight: 660)
                .tint(.orange)
                .preferredColorScheme(.dark)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Spiced-Rum") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: "Developed by Laughing In Purgatory")
                    ])
                }
            }
        }

        Window("Settings", id: "settings") {
            SetupView().environmentObject(store)
                .frame(minWidth: 760, minHeight: 620)
                .tint(.orange)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 820)
    }
}
