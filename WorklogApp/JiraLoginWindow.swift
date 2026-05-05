import SwiftUI
import WebKit

/// Content of the "Connect to Jira" window. Hosts the bridge's `WKWebView`
/// so the user can log in (F5 / SSO / MFA all happen here in a real browser
/// engine), and displays a status bar at the bottom that flips to "Connected"
/// the moment a `/rest/api/2/myself` poll succeeds.
struct JiraLoginWindowContent: View {
    @EnvironmentObject var bridge: JiraBridge
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            JiraWebViewRepresentable(webView: bridge.webView)
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 500, idealHeight: 600)

            Divider()

            // Live diagnostic line — most recent navigation/auth event
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(bridge.navDelegate.lastEvent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Toggle("Diagnostics", isOn: $showDiagnostics)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            if showDiagnostics {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(bridge.navDelegate.diagnosticLog.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 140)
                    .background(Color.black.opacity(0.85))
                    .foregroundStyle(.green)
                    .onChange(of: bridge.navDelegate.diagnosticLog.count) { _, count in
                        if count > 0 {
                            withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                connectionStatusBadge

                Spacer()

                Button {
                    bridge.startLoginFlow()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Button("Done") {
                    dismissWindow(id: WindowIDs.jiraLogin)
                }
                .keyboardShortcut(.cancelAction)

                if case .connected = bridge.state {
                    Button("Close") {
                        dismissWindow(id: WindowIDs.jiraLogin)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
        .onAppear {
            bridge.startLoginFlow()
        }
        .onDisappear {
            bridge.cancelPolling()
        }
        .onChange(of: bridge.state) { _, newValue in
            // Auto-close after a short delay once we detect a successful login,
            // so the user gets visual confirmation before the window goes away.
            if case .connected = newValue {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if case .connected = bridge.state {
                        dismissWindow(id: WindowIDs.jiraLogin)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch bridge.state {
        case .unknown:
            statusLabel("Loading…", icon: "ellipsis.circle", color: .secondary)
        case .checking:
            statusLabel("Checking session…", icon: "ellipsis.circle", color: .secondary)
        case .connected(let name, _):
            statusLabel("Connected as \(name)", icon: "checkmark.circle.fill", color: .green)
        case .disconnected:
            statusLabel("Sign in via the page above", icon: "person.crop.circle.badge.exclamationmark", color: .orange)
        case .error(let msg):
            statusLabel(msg, icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func statusLabel(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(color)
        }
    }
}

/// SwiftUI host for an existing `WKWebView`. We pass the bridge's shared
/// instance in so cookies + navigation history persist beyond this window.
private struct JiraWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Window ID registry

enum WindowIDs {
    static let main = "main"
    static let jiraLogin = "jiraLogin"
}
