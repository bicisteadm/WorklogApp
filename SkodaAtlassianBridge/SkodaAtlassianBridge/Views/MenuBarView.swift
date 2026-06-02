import SwiftUI

/// Dropdown shown from the menu bar icon. Compact summary + actions:
/// sign in, open settings, copy IPC token, quit.
struct MenuBarView: View {
    @EnvironmentObject var session: AtlassianSession
    @EnvironmentObject var settings: BridgeSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            stateRow
            Divider()

            Button("Sign in…") {
                openWindow(id: WindowIDs.login)
                activate()
            }

            Button("Settings…") {
                if #available(macOS 14.0, *) {
                    NSApp.activate()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Divider()

            Button("Copy API token") {
                let token = TokenStore.getOrCreate()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(token, forType: .string)
            }

            Button("Validate session now") {
                Task { @MainActor in await session.validate() }
            }

            Divider()

            Button("Quit SkodaAtlassianBridge") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var stateRow: some View {
        switch session.state {
        case .unknown:
            Text("Not validated yet")
        case .checking:
            Text("Checking session…")
        case .connected(let name, _):
            Text("Connected as \(name)")
        case .disconnected:
            Text("Disconnected — sign in")
        case .error(let msg):
            Text("Error: \(msg)")
        }
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
