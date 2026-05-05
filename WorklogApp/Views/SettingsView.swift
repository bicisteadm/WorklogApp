import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bridge: JiraBridge
    @Environment(\.openWindow) private var openWindow
    @State private var showDiagnostics = false

    var body: some View {
        TabView {
            jiraTab
                .tabItem { Label("Jira", systemImage: "link") }
        }
        .scenePadding()
        .frame(width: 620, height: showDiagnostics ? 580 : 420)
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

            Section {
                Toggle("Show diagnostic log", isOn: $showDiagnostics)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(bridge.navDelegate.lastEvent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if showDiagnostics {
                    diagnosticPanel
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiagnosticLogEditor(
                text: bridge.navDelegate.diagnosticLog.joined(separator: "\n")
            )
            .frame(height: 160)

            HStack {
                Button {
                    let text = bridge.navDelegate.diagnosticLogText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy log", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(bridge.navDelegate.diagnosticLog.isEmpty)

                Button {
                    bridge.navDelegate.clearDiagnosticLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(bridge.navDelegate.diagnosticLog.isEmpty)

                Spacer()

                Text("\(bridge.navDelegate.diagnosticLog.count) line(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

/// Read-only NSTextView wrapper. `Text` + `.textSelection(.enabled)` works
/// erratically inside Form / ScrollView, so we drop to AppKit for a reliable
/// Cmd-A / Cmd-C experience and auto-scroll-to-bottom.
private struct DiagnosticLogEditor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false

        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textColor = .systemGreen
            textView.backgroundColor = NSColor.black.withAlphaComponent(0.9)
            textView.drawsBackground = true
            textView.usesFontPanel = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.string = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToEndOfDocument(nil)
        }
    }
}
