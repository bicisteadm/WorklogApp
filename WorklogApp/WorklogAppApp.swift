import SwiftUI
import SwiftData
import AppKit

/// Activation-policy owner. Two transitions:
///
/// 1. Cold launch → `.regular`. SwiftUI's `WindowGroup` auto-creates the main
///    window (because we're a regular Dock app with no LSUIElement). Window
///    visible, Dock icon visible.
///
/// 2. User closes the last window (red X / Cmd-W) → `.accessory`. Dock icon
///    disappears, app keeps running for the menu bar item. The SwiftUI
///    `WindowGroup` window is destroyed; reopening recreates it.
///
/// 3. Menu bar "Open" → MenuBarContentView calls `openWindow(id: "main")`
///    from SwiftUI Environment (closure-captured at view evaluation), AND
///    triggers `WindowOpener.bringForward()` for activation + .regular flip.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    /// Last window closed → become menu-bar-only. Keep process alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    /// Dock-icon click while .regular and window not visible. The MenuBar button
    /// is the primary path; this is a fallback.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowOpener.bringForward()
        }
        return true
    }
}

// MARK: - Window forwarding

/// Helpers for the menu bar "Open" path. The caller must hand us the SwiftUI
/// `openWindow` action captured from its `@Environment` — that's the only way
/// to materialize a `WindowGroup` window after it's been closed.
enum WindowOpener {
    /// Bring an already-existing main window forward. Does nothing if no window
    /// exists. (For the "no window" case, the caller posts `openWindow(id:)`
    /// first; SwiftUI will create the window, then we bring it forward.)
    @MainActor
    static func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// Find the first regular titled non-panel window. SwiftUI's WindowGroup
    /// windows match this.
    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.canBecomeKey
                && !(window is NSPanel)
                && window.styleMask.contains(.titled)
        }
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
            #if DEBUG
            let dbFile = "WorklogApp-Dev.sqlite"
            #else
            let dbFile = "WorklogApp.sqlite"
            #endif
            let dbURL = URL.applicationSupportDirectory.appendingPathComponent(dbFile)
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

        Window("Time Reports", id: WindowIDs.reports) {
            ReportsView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 720)
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
            #if DEBUG
            Text("DEV")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
            #endif
            if timerState.isRunning {
                Text(formatDuration(timerState.elapsed))
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        #if DEBUG
        return timerState.isRunning ? (timerState.isPaused ? "hammer.circle" : "hammer.fill") : "hammer"
        #else
        guard timerState.isRunning else { return "clock" }
        return timerState.isPaused ? "pause.circle" : "timer"
        #endif
    }
}

