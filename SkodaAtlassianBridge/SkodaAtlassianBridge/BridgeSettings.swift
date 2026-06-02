import Foundation
import Combine

/// Persisted user configuration. Stores base URLs for each Atlassian service
/// (Jira, Confluence/Wiki) that the bridge will proxy requests to. URLs are
/// editable from the Settings window.
final class BridgeSettings: ObservableObject {
    @Published var jiraBaseURL: String {
        didSet { UserDefaults.standard.set(jiraBaseURL, forKey: Keys.jiraBaseURL) }
    }

    @Published var wikiBaseURL: String {
        didSet { UserDefaults.standard.set(wikiBaseURL, forKey: Keys.wikiBaseURL) }
    }

    init() {
        self.jiraBaseURL = UserDefaults.standard.string(forKey: Keys.jiraBaseURL)
            ?? "https://jira.skoda.vwgroup.com"
        self.wikiBaseURL = UserDefaults.standard.string(forKey: Keys.wikiBaseURL)
            ?? "https://wiki.skoda.vwgroup.com"
    }

    var jiraURL: URL? { Self.normalize(jiraBaseURL) }
    var wikiURL: URL? { Self.normalize(wikiBaseURL) }

    /// Used by the IPC layer to resolve a service name from a `/fetch` request
    /// into a configured base URL. Names are case-insensitive; accepts both
    /// `wiki` and `confluence` for the Confluence instance.
    func baseURL(for service: String) -> URL? {
        switch service.lowercased() {
        case "jira":                  return jiraURL
        case "wiki", "confluence":    return wikiURL
        default:                      return nil
        }
    }

    /// Canonical list of services advertised in /services and the UI.
    var configuredServices: [(name: String, url: URL?)] {
        [("jira", jiraURL), ("wiki", wikiURL)]
    }

    private static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty,
              let url = URL(string: s),
              let scheme = url.scheme, scheme.hasPrefix("http"),
              url.host != nil
        else { return nil }
        return url
    }

    private enum Keys {
        static let jiraBaseURL = "settings.jiraBaseURL"
        static let wikiBaseURL = "settings.wikiBaseURL"
    }
}
