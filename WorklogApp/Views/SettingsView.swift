import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bridge: JiraBridge
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
            jiraTab
                .tabItem { Label("Jira", systemImage: "link") }
        }
        .scenePadding()
        .frame(width: 540, height: 380)
    }

    private var jiraTab: some View {
        Form {
            Section {
                LabeledContent("Server URL") {
                    TextField("", text: $settings.jiraBaseURL,
                              prompt: Text("https://jira.example.com"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(minWidth: 320)
                }

                if settings.baseURL == nil && !settings.jiraBaseURL.isEmpty {
                    Text("Doesn't look like a valid URL — needs scheme + host (e.g. `https://jira.example.com`).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Jira")
            } footer: {
                Text("The app will open this server in an embedded browser window so you can sign in normally (F5 / SSO / MFA). The session cookies are then reused for API calls inside the app — your password is never stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                connectionStatusRow

                HStack(spacing: 8) {
                    Button {
                        openWindow(id: WindowIDs.jiraLogin)
                    } label: {
                        Label(connectButtonLabel, systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(settings.baseURL == nil)

                    Button {
                        Task { await bridge.validate() }
                    } label: {
                        Label("Test", systemImage: "stethoscope")
                    }
                    .disabled(settings.baseURL == nil)

                    Spacer()

                    if case .connected = bridge.state {
                        Button(role: .destructive) {
                            Task { await bridge.disconnect() }
                        } label: {
                            Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var connectButtonLabel: String {
        if case .connected = bridge.state { return "Re-authenticate…" }
        return "Connect…"
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch bridge.state {
        case .unknown:
            statusRow(text: "Not yet checked", icon: "circle", color: .secondary)
        case .checking:
            statusRow(text: "Checking…", icon: "ellipsis.circle", color: .secondary)
        case .connected(let name, let lastChecked):
            statusRow(
                text: "Connected as \(name) (last checked \(Self.relativeTime.localizedString(for: lastChecked, relativeTo: Date())))",
                icon: "checkmark.circle.fill",
                color: .green
            )
        case .disconnected:
            statusRow(text: "Not signed in", icon: "person.crop.circle.badge.exclamationmark", color: .orange)
        case .error(let msg):
            statusRow(text: msg, icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func statusRow(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(color)
        }
    }

    private static let relativeTime: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
