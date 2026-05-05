import Foundation
import WebKit
import Combine
import Security
import SecurityInterface
import AppKit

/// Bridges the app to Jira **without using the public REST API** that the company
/// has disabled. Instead it embeds a single `WKWebView` whose `WKWebsiteDataStore`
/// carries the user's authenticated session cookies (F5 / SSO / Jira). API calls
/// are made by `callAsyncJavaScript` running `fetch()` *inside the page context*,
/// so F5 sees a normal authenticated browser request.
///
/// **Strictly on-demand** — there is no background watchdog or periodic ping.
/// `validate()` runs only when:
///   - the user clicks "Test" in Settings,
///   - the login window is open and we're polling for the user to finish sign-in,
///   - we're about to perform a real API operation (caller's responsibility).
///
/// This keeps our request profile minimal: the server only sees calls that
/// match a real user action.
@MainActor
final class JiraBridge: ObservableObject {
    enum ConnectionState: Equatable {
        case unknown
        case checking
        case connected(displayName: String, lastChecked: Date)
        case disconnected
        case error(String)
    }

    @Published private(set) var state: ConnectionState = .unknown

    /// The single shared WKWebView. Used for both the login window UI and headless
    /// `fetch()` calls afterwards. Only one parent at a time, but it stays alive in
    /// memory regardless of whether it's currently embedded in a window.
    let webView: WKWebView

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    /// Retained navigation delegate that handles client-cert (mTLS) auth challenges
    /// and accumulates diagnostic events. Surface this in the login window so the
    /// user can see exactly what's happening when something silently fails.
    let navDelegate = MTLSNavigationDelegate()

