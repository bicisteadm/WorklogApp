import Foundation
import SwiftData

@Model
final class Iteration {
    var name: String
    var type: IterationType
    var startDate: Date
    var dueDate: Date
    
    var project: Project?
    @Relationship(deleteRule: .nullify, inverse: \Ticket.iteration) var tickets: [Ticket] = []
    
    init(name: String, type: IterationType, startDate: Date, dueDate: Date, project: Project? = nil) {
        self.name = name
        self.type = type
        self.startDate = startDate
        self.dueDate = dueDate
        self.project = project
    }
}

enum IterationType: String, Codable, CaseIterable {
    case sprint = "Sprint"
    case milestone = "Milestone"
}
