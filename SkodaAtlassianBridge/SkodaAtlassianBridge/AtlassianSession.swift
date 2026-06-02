import Foundation
import WebKit
import Combine
import Security
import SecurityInterface
import AppKit

/// One authenticated WebKit session shared across all Atlassian services
/// (Jira, Confluence/Wiki) that sit behind the same F5/SSO. A single
/// `WKWebView` carries cookies; per-request we make sure the page is on the
/// right origin before running `fetch()` inside its context.
///
/// **All API requests funnel through `fetch(service:path:method:headers:body:)`**
/// — IPC handlers call into here. Validation hits Jira's `/rest/api/2/myself`
/// as the primary signal of "session is alive" because all services share auth.
@MainActor
final class AtlassianSession: ObservableObject {
    enum ConnectionState: Equatable {
        case unknown
        case checking
        case connected(displayName: String, lastChecked: Date)
        case disconnected
        case error(String)
    }

    @Published private(set) var state: ConnectionState = .unknown

    let webView: WKWebView
    let navDelegate = MTLSNavigationDelegate()

    private let settings: BridgeSettings
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    init(settings: BridgeSettings) {
        self.settings = settings

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = navDelegate
        self.webView = webView

        // Reset state if either configured URL changes; user will need to re-validate.
        Publishers.CombineLatest(settings.$jiraBaseURL, settings.$wikiBaseURL)
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancelPolling()
                    self?.state = .unknown
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API used by IPC + UI

    /// Make sure the WebView is sitting on a Jira-origin document so the next
    /// validation/fetch picks up the right cookies. Same-origin loads are no-ops.
    func prepareForJira() async {
        guard let url = settings.jiraURL else {
            state = .error("Set Jira URL in Settings")
            return
        }
        await ensureOrigin(of: url)
    }

    /// Run `/rest/api/2/myself` from the current Jira page context; promote the
    /// session state to `.connected` on a JSON 200, otherwise `.disconnected`.
    func validate() async {
        guard let baseURL = settings.jiraURL else {
            state = .error("Set Jira URL in Settings")
            return
        }
        state = .checking
        await ensureOrigin(of: baseURL)
        navDelegate.log("validate: webView at \(webView.url?.absoluteString ?? "about:blank")")

        let body = """
        const cookieCount = (document.cookie || '').split(';').filter(Boolean).length;
        try {
          const r = await fetch('/rest/api/2/myself', {
            credentials: 'include',
            redirect: 'follow',
            headers: {
              'Accept': 'application/json',
              'X-Atlassian-Token': 'no-check',
              'X-Requested-With': 'XMLHttpRequest'
            }
          });
          const text = await r.text();
          return {
            ok: true,
            status: r.status,
            finalURL: String(r.url || ''),
            contentType: String(r.headers.get('content-type') || ''),
            bodyPreview: text.substring(0, 240),
            fullBody: text,
            location: String(location.href || ''),
            cookieCount: cookieCount
          };
        } catch (e) {
          return {
            ok: false,
            error: String(e && e.message || e),
            location: String(location.href || ''),
            cookieCount: cookieCount
          };
        }
        """

        do {
            let raw = try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
            guard let dict = raw as? [String: Any] else {
                navDelegate.log("validate: callAsyncJS returned \(String(describing: type(of: raw)))")
                state = .disconnected
                return
            }

            let location = (dict["location"] as? String) ?? "?"
            let cookieCount = (dict["cookieCount"] as? Int) ?? 0
            let ok = (dict["ok"] as? Bool) ?? false

            if !ok {
                let err = (dict["error"] as? String) ?? "unknown"
                navDelegate.log("validate: fetch error: \(err) (cookies=\(cookieCount), at=\(location))")
                state = .disconnected
                return
            }

            let status = (dict["status"] as? Int) ?? 0
            let finalURL = (dict["finalURL"] as? String) ?? "?"
            let ctype = (dict["contentType"] as? String) ?? ""
            let preview = (dict["bodyPreview"] as? String) ?? ""
            navDelegate.log("validate: \(status) → \(finalURL) ct=\(ctype) cookies=\(cookieCount)")
            if !preview.isEmpty {
                navDelegate.log("body: \(preview.replacingOccurrences(of: "\n", with: " ").prefix(180))")
            }

            if status == 200,
               ctype.contains("application/json"),
               let bodyText = dict["fullBody"] as? String,
               let data = bodyText.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = (json["displayName"] as? String)
                    ?? (json["name"] as? String)
                    ?? "Atlassian user"
                state = .connected(displayName: name, lastChecked: Date())
            } else {
                state = .disconnected
            }
        } catch {
            navDelegate.log("validate: JS exception: \(error.localizedDescription)")
            state = .disconnected
        }
    }

