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
                VStack(alignment: .leading, spacing: 4) {
                    LoginDiagnosticEditor(text: bridge.navDelegate.diagnosticLog.joined(separator: "\n"))
                        .frame(height: 140)
                    HStack {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(bridge.navDelegate.diagnosticLogText(), forType: .string)
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
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
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
    static let reports = "reports"
}

/// Read-only NSTextView wrapper for the login window's diagnostic panel.
/// (Same trick as in SettingsView — Cmd-A/Cmd-C works reliably here.)
private struct LoginDiagnosticEditor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
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
