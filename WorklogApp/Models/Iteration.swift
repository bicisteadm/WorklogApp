import Foundation
import SwiftData

@Model
final class Iteration {
    var name: String
    var type: IterationType
    var startDate: Date
    var dueDate: Date
    /// Archived iterations stay in the database and remain accessible via the
    /// "Archived" sidebar section, but their tickets are hidden from
    /// project-wide / "All" listings and from new-ticket pickers.
    var isArchived: Bool = false

    /// If imported from Jira, this is the Jira sprint ID. Used as the dedup key
    /// when re-running the importer.
    var jiraSprintId: String?
    /// Last known Jira sprint state ("ACTIVE" / "FUTURE" / "CLOSED"). CLOSED
    /// sprints are auto-archived on import.
    var jiraSprintState: String?

    var project: Project?
    @Relationship(deleteRule: .nullify, inverse: \Ticket.iteration) var tickets: [Ticket] = []

    init(name: String,
         type: IterationType,
         startDate: Date,
         dueDate: Date,
         project: Project? = nil,
         isArchived: Bool = false,
         jiraSprintId: String? = nil,
         jiraSprintState: String? = nil) {
        self.name = name
        self.type = type
        self.startDate = startDate
        self.dueDate = dueDate
        self.project = project
        self.isArchived = isArchived
        self.jiraSprintId = jiraSprintId
        self.jiraSprintState = jiraSprintState
    }
}

enum IterationType: String, Codable, CaseIterable {
    case sprint = "Sprint"
    case milestone = "Milestone"
}
