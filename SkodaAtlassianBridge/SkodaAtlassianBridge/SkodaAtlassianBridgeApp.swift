import SwiftUI
import AppKit

/// Resolves the canonical socket path the bridge listens on. Clients use the
/// same path — keep this constant in sync if you ship a client SDK.
enum BridgeSocket {
    static var path: String {
        let dir = ("~/Library/Application Support/SkodaAtlassianBridge" as NSString)
            .expandingTildeInPath
        return (dir as NSString).appendingPathComponent("bridge.sock")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var server: UnixSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}

@main
struct SkodaAtlassianBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings: BridgeSettings
    @StateObject private var session: AtlassianSession

    init() {
        let s = BridgeSettings()
        let sess = AtlassianSession(settings: s)
        _settings = StateObject(wrappedValue: s)
        _session = StateObject(wrappedValue: sess)

        // Ensure the API token exists before any client could connect.
        let token = TokenStore.getOrCreate()

        // The router uses MainActor isolation because it talks to the session;
        // we hop onto it from the socket handler thread via the `Task` inside
        // UnixSocketServer.runHandlerBlocking.
        let router = BridgeRouter(session: sess, settings: s)
        let server = UnixSocketServer(socketPath: BridgeSocket.path, token: token) { req in
            await router.handle(req)
        }
        do {
            try server.start()
            appDelegate.server = server
        } catch {
            NSLog("SkodaAtlassianBridge: failed to start socket server: %@", "\(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(settings)
                .environmentObject(session)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(session)
        }

        Window("Sign in to Atlassian", id: WindowIDs.login) {
            LoginWindowContent()
                .environmentObject(session)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
    }

    private var menuBarIcon: String {
        switch session.state {
        case .connected: return "lock.shield.fill"
        case .checking:  return "lock.shield"
        case .error:     return "exclamationmark.shield"
        default:         return "lock.shield"
        }
    }
}
