import Foundation
import Combine

/// User-configurable settings persisted to `UserDefaults`.
final class AppSettings: ObservableObject {
    @Published var jiraBaseURL: String {
        didSet {
            UserDefaults.standard.set(jiraBaseURL, forKey: Keys.jiraBaseURL)
        }
    }

    init() {
        self.jiraBaseURL = UserDefaults.standard.string(forKey: Keys.jiraBaseURL)
            ?? "https://jira.skoda.vwgroup.com"
    }

    /// Trimmed/validated base URL — `nil` if empty or malformed.
    var baseURL: URL? {
        var raw = jiraBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme, scheme.hasPrefix("http"),
              url.host != nil
        else { return nil }
        return url
    }

    private enum Keys {
        static let jiraBaseURL = "settings.jiraBaseURL"
    }
}
