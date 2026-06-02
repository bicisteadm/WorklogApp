import SwiftUI
import WebKit

/// Login window — hosts the shared `WKWebView` so the user can complete the
/// SSO/F5 flow against Jira (cookies then also work for Confluence/Wiki since
/// it's the same SSO realm). Diagnostics panel shows the navigation log
/// from `MTLSNavigationDelegate` for troubleshooting.
struct LoginWindowContent: View {
    @EnvironmentObject var session: AtlassianSession
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            WebViewHost(webView: session.webView)
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 500, idealHeight: 600)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(session.navDelegate.lastEvent)
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
                DiagnosticPanel(text: session.navDelegate.diagnosticLog.joined(separator: "\n"),
                                onCopy: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.navDelegate.diagnosticLogText(), forType: .string)
                                },
                                onClear: { session.navDelegate.clearDiagnosticLog() },
                                lineCount: session.navDelegate.diagnosticLog.count)
            }

            Divider()

            HStack(spacing: 12) {
                statusBadge

                Spacer()

                Button {
                    session.startLoginFlow()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Button("Done") {
                    dismissWindow(id: WindowIDs.login)
                }
                .keyboardShortcut(.cancelAction)

                if case .connected = session.state {
                    Button("Close") {
                        dismissWindow(id: WindowIDs.login)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
        .onAppear { session.startLoginFlow() }
        .onDisappear { session.cancelPolling() }
        .onChange(of: session.state) { _, newValue in
            if case .connected = newValue {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if case .connected = session.state {
                        dismissWindow(id: WindowIDs.login)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.state {
        case .unknown:       label("Loading…", icon: "ellipsis.circle", color: .secondary)
        case .checking:      label("Checking session…", icon: "ellipsis.circle", color: .secondary)
        case .connected(let name, _):
            label("Connected as \(name)", icon: "checkmark.circle.fill", color: .green)
        case .disconnected:  label("Sign in via the page above", icon: "person.crop.circle.badge.exclamationmark", color: .orange)
        case .error(let msg): label(msg, icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline).foregroundStyle(color)
        }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct DiagnosticPanel: View {
    let text: String
    let onCopy: () -> Void
    let onClear: () -> Void
    let lineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DiagnosticEditor(text: text)
                .frame(height: 140)
            HStack {
                Button {
                    onCopy()
                } label: {
                    Label("Copy log", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(lineCount == 0)

                Button {
                    onClear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(lineCount == 0)

                Spacer()
                Text("\(lineCount) line(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

private struct DiagnosticEditor: NSViewRepresentable {
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

enum WindowIDs {
    static let login = "login"
}
