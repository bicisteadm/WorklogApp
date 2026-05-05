import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var detail: String
    @Relationship(deleteRule: .cascade, inverse: \Ticket.project) var tickets: [Ticket] = []
    @Relationship(deleteRule: .cascade, inverse: \Iteration.project) var iterations: [Iteration] = []

    init(name: String, detail: String = "") {
        self.name = name
        self.detail = detail
    }
}
