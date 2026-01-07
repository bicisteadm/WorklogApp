import Foundation
import SwiftData

@Model
final class TimeEntry {
    var hours: Double
    var loggedAt: Date
    var ticket: Ticket?
    var note: String?

    init(hours: Double, loggedAt: Date = Date(), ticket: Ticket? = nil, note: String? = nil) {
        self.hours = hours
        self.loggedAt = loggedAt
        self.ticket = ticket
        self.note = note
    }
}
