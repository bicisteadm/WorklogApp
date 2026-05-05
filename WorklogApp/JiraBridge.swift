import Foundation
import WebKit
import Combine

/// Bridges the app to Jira **without using the public REST API** that the company
/// has disabled. Instead it embeds a single `WKWebView` whose `WKWebsiteDataStore`
/// carries the user's authenticated session cookies (F5 / SSO / Jira). API calls
/// are made by `evaluateJavaScript` running `fetch()` *inside the page context*,
/// so F5 sees a normal authenticated browser request.
///
/// Lifecycle:
///   1. `prepareForUse()` loads the Jira homepage so a document context exists.
///   2. `validate()` runs `fetch('/rest/api/2/myself')` and updates `state`.
///   3. While disconnected during a login flow, `pollUntilConnected()` retries
///      every few seconds so the UI flips to "connected" automatically when
///      the user finishes signing in.
///   4. A 5-min watchdog re-validates in the background after first success.
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
    private var watchdogTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // persists cookies across launches
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
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
    /// and translate the result into `state`.
    func validate() async {
        guard let baseURL = settings.baseURL else {
            state = .error("Set Jira URL in Settings")
            return
        }
        state = .checking

        let endpoint = baseURL.appendingPathComponent("rest/api/2/myself").absoluteString
        let js = """
        (async () => {
          try {
            const r = await fetch(\(jsString(endpoint)), {
              credentials: 'include',
              headers: { 'Accept': 'application/json' }
            });
            const text = await r.text();
            return { status: r.status, body: text, finalURL: r.url };
          } catch (e) {
            return { status: 0, error: String(e) };
          }
        })()
        """

        do {
            let result = try await webView.evaluateJavaScript(js)
            guard let dict = result as? [String: Any], let status = dict["status"] as? Int else {
                state = .disconnected
                return
            }

            // Login redirects through F5/SSO often return 200 with a login page,
            // not 401, so also check the body.
            if status == 200,
               let body = dict["body"] as? String,
               let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = (json["displayName"] as? String)
                    ?? (json["name"] as? String)
                    ?? "Jira user"
                state = .connected(displayName: name, lastChecked: Date())
                startWatchdog()
            } else {
                state = .disconnected
            }
        } catch {
            // Cross-origin redirect during SSO / page not yet loaded → treat as not yet.
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
        watchdogTimer?.invalidate()
        watchdogTimer = nil

        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)

        // Load about:blank so the next prepareForUse() definitely re-loads Jira.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        state = .disconnected
    }

    // MARK: - Internal helpers

    private func load(_ request: URLRequest) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let observer = NavigationObserver { cont.resume() }
            webView.navigationDelegate = observer
            // Retain observer until callback fires.
            objc_setAssociatedObject(webView, &Self.navObserverKey, observer, .OBJC_ASSOCIATION_RETAIN)
            webView.load(request)
        }
    }

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        // Re-check session every 5 minutes once we've been connected at least once.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.validate() }
        }
    }

    private static var navObserverKey: UInt8 = 0
}

// MARK: - Navigation observer

/// Calls back exactly once when the next navigation either finishes or fails,
/// so we can `await` a `webView.load()` cleanly. We don't keep the delegate
/// installed past that — JavaScript-driven page loads (login redirects) are
/// driven by the user's interaction in the login window, not by us.
private final class NavigationObserver: NSObject, WKNavigationDelegate {
    private var didFire = false
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fireOnce()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fireOnce()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fireOnce()
    }

    private func fireOnce() {
        guard !didFire else { return }
        didFire = true
        onFinish()
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
