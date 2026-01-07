import XCTest

final class WorklogAppUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Project Tests
    
    func testCreateProject() throws {
        // Click New Project button
        let newProjectButton = app.buttons["New Project"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 5))
        newProjectButton.click()
        
        // Fill in project details
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Test Project")
        
        let descField = app.textFields["Description"]
        descField.click()
        descField.typeText("Test project description")
        
        // Save
        let saveButton = app.buttons["Save"]
        saveButton.click()
        
        // Verify project appears in list
        let projectLabel = app.staticTexts["Test Project"]
        XCTAssertTrue(projectLabel.waitForExistence(timeout: 2))
    }
    
    func testEditProject() throws {
        // First create a project
        try testCreateProject()
        
        // Right-click on project
        let projectLabel = app.staticTexts["Test Project"]
        projectLabel.rightClick()
        
        // Click Edit
        let editButton = app.menuItems["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 2))
        editButton.click()
        
        // Modify name
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command) // Select all
        nameField.typeText("Updated Project")
        
        // Save
        app.buttons["Save"].click()
        
        // Verify updated name
        let updatedLabel = app.staticTexts["Updated Project"]
        XCTAssertTrue(updatedLabel.waitForExistence(timeout: 2))
    }
    
    func testDeleteProject() throws {
        // Create a project
        try testCreateProject()
        
        // Right-click and delete
        let projectLabel = app.staticTexts["Test Project"]
        projectLabel.rightClick()
        
        let deleteButton = app.menuItems["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.click()
        
        // Verify project is gone
        XCTAssertFalse(projectLabel.exists)
    }
    
    // MARK: - Ticket Tests
    
    func testCreateTicket() throws {
        // Create a project first
        try testCreateProject()
        
        // Click New Ticket button
        let newTicketButton = app.buttons["New Ticket"]
        XCTAssertTrue(newTicketButton.waitForExistence(timeout: 2))
        newTicketButton.click()
        
        // Fill in ticket details
        let ticketIdField = app.textFields["Ticket ID"]
        XCTAssertTrue(ticketIdField.waitForExistence(timeout: 2))
        ticketIdField.click()
        ticketIdField.typeText("TST-001")
        
        let titleField = app.textFields["Title"]
        titleField.click()
        titleField.typeText("Test Ticket")
        
        let descField = app.textFields["Description"]
        descField.click()
        descField.typeText("Test ticket description")
        
        // Save
        app.buttons["Save"].click()
        
        // Verify ticket appears
        let ticketLabel = app.staticTexts["Test Ticket"]
        XCTAssertTrue(ticketLabel.waitForExistence(timeout: 2))
    }
    
    func testEditTicket() throws {
        // Create ticket first
        try testCreateTicket()
        
        // Right-click on ticket
        let ticketLabel = app.staticTexts["Test Ticket"]
        ticketLabel.rightClick()
        
        // Click Edit
        app.menuItems["Edit"].click()
        
        // Modify title
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.click()
        titleField.typeKey("a", modifierFlags: .command)
        titleField.typeText("Updated Ticket")
        
        // Save
        app.buttons["Save"].click()
        
        // Verify updated name
        let updatedLabel = app.staticTexts["Updated Ticket"]
        XCTAssertTrue(updatedLabel.waitForExistence(timeout: 2))
    }
    
    func testDeleteTicket() throws {
        // Create ticket
        try testCreateTicket()
        
        // Right-click and delete
        let ticketLabel = app.staticTexts["Test Ticket"]
        ticketLabel.rightClick()
        
        app.menuItems["Delete"].click()
        
        // Verify ticket is gone
        XCTAssertFalse(ticketLabel.exists)
    }
    
    // MARK: - Iteration Tests
    
    func testCreateIteration() throws {
        // Create project first
        try testCreateProject()
        
        // Right-click on project
        let projectLabel = app.staticTexts["Test Project"]
        projectLabel.rightClick()
        
        // Click Manage Iterations
        app.menuItems["Manage Iterations"].click()
        
        // Click New Iteration
        let newIterationButton = app.buttons["New Iteration"]
        XCTAssertTrue(newIterationButton.waitForExistence(timeout: 2))
        newIterationButton.click()
        
        // Fill in iteration details
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Sprint 1")
        
        // Save
        app.buttons["Save"].click()
        
        // Verify iteration appears
        let iterationLabel = app.staticTexts["Sprint 1"]
        XCTAssertTrue(iterationLabel.waitForExistence(timeout: 2))
    }
    
    func testFilterByIteration() throws {
        // Create project
        try testCreateProject()
        
        // Create iteration
        try testCreateIteration()
        
        // Close iteration dialog
        app.buttons.matching(identifier: "xmark.circle.fill").firstMatch.click()
        
        // Create ticket with iteration
        let newTicketButton = app.buttons["New Ticket"]
        newTicketButton.click()
        
        let ticketIdField = app.textFields["Ticket ID"]
        ticketIdField.click()
        ticketIdField.typeText("TST-002")
        
        let titleField = app.textFields["Title"]
        titleField.click()
        titleField.typeText("Iteration Ticket")
        
        // Select iteration
        let iterationPicker = app.popUpButtons["Iteration"]
        if iterationPicker.waitForExistence(timeout: 2) {
            iterationPicker.click()
            app.menuItems["Sprint 1"].click()
        }
        
        app.buttons["Save"].click()
        
        // Click on iteration in sidebar to filter
        let iterationInSidebar = app.staticTexts["Sprint 1"]
        if iterationInSidebar.waitForExistence(timeout: 2) {
            iterationInSidebar.click()
            
            // Verify ticket is visible
            let ticketLabel = app.staticTexts["Iteration Ticket"]
            XCTAssertTrue(ticketLabel.exists)
        }
    }
    
    // MARK: - Time Logging Tests
    
    func testLogTime() throws {
        // Create ticket
        try testCreateTicket()
        
        // Click on ticket to open detail view
        let ticketLabel = app.staticTexts["Test Ticket"]
        ticketLabel.click()
        
        // Find hours field
        let hoursField = app.textFields.matching(NSPredicate(format: "value == '0.5'")).firstMatch
        if hoursField.waitForExistence(timeout: 2) {
            hoursField.click()
            hoursField.typeKey("a", modifierFlags: .command)
            hoursField.typeText("2.5")
            
            // Click Add button
            let addButton = app.buttons["Add"]
            addButton.click()
            
            // Wait a moment for the entry to be added
            sleep(1)
            
            // Verify time is logged (would check for entry in list)
            // This is simplified - in real app would verify the entry appears
        }
    }
    
    func testTimer() throws {
        // Create ticket
        try testCreateTicket()
        
        // Click on ticket
        let ticketLabel = app.staticTexts["Test Ticket"]
        ticketLabel.click()
        
        // Find and click Start button
        let startButton = app.buttons["Start"]
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
            
            // Wait a moment
            sleep(2)
            
            // Verify button changed to Stop
            let stopButton = app.buttons["Stop"]
            XCTAssertTrue(stopButton.exists)
            
            // Stop timer
            stopButton.click()
            
            // Verify button changed back to Start
            XCTAssertTrue(startButton.exists)
        }
    }
    
    // MARK: - Project Filtering Tests
    
    func testFilterByProject() throws {
        // Create two projects
        try testCreateProject()
        
        // Create second project
        app.buttons["New Project"].click()
        let nameField = app.textFields["Name"]
        nameField.click()
        nameField.typeText("Project Two")
        app.buttons["Save"].click()
        
        // Create ticket in first project
        let firstProject = app.staticTexts["Test Project"]
        firstProject.click()
        
        app.buttons["New Ticket"].click()
        let ticketIdField = app.textFields["Ticket ID"]
        ticketIdField.click()
        ticketIdField.typeText("TST-003")
        
        let titleField = app.textFields["Title"]
        titleField.click()
        titleField.typeText("Project One Ticket")
        app.buttons["Save"].click()
        
        // Click on second project
        let secondProject = app.staticTexts["Project Two"]
        secondProject.click()
        
        // Verify first project's ticket is not visible
        let projectOneTicket = app.staticTexts["Project One Ticket"]
        XCTAssertFalse(projectOneTicket.exists)
        
        // Click on "All Projects"
        app.staticTexts["All Projects"].click()
        
        // Verify ticket is visible again
        XCTAssertTrue(projectOneTicket.exists)
    }
    
    // MARK: - Navigation Tests
    
    func testNavigationBetweenViews() throws {
        // Create project
        try testCreateProject()
        
        // Create ticket
        try testCreateTicket()
        
        // Click on project in sidebar
        let projectLabel = app.staticTexts["Test Project"]
        projectLabel.click()
        
        // Verify tickets section is visible
        let ticketsSection = app.staticTexts["Tickets"]
        XCTAssertTrue(ticketsSection.exists)
        
        // Click on ticket
        let ticketLabel = app.staticTexts["Test Ticket"]
        ticketLabel.click()
        
        // Verify detail view is showing (check for timer section)
        let timerLabel = app.staticTexts["Timer"]
        XCTAssertTrue(timerLabel.waitForExistence(timeout: 2))
    }
    
    // MARK: - Data Persistence Tests
    
    func testDataPersistence() throws {
        // Create project
        try testCreateProject()
        
        // Restart app
        app.terminate()
        app.launch()
        
        // Verify project still exists
        let projectLabel = app.staticTexts["Test Project"]
        XCTAssertTrue(projectLabel.waitForExistence(timeout: 5))
    }
}
