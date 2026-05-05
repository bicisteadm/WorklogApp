import Foundation
import SwiftData

// MARK: - Text helpers

import AppKit

enum JiraText {
    /// Strip HTML tags down to plain text. Used for fields that must be a single
    /// line / plain (the issue summary). Description fields are kept raw and
    /// rendered via `attributed(from:)` instead.
    static func plainText(from raw: String?) -> String {
        guard var s = raw, !s.isEmpty else { return "" }

        let replacements: [(String, String)] = [
            ("<br/>", "\n"), ("<br />", "\n"), ("<br>", "\n"),
            ("</p>", "\n\n"), ("</div>", "\n\n"),
            ("</li>", "\n"), ("<li>", "  • "),
            ("</tr>", "\n"), ("</td>", "\t")
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&laquo;", "«"), ("&raquo;", "»"), ("&copy;", "©"), ("&reg;", "®")
        ]
        for (from, to) in entities {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = decodeNumericEntities(s)

        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse Jira's HTML-rendered description into an `AttributedString` for
    /// SwiftUI display — preserves bold, italics, links, lists. Returns nil if
    /// the input isn't HTML or parsing fails.
    @MainActor
    static func attributed(from raw: String?) -> AttributedString? {
        guard let raw, !raw.isEmpty else { return nil }
        // Quick gate: not worth invoking the HTML parser if there are clearly no tags.
        let containsTag = raw.range(of: "<[a-zA-Z/!][^>]*>", options: .regularExpression) != nil
        guard containsTag else { return nil }

        guard let data = raw.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let nsAttr = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        // The HTML parser injects fonts (often Times) and absolute colors (black)
        // that look out of place. Strip them so the rendered text inherits the
        // SwiftUI environment's font and adapts to dark mode automatically.
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        nsAttr.removeAttribute(.foregroundColor, range: fullRange)
        nsAttr.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont else { return }
            // Preserve bold/italic traits, drop family + size.
            let traits = font.fontDescriptor.symbolicTraits
            let baseSize = NSFont.systemFontSize
            var newFont = NSFont.systemFont(ofSize: baseSize)
            if traits.contains(.bold) {
                newFont = NSFont.boldSystemFont(ofSize: baseSize)
            }
            if traits.contains(.italic) {
                if let italic = NSFontManager.shared.font(withFamily: newFont.familyName ?? "",
                                                          traits: NSFontTraitMask.italicFontMask,
                                                          weight: 5,
                                                          size: baseSize) {
                    newFont = italic
                }
            }
            nsAttr.addAttribute(.font, value: newFont, range: range)
        }
        // Trim trailing whitespace/newlines that the HTML parser appends.
        while nsAttr.length > 0,
              let last = nsAttr.string.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) {
            nsAttr.deleteCharacters(in: NSRange(location: nsAttr.length - 1, length: 1))
        }

        return try? AttributedString(nsAttr, including: \.appKit)
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        var result = s
        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
        for m in matches.reversed() {
            guard m.numberOfRanges >= 2 else { continue }
            let token = nsString.substring(with: m.range(at: 1))
            let scalarValue: UInt32?
            if token.hasPrefix("x") || token.hasPrefix("X") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { continue }
            let replacement = String(scalar)
            result = (result as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return result
    }
}

// MARK: - Jira REST DTOs

/// Minimal subset of `/rest/api/2/search` response we care about.
struct JiraSearchResponse: Decodable {
    let total: Int
    let startAt: Int
    let maxResults: Int
    let issues: [JiraIssue]
}

struct JiraIssue: Decodable {
    let id: String
    let key: String
    let fields: JiraIssueFields

    /// Raw extra fields (sprint custom field comes through here, name varies).
    /// Decoded via dynamic CodingKeys — see init(from:).
    let raw: [String: JSONValue]

    private enum FixedKeys: String, CodingKey {
        case id, key, fields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FixedKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.key = try c.decode(String.self, forKey: .key)
        self.fields = try c.decode(JiraIssueFields.self, forKey: .fields)

        // Re-decode `fields` as a dynamic dict so we can pick up arbitrary
        // customfield_XXXXX values (sprint, etc.) without hardcoding names.
        let fieldsContainer = try c.decode([String: JSONValue].self, forKey: .fields)
        self.raw = fieldsContainer
    }
}

/// Fields we always want, by name. Other fields (sprint custom field) come
/// through `JiraIssue.raw` because their key depends on the Jira instance.
struct JiraIssueFields: Decodable {
    let summary: String?
    let description: String?
    let duedate: String?  // "YYYY-MM-DD" or nil
    let updated: String?  // ISO8601 with offset
}

/// One entry returned by `/rest/api/2/field` — used to discover which
/// `customfield_XXXXX` carries the sprint reference.
struct JiraField: Decodable {
    let id: String
    let name: String
    let custom: Bool
    let schema: Schema?

    struct Schema: Decodable {
        let type: String?
        let custom: String?    // e.g. "com.pyxis.greenhopper.jira:gh-sprint"
        let customId: Int?
    }
}

/// Permissive JSON value decoder — tolerates anything Jira throws.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var asArray: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var asObject: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var asInt: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }
}

// MARK: - Sprint extraction from issue

/// One sprint reference extracted from an issue's sprint custom field. Newer
/// Jira returns these as JSON objects; older versions return strings like
/// `com.atlassian.greenhopper.service.sprint.Sprint@1234[id=42,name=Sprint 7,state=ACTIVE,startDate=…,endDate=…]`.
struct ExtractedSprint {
    let id: String
    let name: String
    let state: String       // ACTIVE | FUTURE | CLOSED | unknown
    let startDate: Date?
    let endDate: Date?
}

enum SprintParser {
    /// Take whatever Jira returned in the sprint custom field and produce sprint refs.
    static func parse(_ value: JSONValue?) -> [ExtractedSprint] {
        guard let value, let arr = value.asArray else { return [] }
        return arr.compactMap { item in
            switch item {
            case .object(let o): return parseObject(o)
            case .string(let s): return parseLegacyString(s)
            default: return nil
            }
        }
    }

