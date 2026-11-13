import AppKit
import SwiftUI

@main
struct EventMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Event Monitor", id: "main") {
            ContentView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
                .frame(minWidth: 920, minHeight: 540)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Veranstaltungen") {
                Button("Jetzt aktualisieren") { Task { await model.scan() } }
                    .keyboardShortcut("r")
                    .disabled(model.isScanning)
                Button("Filter zurücksetzen") { model.resetFilters() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(\.locale, Fmt.locale)
        }
    }
}

/// Sorgt dafür, dass die App auch beim Start per `swift run` ein normales Fenster mit Dock-Symbol bekommt.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
