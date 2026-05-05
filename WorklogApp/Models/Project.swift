import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var detail: String

    /// JQL filter used to pull issues from Jira into this project. Empty = sync disabled.
    var jiraJQL: String = ""
    /// Cached ID of the Jira custom field that holds the sprint reference for issues
    /// in this project (e.g. "customfield_10020"). Auto-detected on first sync.
    var jiraSprintFieldId: String?
    /// Last successful sync timestamp; nil = never synced.
    var lastJiraSync: Date?

    @Relationship(deleteRule: .cascade, inverse: \Ticket.project) var tickets: [Ticket] = []
    @Relationship(deleteRule: .cascade, inverse: \Iteration.project) var iterations: [Iteration] = []

    init(name: String, detail: String = "", jiraJQL: String = "") {
        self.name = name
        self.detail = detail
        self.jiraJQL = jiraJQL
    }

    var isJiraSynced: Bool {
        !jiraJQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