    private static func parseObject(_ o: [String: JSONValue]) -> ExtractedSprint? {
        guard let idAny = o["id"], let name = o["name"]?.asString else { return nil }
        let idStr: String
        if let n = idAny.asInt { idStr = String(n) }
        else if let s = idAny.asString { idStr = s }
        else { return nil }
        return ExtractedSprint(
            id: idStr,
            name: name,
            state: (o["state"]?.asString ?? "unknown").uppercased(),
            startDate: parseDate(o["startDate"]?.asString),
            endDate: parseDate(o["endDate"]?.asString) ?? parseDate(o["completeDate"]?.asString)
        )
    }

    private static func parseLegacyString(_ s: String) -> ExtractedSprint? {
        // Format: com....Sprint@hash[k=v,k=v,...]
        guard let bracketStart = s.firstIndex(of: "["),
              let bracketEnd = s.lastIndex(of: "]")
        else { return nil }
        let inside = s[s.index(after: bracketStart)..<bracketEnd]
        var dict: [String: String] = [:]
        for pair in inside.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            dict[String(kv[0]).trimmingCharacters(in: .whitespaces)] =
                String(kv[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let id = dict["id"], let name = dict["name"] else { return nil }
        return ExtractedSprint(
            id: id,
            name: name,
            state: (dict["state"] ?? "unknown").uppercased(),
            startDate: parseDate(dict["startDate"]),
            endDate: parseDate(dict["endDate"]) ?? parseDate(dict["completeDate"])
        )
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty, s != "<null>" else { return nil }
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static let formatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]
        return patterns.map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = $0
            return f
        }
    }()
}

// MARK: - Importer

@MainActor
final class JiraImporter: ObservableObject {
    enum Phase: Equatable {
        case idle
        case discoveringSprintField
        case fetching(page: Int, totalSoFar: Int, total: Int?)
        case applying(processed: Int, total: Int)
        case finished(Summary)
        case failed(String)
    }

    struct Summary: Equatable {
        var ticketsCreated = 0
        var ticketsUpdated = 0
        var sprintsCreated = 0
        var sprintsUpdated = 0
        var fetched = 0
        var errors: [String] = []
    }

    @Published private(set) var phase: Phase = .idle

    private let bridge: JiraBridge

    init(bridge: JiraBridge) {
        self.bridge = bridge
    }