    func startLoginFlow() {
        cancelPolling()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareForJira()
            for _ in 0..<200 {
                if Task.isCancelled { return }
                await self.validate()
                if case .connected = self.state {
                    return
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Wipe cookies + cache so the next login flow starts fresh for all services.
    func disconnect() async {
        cancelPolling()
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        state = .disconnected
    }

    // MARK: - Generic authenticated fetch (the public IPC API)

    struct FetchResult {
        let status: Int
        let contentType: String
        let body: String
    }

    enum FetchError: LocalizedError {
        case unknownService(String)
        case notConfigured(String)
        case invalidPath(String)
        case scriptError(String)
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .unknownService(let s): return "Unknown service '\(s)'. Configured: jira, wiki."
            case .notConfigured(let s):  return "Service '\(s)' has no base URL configured."
            case .invalidPath(let p):    return "Invalid path '\(p)' (must start with '/')."
            case .scriptError(let m):    return "JS bridge error: \(m)"
            case .malformed(let m):      return "Malformed response: \(m)"
            }
        }
    }

    /// Runs `fetch(path, opts)` inside the WebView page context for the given
    /// service. The page is loaded for the service's origin first if needed so
    /// cookies are scoped correctly.
    func fetch(
        service: String,
        path: String,
        method: String,
        headers: [String: String],
        body: String?
    ) async throws -> FetchResult {
        guard let baseURL = settings.baseURL(for: service) else {
            if settings.baseURL(for: service) == nil &&
               !["jira", "wiki", "confluence"].contains(service.lowercased()) {
                throw FetchError.unknownService(service)
            }
            throw FetchError.notConfigured(service)
        }
        guard path.hasPrefix("/") else { throw FetchError.invalidPath(path) }

        await ensureOrigin(of: baseURL)

        var mergedHeaders: [String: String] = [
            "Accept": "application/json",
            "X-Atlassian-Token": "no-check",
            "X-Requested-With": "XMLHttpRequest"
        ]
        for (k, v) in headers { mergedHeaders[k] = v }
        if body != nil && mergedHeaders["Content-Type"] == nil {
            mergedHeaders["Content-Type"] = "application/json"
        }

        var args: [String: Any] = [
            "path": path,
            "method": method.uppercased(),
            "headers": mergedHeaders
        ]
        if let body { args["body"] = body }

        let js = """
        try {
          const opts = {
            method: method,
            credentials: 'include',
            redirect: 'follow',
            headers: headers
          };
          if (typeof body !== 'undefined') {
            opts.body = body;
          }
          const r = await fetch(path, opts);
          const text = await r.text();
          return {
            ok: true,
            status: r.status,
            contentType: String(r.headers.get('content-type') || ''),
            body: text
          };
        } catch (e) {
          return { ok: false, error: String(e && e.message || e) };
        }
        """

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page)
        } catch {
            navDelegate.log("fetch \(service) \(method) \(path): JS error: \(error.localizedDescription)")
            throw FetchError.scriptError(error.localizedDescription)
        }

