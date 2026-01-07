import Foundation
import SwiftData

@Model
final class Ticket {
    @Attribute(.unique) var ticketId: String
    var name: String
    var detail: String
    var startDate: Date
    var dueDate: Date?
    var project: Project?
    var iteration: Iteration?
    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.ticket) var entries: [TimeEntry] = []

    init(ticketId: String, name: String, detail: String, startDate: Date = Date(), dueDate: Date? = nil, project: Project? = nil, iteration: Iteration? = nil) {
        self.ticketId = ticketId
        self.name = name
        self.detail = detail
        self.startDate = startDate
        self.dueDate = dueDate
        self.project = project
        self.iteration = iteration
    }
}