    /// Run the full sync against `project`. The project must be saved (have an ID),
    /// have a non-empty `jiraJQL`, and the bridge must be connected.
    func sync(project: Project, in context: ModelContext) async {
        guard project.isJiraSynced else {
            phase = .failed("Project has no JQL configured.")
            return
        }
        if case .connected = bridge.state {} else {
            phase = .failed("Not connected to Jira.")
            return
        }

        var summary = Summary()

        // 1) Resolve sprint custom field once per project (cached on Project).
        let sprintFieldId: String?
        if let cached = project.jiraSprintFieldId, !cached.isEmpty {
            sprintFieldId = cached
        } else {
            phase = .discoveringSprintField
            do {
                let fields = try await bridge.getJSON("/rest/api/2/field", as: [JiraField].self)
                let sprintField = fields.first { $0.schema?.custom == "com.pyxis.greenhopper.jira:gh-sprint" }
                sprintFieldId = sprintField?.id
                if let f = sprintFieldId {
                    project.jiraSprintFieldId = f
                    try? context.save()
                }
            } catch {
                summary.errors.append("Couldn't list Jira fields: \(error.localizedDescription)")
                sprintFieldId = nil
            }
        }

        // 2) Build the field list to request: standard ones + sprint if known.
        var fieldsParam = ["summary", "description", "duedate", "updated"]
        if let sf = sprintFieldId { fieldsParam.append(sf) }
        let fieldsCSV = fieldsParam.joined(separator: ",")

        // 3) Paginated search.
        let pageSize = 100
        var startAt = 0
        var allIssues: [JiraIssue] = []

        while true {
            phase = .fetching(page: (startAt / pageSize) + 1, totalSoFar: allIssues.count, total: nil)

            let escapedJQL = project.jiraJQL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? project.jiraJQL
            let path = "/rest/api/2/search?jql=\(escapedJQL)&fields=\(fieldsCSV)&startAt=\(startAt)&maxResults=\(pageSize)"

            let response: JiraSearchResponse
            do {
                response = try await bridge.getJSON(path, as: JiraSearchResponse.self)
            } catch {
                phase = .failed("Search failed at page \(startAt / pageSize + 1): \(error.localizedDescription)")
                return
            }

            allIssues.append(contentsOf: response.issues)
            phase = .fetching(page: (startAt / pageSize) + 1, totalSoFar: allIssues.count, total: response.total)

            startAt += response.issues.count
            if startAt >= response.total || response.issues.isEmpty { break }
        }

        summary.fetched = allIssues.count

        // 4) Apply: upsert sprints (iterations) and tickets.
        var sprintCache: [String: Iteration] = [:] // jiraSprintId → iteration

        // Pre-load existing iterations + tickets for this project.
        let projectIterations = project.iterations
        let projectTickets = project.tickets

        for (idx, issue) in allIssues.enumerated() {
            phase = .applying(processed: idx, total: allIssues.count)

            // Sprint resolution
            var iteration: Iteration? = nil
            if let sf = sprintFieldId, let sprintFieldValue = issue.raw[sf] {
                let sprints = SprintParser.parse(sprintFieldValue)
                // Take the most recent (last) — issue can carry historical refs.
                if let sprint = sprints.last {
                    if let cached = sprintCache[sprint.id] {
                        iteration = cached
                    } else if let existing = projectIterations.first(where: { $0.jiraSprintId == sprint.id }) {
                        // Refresh fields if Jira has more recent info
                        var dirty = false
                        if existing.name != sprint.name { existing.name = sprint.name; dirty = true }
                        if let s = sprint.startDate, existing.startDate != s { existing.startDate = s; dirty = true }
                        if let e = sprint.endDate, existing.dueDate != e { existing.dueDate = e; dirty = true }
                        if existing.jiraSprintState != sprint.state {
                            existing.jiraSprintState = sprint.state
                            // Auto-archive when Jira closes the sprint.
                            if sprint.state == "CLOSED" && !existing.isArchived {
                                existing.isArchived = true
                            }
                            dirty = true
                        }
                        if dirty { summary.sprintsUpdated += 1 }
                        sprintCache[sprint.id] = existing
                        iteration = existing
                    } else {
                        // Create new iteration
                        let start = sprint.startDate ?? Date()
                        let end = sprint.endDate ?? Calendar.current.date(byAdding: .weekOfYear, value: 2, to: start) ?? start
                        let new = Iteration(
                            name: sprint.name,
                            type: .sprint,
                            startDate: start,
                            dueDate: end,
                            project: project,
                            isArchived: sprint.state == "CLOSED",
                            jiraSprintId: sprint.id,
                            jiraSprintState: sprint.state
                        )
                        context.insert(new)
                        sprintCache[sprint.id] = new
                        iteration = new
                        summary.sprintsCreated += 1
                    }
                }
            }

            // Ticket upsert (match by Jira issue key — that's what we put in ticketId).
            // Summary stays plain (single-line title); description preserves
            // raw HTML so the detail view can render it formatted.
            let summary_ = JiraText.plainText(from: issue.fields.summary)
            let detail = issue.fields.description ?? ""
            let dueDate: Date? = parseISODateOnly(issue.fields.duedate)

            if let existing = projectTickets.first(where: { $0.ticketId == issue.key }) {
                // Update only if it's an imported one — never silently overwrite a manual ticket
                // that happens to share a key.
                if existing.isImported {
                    existing.name = summary_
                    existing.detail = detail
                    existing.dueDate = dueDate
                    existing.iteration = iteration
                    existing.jiraIssueId = issue.id
                    existing.jiraLastSync = Date()
                    summary.ticketsUpdated += 1
                } else {
                    summary.errors.append("Skipped \(issue.key): already exists locally as a manually-created ticket.")
                }
            } else {
                let ticket = Ticket(
                    ticketId: issue.key,
                    name: summary_,
                    detail: detail,
                    startDate: Date(),
                    dueDate: dueDate,
                    project: project,
                    iteration: iteration,
                    isImported: true,
                    jiraIssueId: issue.id
                )
                ticket.jiraLastSync = Date()
                context.insert(ticket)
                summary.ticketsCreated += 1
            }
        }

        project.lastJiraSync = Date()

        do {
            try context.save()
        } catch {
            summary.errors.append("Save failed: \(error.localizedDescription)")
        }

        phase = .finished(summary)
    }

    private func parseISODateOnly(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