    init(settings: AppSettings) {
        self.settings = settings

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // persists cookies across launches
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = navDelegate
        self.webView = webView

        // Re-validate whenever the user changes the Jira URL.
        settings.$jiraBaseURL
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

    // MARK: - Public API

    /// Make sure the WebView has a Jira-origin document loaded so subsequent
    /// `fetch()` calls work as same-origin requests. Idempotent.
    func prepareForUse() async {
        guard let baseURL = settings.baseURL else {
            state = .error("Set Jira URL in Settings")
            return
        }
        if let current = webView.url, current.host == baseURL.host {
            return // already on Jira
        }
        await load(URLRequest(url: baseURL))
    }

    /// One-shot validation: hit `/rest/api/2/myself` from the current page context
    /// and translate the result into `state`. Uses `callAsyncJavaScript` instead
    /// of `evaluateJavaScript` because the async overload of the latter trips on
    /// "unsupported type" when the resolved Promise contains certain values
    /// (null/undefined inside an object). `callAsyncJavaScript` is designed
    /// specifically for async function bodies returning Promises and bridges
    /// the result cleanly.
    func validate() async {
        guard let baseURL = settings.baseURL else {
            state = .error("Set Jira URL in Settings")
            return
        }
        state = .checking
        navDelegate.log("validate: webView at \(webView.url?.absoluteString ?? "about:blank")")

        // Function body for callAsyncJavaScript — note: NO IIFE wrapper; just
        // statements and `return` directly. The runtime treats this as an async
        // function body.
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
               let body = dict["fullBody"] as? String,
               let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = (json["displayName"] as? String)
                    ?? (json["name"] as? String)
                    ?? "Jira user"
                state = .connected(displayName: name, lastChecked: Date())
            } else {
                state = .disconnected
            }
        } catch {
            navDelegate.log("validate: JS exception: \(error.localizedDescription)")
            state = .disconnected
        }
    }

    /// Used by the login window: navigate to Jira and poll `validate()` every few
    /// seconds until the user successfully signs in (or the task is cancelled).
    func startLoginFlow() {
        cancelPolling()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareForUse()
            for _ in 0..<200 { // ~10 minutes max
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

    /// Wipe cookies + cache so the next login flow starts from a clean slate.
    func disconnect() async {
        cancelPolling()

        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)

        // Load about:blank so the next prepareForUse() definitely re-loads Jira.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        state = .disconnected
    }

    // MARK: - Generic API access

    enum JiraAPIError: LocalizedError {
        case notConnected
        case unauthorized
        case notConfigured
        case http(Int, String)
        case malformed(String)
        case scriptError(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:    return "Not connected to Jira. Open Settings → Connect."
            case .unauthorized:    return "Jira session expired. Re-authenticate in Settings."
            case .notConfigured:   return "Jira URL not set in Settings."
            case .http(let code, let preview):
                return "Jira returned HTTP \(code): \(preview)"
            case .malformed(let m): return "Unexpected response: \(m)"
            case .scriptError(let m): return "JS bridge error: \(m)"
            }
        }
    }

    /// GET a Jira REST endpoint as JSON, decoded into `T`. Path is everything
    /// after the host (e.g. `/rest/api/2/myself` or `/rest/api/2/search?jql=...`).
    /// Runs `fetch()` inside the WebView's page context — cookies, F5, CSRF
    /// are all handled by the live browser session.
    func getJSON<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        try await fetchJSON(path: path, method: "GET", body: nil, decode: T.self)
    }

    /// POST a JSON body to a Jira REST endpoint, decoding the response.
    func postJSON<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request,
        as: Response.Type = Response.self
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        let bodyString = String(data: data, encoding: .utf8) ?? "{}"
        return try await fetchJSON(path: path, method: "POST", body: bodyString, decode: Response.self)
    }

    private func fetchJSON<T: Decodable>(
        path: String,
        method: String,
        body: String?,
        decode: T.Type
    ) async throws -> T {
        guard settings.baseURL != nil else { throw JiraAPIError.notConfigured }

        // Pass path/body as arguments so we don't have to escape into JS source.
        var args: [String: Any] = [
            "path": path,
            "method": method
        ]
        if let body { args["body"] = body }

        let js = """
        try {
          const opts = {
            method: method,
            credentials: 'include',
            redirect: 'follow',
            headers: {
              'Accept': 'application/json',
              'X-Atlassian-Token': 'no-check',
              'X-Requested-With': 'XMLHttpRequest'
            }
          };
          if (typeof body !== 'undefined') {
            opts.body = body;
            opts.headers['Content-Type'] = 'application/json';
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
            navDelegate.log("API \(method) \(path): JS error: \(error.localizedDescription)")
            throw JiraAPIError.scriptError(error.localizedDescription)
        }

        guard let dict = raw as? [String: Any] else {
            throw JiraAPIError.malformed("non-object JS result")
        }
        if (dict["ok"] as? Bool) != true {
            let err = (dict["error"] as? String) ?? "unknown"
            navDelegate.log("API \(method) \(path): fetch failed: \(err)")
            throw JiraAPIError.scriptError(err)
        }

        let status = (dict["status"] as? Int) ?? 0
        let bodyText = (dict["body"] as? String) ?? ""

        navDelegate.log("API \(method) \(path) → \(status) (\(bodyText.count) bytes)")

        if status == 401 || status == 403 {
            state = .disconnected
            throw JiraAPIError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw JiraAPIError.http(status, String(bodyText.prefix(200)))
        }
        guard let data = bodyText.data(using: .utf8) else {
            throw JiraAPIError.malformed("non-UTF8 body")
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            navDelegate.log("API \(method) \(path): decode error: \(error)")
            throw JiraAPIError.malformed("decode: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal helpers

    private func load(_ request: URLRequest) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            navDelegate.onceOnNextNavigationFinish { cont.resume() }
            webView.load(request)
        }
    }

}

// MARK: - Navigation delegate

/// Permanent navigation delegate for the bridge's WebView. Handles:
///
///   1. **Client-certificate (mTLS) auth challenges** — by default WKWebView
///      ignores user identities in the system Keychain. We respond by enumerating
///      identities relevant to the protection space and either picking the only
///      match automatically or showing a native picker (`SFChooseIdentityPanel`).
///
///   2. **One-shot navigation-finished callback** — used by `JiraBridge.load(_:)`
///      to `await` a single page load without thrashing the delegate slot.
///
///   3. **Diagnostics** — every navigation lifecycle event and every auth
///      challenge is appended to `diagnosticLog` and observable via
///      `lastEvent`, surfaced in the login window status bar.
final class MTLSNavigationDelegate: NSObject, WKNavigationDelegate, ObservableObject {
    private var pendingFinishCallback: (() -> Void)?

    /// Most recent human-readable diagnostic line (current URL, error, auth
    /// challenge, etc.). Updated on the main thread.
    @Published private(set) var lastEvent: String = "Idle"

    /// Cumulative diagnostic log — newest line last, capped at ~200 entries.
    @Published private(set) var diagnosticLog: [String] = []

    func log(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        DispatchQueue.main.async {
            self.lastEvent = message
            self.diagnosticLog.append(line)
            if self.diagnosticLog.count > 200 {
                self.diagnosticLog.removeFirst(self.diagnosticLog.count - 200)
            }
            print("JiraBridge: \(line)") // also visible in Console.app via stderr
        }
    }

    /// Plain-text snapshot of the full diagnostic log, for clipboard / sharing.
    @MainActor
    func diagnosticLogText() -> String {
        diagnosticLog.joined(separator: "\n")
    }

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
    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    @MainActor
    func onceOnNextNavigationFinish(_ block: @escaping () -> Void) {
        // Replace any prior pending callback — the new awaiter wins.
        pendingFinishCallback = block
    }

    // MARK: Auth challenges (mTLS)

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
            // Server cert (kSecTrust), HTTP basic, NTLM, etc. — let the system handle it.
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
            // No certs found — fall back to default (server may not actually require client cert).
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Single identity — use it directly. Multiple — show picker.
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

    /// Pull every `SecIdentity` (= cert + private key pair) the user has installed
    /// in their default Keychain. F5 will request a specific issuer in
    /// `acceptableIssuers`; we still hand the full list to the picker so the user
    /// can pick anything if their cert isn't auto-matched.
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

    // MARK: Navigation lifecycle

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

// MARK: - JS string escaping

/// Escape a Swift string so it can be embedded as a JavaScript string literal.
private func jsString(_ s: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
    let json = String(data: data, encoding: .utf8) ?? "[]"
    // JSONSerialization always wraps a string in an array; strip the outer brackets.
    return String(json.dropFirst().dropLast())
}
