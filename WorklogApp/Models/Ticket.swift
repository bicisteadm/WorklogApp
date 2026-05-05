import Foundation
import SwiftData

@Model
final class Ticket {
    var ticketId: String
    var name: String
    var detail: String
    var startDate: Date
    var dueDate: Date?
    var project: Project?
    var iteration: Iteration?

    /// True when the ticket was created by the Jira importer. Imported tickets
    /// are read-only in the UI — fields are refreshed by re-syncing, not edited.
    var isImported: Bool = false
    /// Atlassian's stable numeric issue ID (more durable than `ticketId`/key,
    /// which can change if an issue is moved between projects).
    var jiraIssueId: String?
    /// Time of the last successful sync from Jira for this ticket.
    var jiraLastSync: Date?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.ticket) var entries: [TimeEntry] = []

    init(ticketId: String = "",
         name: String,
         detail: String,
         startDate: Date = Date(),
         dueDate: Date? = nil,
         project: Project? = nil,
         iteration: Iteration? = nil,
         isImported: Bool = false,
         jiraIssueId: String? = nil) {
        self.ticketId = ticketId
        self.name = name
        self.detail = detail
        self.startDate = startDate
        self.dueDate = dueDate
        self.project = project
        self.iteration = iteration
        self.isImported = isImported
        self.jiraIssueId = jiraIssueId
    }
}
