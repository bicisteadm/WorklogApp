import SwiftUI
import SwiftData
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, but window can still be made key/active.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // When the user clicks the (hidden) Dock icon or activates from elsewhere.
        WindowOpener.bringMainToFront()
        return true
    }
}

@main
struct WorklogAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer
    @StateObject private var timerState = TimerState()
    @StateObject private var settings: AppSettings
    @StateObject private var jiraBridge: JiraBridge

    init() {
        do {
            let schema = Schema([Project.self, Ticket.self, TimeEntry.self, Iteration.self])
            let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")
            let config = ModelConfiguration(schema: schema, url: dbURL)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        // Bridge needs the same AppSettings instance the rest of the app reads.
        // Build both here so we share the reference; @StateObject preserves it
        // across re-inits of the App struct.
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _jiraBridge = StateObject(wrappedValue: JiraBridge(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(timerState: timerState)
        } label: {
            MenuBarLabel(timerState: timerState)
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(modelContainer)

        WindowGroup(id: WindowIDs.main) {
            ContentView(timerState: timerState)
                .frame(minWidth: 800, minHeight: 600)
                .background(WindowConfigurator())
                .environmentObject(settings)
                .environmentObject(jiraBridge)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WorklogApp") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(jiraBridge)
        }

        Window("Connect to Jira", id: WindowIDs.jiraLogin) {
            JiraLoginWindowContent()
                .environmentObject(settings)
                .environmentObject(jiraBridge)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
    }
}

// MARK: - Menu bar label

/// The label shown in the system menu bar. Re-renders once per second when running —
/// fine because it's a single tiny view. Avoid `Text(timerInterval:)` here: with
/// `Date.distantFuture` as the upper bound it causes a runaway snapshot loop in the
/// `MenuBarExtra` label slot and freezes the app.
private struct MenuBarLabel: View {
    @ObservedObject var timerState: TimerState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if timerState.isRunning {
                Text(formatDuration(timerState.elapsed))
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        guard timerState.isRunning else { return "clock" }
        return timerState.isPaused ? "pause.circle" : "timer"
    }
}

// MARK: - Window configuration & activation

/// Attaches a one-shot configurator to the main window: stable autosave name +
/// behaviors that ensure the window appears on the *current* Space when summoned.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.setFrameAutosaveName("MainWindow")
            // Allow the window to follow the user across Spaces. Without this,
            // clicking the menu bar from another desktop opens the window on
            // the *original* Space and looks broken.
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.isReleasedWhenClosed = false
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Centralized "show the main window" logic. Handles every quirk of running
/// `.accessory` activation policy (hidden Dock icon): activates the app, picks
/// the existing main window if one exists, deminiaturizes, and finally calls
/// `makeKeyAndOrderFront` on the *active Space*.
enum WindowOpener {
    static func bringMainToFront(openWindow: OpenWindowAction? = nil) {
        // Modern, non-deprecated activation. Replaces NSApp.activate(ignoringOtherApps:).
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        if let window = mainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // No window yet (rare — only if the user explicitly closed it and we lost the ref).
        // Use SwiftUI's openWindow if we have it; otherwise we can't materialize a WindowGroup
        // from AppDelegate context, so just leave the app activated — the next click opens it.
        openWindow?(id: "main")
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.canBecomeKey
                && !(window is NSPanel)
                && window.styleMask.contains(.titled)
        }
    }
}
