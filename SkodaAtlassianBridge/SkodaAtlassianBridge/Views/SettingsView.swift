import SwiftUI

/// Settings window — edit per-service base URLs, see auth state, manage the
/// local API token, and kick off login or disconnect.
struct SettingsView: View {
    @EnvironmentObject var settings: BridgeSettings
    @EnvironmentObject var session: AtlassianSession
    @Environment(\.openWindow) private var openWindow
    @State private var revealToken = false

    var body: some View {
        Form {
            Section("Services") {
                LabeledContent("Jira URL") {
                    TextField("https://jira.example.com", text: $settings.jiraBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                LabeledContent("Wiki URL") {
                    TextField("https://wiki.example.com", text: $settings.wikiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                if settings.jiraURL == nil {
                    invalidLabel("Jira URL is empty or malformed")
                }
                if settings.wikiURL == nil {
                    invalidLabel("Wiki URL is empty or malformed")
                }
            }

            Section("Authentication") {
                LabeledContent("Status") {
                    statusBadge
                }
                HStack {
                    Button("Sign in…") {
                        openWindow(id: WindowIDs.login)
                    }
                    Button("Validate now") {
                        Task { @MainActor in await session.validate() }
                    }
                    Button("Disconnect") {
                        Task { @MainActor in await session.disconnect() }
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("Local API") {
                LabeledContent("Socket path") {
                    Text(BridgeSocket.path)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Token") {
                    HStack {
                        if revealToken {
                            Text(TokenStore.getOrCreate())
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(String(repeating: "•", count: 20))
                                .foregroundStyle(.secondary)
                        }
                        Button(revealToken ? "Hide" : "Reveal") {
                            revealToken.toggle()
                        }
                        .controlSize(.small)
                        Button("Copy") {
                            let token = TokenStore.getOrCreate()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(token, forType: .string)
                        }
                        .controlSize(.small)
                        Button("Rotate") {
                            TokenStore.delete()
                            _ = TokenStore.getOrCreate()
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
                Text("Clients authenticate by sending `Authorization: Bearer <token>` on every request. Rotating invalidates existing clients — they will read the new value from the Keychain on next call.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 480)
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.state {
        case .unknown:
            label("Not validated yet", icon: "questionmark.circle", color: .secondary)
        case .checking:
            label("Checking…", icon: "ellipsis.circle", color: .secondary)
        case .connected(let name, let date):
            label("Connected as \(name) · \(date.formatted(date: .omitted, time: .shortened))",
                  icon: "checkmark.circle.fill", color: .green)
        case .disconnected:
            label("Disconnected", icon: "person.crop.circle.badge.exclamationmark", color: .orange)
        case .error(let msg):
            label(msg, icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func invalidLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(.orange)
        }
    }
}