        guard let dict = raw as? [String: Any] else {
            throw FetchError.malformed("non-object JS result")
        }
        if (dict["ok"] as? Bool) != true {
            let err = (dict["error"] as? String) ?? "unknown"
            navDelegate.log("fetch \(service) \(method) \(path): \(err)")
            throw FetchError.scriptError(err)
        }
        let status = (dict["status"] as? Int) ?? 0
        let ctype = (dict["contentType"] as? String) ?? ""
        let bodyText = (dict["body"] as? String) ?? ""
        navDelegate.log("fetch \(service) \(method) \(path) → \(status) (\(bodyText.count) bytes)")
        if status == 401 || status == 403 {
            state = .disconnected
        }
        return FetchResult(status: status, contentType: ctype, body: bodyText)
    }

    // MARK: - Internals

    private func ensureOrigin(of url: URL) async {
        if let current = webView.url, current.host == url.host, current.scheme == url.scheme {
            return
        }
        await load(URLRequest(url: url))
    }

    private func load(_ request: URLRequest) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            navDelegate.onceOnNextNavigationFinish { cont.resume() }
            webView.load(request)
        }
    }
}

// MARK: - Navigation delegate (mTLS + diagnostics)

/// Same role as in WorklogApp's JiraBridge: handles client-cert auth challenges
/// the system would otherwise drop, and exposes a rolling diagnostic log for
/// the login window.
final class MTLSNavigationDelegate: NSObject, WKNavigationDelegate, ObservableObject {
    private var pendingFinishCallback: (() -> Void)?

    @Published private(set) var lastEvent: String = "Idle"
    @Published private(set) var diagnosticLog: [String] = []

    func log(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        DispatchQueue.main.async {
            self.lastEvent = message
            self.diagnosticLog.append(line)
            if self.diagnosticLog.count > 200 {
                self.diagnosticLog.removeFirst(self.diagnosticLog.count - 200)
            }
            print("SkodaAtlassianBridge: \(line)")
        }
    }

    @MainActor
    func diagnosticLogText() -> String { diagnosticLog.joined(separator: "\n") }

    @MainActor
    func clearDiagnosticLog() {
        diagnosticLog.removeAll()
        lastEvent = "Idle"
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static func timestamp() -> String { timestampFormatter.string(from: Date()) }

    @MainActor
    func onceOnNextNavigationFinish(_ block: @escaping () -> Void) {
        pendingFinishCallback = block
    }

    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        log("auth challenge: \(space.authenticationMethod) @ \(space.host):\(space.port)")
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertChallenge(host: space.host,
                                      acceptableIssuers: space.distinguishedNames,
                                      completionHandler: completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func handleClientCertChallenge(
        host: String,
        acceptableIssuers: [Data]?,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let identities = Self.findClientIdentities()
        guard !identities.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if identities.count == 1 {
            let credential = URLCredential(identity: identities[0], certificates: nil, persistence: .forSession)
            completionHandler(.useCredential, credential)
            return
        }
        DispatchQueue.main.async {
            guard let panel = SFChooseIdentityPanel.shared() else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            panel.setAlternateButtonTitle("Cancel")
            let result = panel.runModal(
                forIdentities: identities,
                message: "Choose a certificate to authenticate to \(host)"
            )
            if result == NSApplication.ModalResponse.OK.rawValue,
               let chosen = panel.identity()?.takeUnretainedValue() {
                let credential = URLCredential(identity: chosen, certificates: nil, persistence: .forSession)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    private static func findClientIdentities() -> [SecIdentity] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return [] }
        return (result as? [SecIdentity]) ?? []
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log("→ \(webView.url?.absoluteString ?? "?")")
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        log("redirect → \(webView.url?.absoluteString ?? "?")")
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        log("loading \(webView.url?.absoluteString ?? "?")")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("✓ loaded \(webView.url?.absoluteString ?? "?")")
        firePendingCallback()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("✗ failed: \(error.localizedDescription)")
        firePendingCallback()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("✗ provisional failed: \(error.localizedDescription)")
        firePendingCallback()
    }

    private func firePendingCallback() {
        guard let block = pendingFinishCallback else { return }
        pendingFinishCallback = nil
        block()
    }
}
