import XCTest
import SwiftData
@testable import WorklogApp

final class WorklogAppTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
        // Create in-memory container for testing
        let schema = Schema([Project.self, Ticket.self, TimeEntry.self, Iteration.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
    }
    
    // MARK: - Project Tests
    
    func testProjectCreation() throws {
        let project = Project(name: "Test Project", detail: "Test detail")
        context.insert(project)
        try context.save()
        
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.detail, "Test detail")
        XCTAssertTrue(project.tickets.isEmpty)
        XCTAssertTrue(project.iterations.isEmpty)
    }
    
    func testProjectUpdate() throws {
        let project = Project(name: "Original", detail: "Original detail")
        context.insert(project)
        try context.save()
        
        project.name = "Updated"
        project.detail = "Updated detail"
        try context.save()
        
        XCTAssertEqual(project.name, "Updated")
        XCTAssertEqual(project.detail, "Updated detail")
    }
    
    func testProjectDeletion() throws {
        let project = Project(name: "To Delete", detail: "")
        context.insert(project)
        try context.save()
        
        context.delete(project)
        try context.save()
        
        let descriptor = FetchDescriptor<Project>()
        let projects = try context.fetch(descriptor)
        XCTAssertTrue(projects.isEmpty)
    }
    
    func testProjectTicketRelationship() throws {
        let project = Project(name: "Test Project", detail: "")
        context.insert(project)
        
        let ticket = Ticket(ticketId: "TST-001", name: "Test Ticket", detail: "", project: project)
        context.insert(ticket)
        try context.save()
        
        XCTAssertEqual(project.tickets.count, 1)
        XCTAssertEqual(project.tickets.first?.ticketId, "TST-001")
        XCTAssertEqual(ticket.project?.name, "Test Project")
    }
    
    // MARK: - Ticket Tests
    
    func testTicketCreation() throws {
        let ticket = Ticket(ticketId: "TST-001", name: "Test Ticket", detail: "Test detail")
        context.insert(ticket)
        try context.save()
        
        XCTAssertEqual(ticket.ticketId, "TST-001")
        XCTAssertEqual(ticket.name, "Test Ticket")
        XCTAssertEqual(ticket.detail, "Test detail")
        XCTAssertNotNil(ticket.startDate)
        XCTAssertNil(ticket.dueDate)
        XCTAssertNil(ticket.project)
        XCTAssertNil(ticket.iteration)
        XCTAssertTrue(ticket.entries.isEmpty)
    }
    
    func testTicketWithDates() throws {
        let startDate = Date()
        let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        
        let ticket = Ticket(
            ticketId: "TST-002",
            name: "Dated Ticket",
            detail: "",
            startDate: startDate,
            dueDate: dueDate
        )
        context.insert(ticket)
        try context.save()
        
        XCTAssertEqual(ticket.startDate.timeIntervalSince1970, startDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertNotNil(ticket.dueDate)
        XCTAssertEqual(ticket.dueDate!.timeIntervalSince1970, dueDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testTicketUpdate() throws {
        let ticket = Ticket(ticketId: "TST-003", name: "Original", detail: "")
        context.insert(ticket)
        try context.save()
        
        ticket.name = "Updated Ticket"
        ticket.detail = "Updated detail"
        ticket.dueDate = Date()
        try context.save()
        
        XCTAssertEqual(ticket.name, "Updated Ticket")
        XCTAssertEqual(ticket.detail, "Updated detail")
        XCTAssertNotNil(ticket.dueDate)
    }
    
    func testTicketTimeEntryRelationship() throws {
        let ticket = Ticket(ticketId: "TST-004", name: "Test", detail: "")
        context.insert(ticket)
        
        let entry = TimeEntry(hours: 2.5, ticket: ticket)
        context.insert(entry)
        try context.save()
        
        XCTAssertEqual(ticket.entries.count, 1)
        XCTAssertEqual(ticket.entries.first?.hours, 2.5)
        XCTAssertEqual(entry.ticket?.ticketId, "TST-004")
    }
    
    // MARK: - Iteration Tests
    
    func testIterationCreation() throws {
        let startDate = Date()
        let dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: startDate)!
        
        let iteration = Iteration(
            name: "Sprint 1",
            type: .sprint,
            startDate: startDate,
            dueDate: dueDate
        )
        context.insert(iteration)
        try context.save()
        
        XCTAssertEqual(iteration.name, "Sprint 1")
        XCTAssertEqual(iteration.type, .sprint)
        XCTAssertEqual(iteration.startDate.timeIntervalSince1970, startDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(iteration.dueDate.timeIntervalSince1970, dueDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertTrue(iteration.tickets.isEmpty)
    }
    
    func testIterationTypes() throws {
        let sprint = Iteration(name: "Sprint", type: .sprint, startDate: Date(), dueDate: Date())
        let milestone = Iteration(name: "Milestone", type: .milestone, startDate: Date(), dueDate: Date())
        
        context.insert(sprint)
        context.insert(milestone)
        try context.save()
        
        XCTAssertEqual(sprint.type, .sprint)
        XCTAssertEqual(milestone.type, .milestone)
        XCTAssertEqual(sprint.type.rawValue, "Sprint")
        XCTAssertEqual(milestone.type.rawValue, "Milestone")
    }
    
    func testIterationProjectRelationship() throws {
        let project = Project(name: "Test Project", detail: "")
        context.insert(project)
        
        let iteration = Iteration(
            name: "Sprint 1",
            type: .sprint,
            startDate: Date(),
            dueDate: Date(),
            project: project
        )
        context.insert(iteration)
        try context.save()
        
        XCTAssertEqual(project.iterations.count, 1)
        XCTAssertEqual(project.iterations.first?.name, "Sprint 1")
        XCTAssertEqual(iteration.project?.name, "Test Project")
    }
    
    func testIterationTicketRelationship() throws {
        let iteration = Iteration(name: "Sprint 1", type: .sprint, startDate: Date(), dueDate: Date())
        context.insert(iteration)
        
        let ticket = Ticket(
            ticketId: "TST-005",
            name: "Sprint Ticket",
            detail: "",
            iteration: iteration
        )
        context.insert(ticket)
        try context.save()
        
        XCTAssertEqual(iteration.tickets.count, 1)
        XCTAssertEqual(iteration.tickets.first?.ticketId, "TST-005")
        XCTAssertEqual(ticket.iteration?.name, "Sprint 1")
    }
    
    // MARK: - TimeEntry Tests
    
    func testTimeEntryCreation() throws {
        let entry = TimeEntry(hours: 3.5, note: "Working on feature")
        context.insert(entry)
        try context.save()
        
        XCTAssertEqual(entry.hours, 3.5)
        XCTAssertEqual(entry.note, "Working on feature")
        XCTAssertNotNil(entry.loggedAt)
        XCTAssertNil(entry.ticket)
    }
    
    func testTimeEntryWithTicket() throws {
        let ticket = Ticket(ticketId: "TST-006", name: "Test", detail: "")
        context.insert(ticket)
        
        let entry = TimeEntry(hours: 1.5, ticket: ticket, note: "Testing")
        context.insert(entry)
        try context.save()
        
        XCTAssertEqual(entry.hours, 1.5)
        XCTAssertEqual(entry.note, "Testing")
        XCTAssertEqual(entry.ticket?.ticketId, "TST-006")
    }
    
    func testTimeEntryTimestamp() throws {
        let beforeCreation = Date()
        let entry = TimeEntry(hours: 1.0)
        context.insert(entry)
        try context.save()
        let afterCreation = Date()
        
        XCTAssertGreaterThanOrEqual(entry.loggedAt, beforeCreation)
        XCTAssertLessThanOrEqual(entry.loggedAt, afterCreation)
    }
    
    // MARK: - Cascade Delete Tests
    
    func testProjectDeleteCascadesToTickets() throws {
        let project = Project(name: "Test", detail: "")
        context.insert(project)
        
        let ticket = Ticket(ticketId: "TST-007", name: "Test", detail: "", project: project)
        context.insert(ticket)
        try context.save()
        
        context.delete(project)
        try context.save()
        
        let descriptor = FetchDescriptor<Ticket>()
        let tickets = try context.fetch(descriptor)
        XCTAssertTrue(tickets.isEmpty)
    }
    
    func testProjectDeleteCascadesToIterations() throws {
        let project = Project(name: "Test", detail: "")
        context.insert(project)
        
        let iteration = Iteration(name: "Sprint", type: .sprint, startDate: Date(), dueDate: Date(), project: project)
        context.insert(iteration)
        try context.save()
        
        context.delete(project)
        try context.save()
        
        let descriptor = FetchDescriptor<Iteration>()
        let iterations = try context.fetch(descriptor)
        XCTAssertTrue(iterations.isEmpty)
    }
    
    func testTicketDeleteCascadesToTimeEntries() throws {
        let ticket = Ticket(ticketId: "TST-008", name: "Test", detail: "")
        context.insert(ticket)
        
        let entry = TimeEntry(hours: 1.0, ticket: ticket)
        context.insert(entry)
        try context.save()
        
        context.delete(ticket)
        try context.save()
        
        let descriptor = FetchDescriptor<TimeEntry>()
        let entries = try context.fetch(descriptor)
        XCTAssertTrue(entries.isEmpty)
    }
    
    // MARK: - Complex Relationship Tests
    
    func testFullHierarchy() throws {
        // Create project
        let project = Project(name: "Full Project", detail: "Test")
        context.insert(project)
        
        // Create iteration
        let iteration = Iteration(
            name: "Sprint 1",
            type: .sprint,
            startDate: Date(),
            dueDate: Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date())!,
            project: project
        )
        context.insert(iteration)
        
        // Create ticket
        let ticket = Ticket(
            ticketId: "TST-009",
            name: "Full Ticket",
            detail: "Test",
            project: project,
            iteration: iteration
        )
        context.insert(ticket)
        
        // Create time entries
        let entry1 = TimeEntry(hours: 2.0, ticket: ticket, note: "Work 1")
        let entry2 = TimeEntry(hours: 1.5, ticket: ticket, note: "Work 2")
        context.insert(entry1)
        context.insert(entry2)
        
        try context.save()
        
        // Verify relationships
        XCTAssertEqual(project.tickets.count, 1)
        XCTAssertEqual(project.iterations.count, 1)
        XCTAssertEqual(iteration.tickets.count, 1)
        XCTAssertEqual(ticket.entries.count, 2)
        
        // Calculate total hours
        let totalHours = ticket.entries.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(totalHours, 3.5)
    }
    
    // MARK: - Query Tests
    
    func testFetchProjectsByName() throws {
        let project1 = Project(name: "Alpha", detail: "")
        let project2 = Project(name: "Beta", detail: "")
        let project3 = Project(name: "Gamma", detail: "")
        
        context.insert(project1)
        context.insert(project2)
        context.insert(project3)
        try context.save()
        
        var descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        let projects = try context.fetch(descriptor)
        
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "Alpha")
        XCTAssertEqual(projects[1].name, "Beta")
        XCTAssertEqual(projects[2].name, "Gamma")
    }
    
    func testFetchTicketsByProject() throws {
        let project1 = Project(name: "Project 1", detail: "")
        let project2 = Project(name: "Project 2", detail: "")
        context.insert(project1)
        context.insert(project2)
        
        let ticket1 = Ticket(ticketId: "P1-001", name: "Ticket 1", detail: "", project: project1)
        let ticket2 = Ticket(ticketId: "P1-002", name: "Ticket 2", detail: "", project: project1)
        let ticket3 = Ticket(ticketId: "P2-001", name: "Ticket 3", detail: "", project: project2)
        
        context.insert(ticket1)
        context.insert(ticket2)
        context.insert(ticket3)
        try context.save()
        
        XCTAssertEqual(project1.tickets.count, 2)
        XCTAssertEqual(project2.tickets.count, 1)
    }
}
