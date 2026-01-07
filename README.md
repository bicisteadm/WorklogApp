# WorklogApp

A simple macOS menu bar application for time tracking and worklog management built with SwiftUI and SwiftData.

## Features

### Core Functionality
- **Menu Bar Only App** - Runs exclusively in the menu bar without a Dock icon
- **Live Timer** - Start/stop timer for tickets with real-time display in menu bar
- **Project Management** - Organize work by projects and iterations
- **Ticket Tracking** - Create and manage tickets with detailed information
- **Time Entry Logging** - Automatic and manual time entry creation
- **Advanced Reports** - View time entries with multiple grouping options

### Projects & Iterations
- Create projects with descriptions
- Define iterations (sprints or milestones) for each project
- Assign tickets to projects and iterations
- Track progress and deadlines

### Time Tracking
- Start/stop timer directly from menu bar or main window
- Time displays in `Xh Ymin Zs` format throughout the app
- Automatic time entry creation when stopping timer
- Manual time entry editing with hours, minutes, and seconds
- Add notes to time entries for detailed tracking

### Reports & Analytics
- **Multiple Grouping Modes:**
  - Individual Time Entries - All entries with full details
  - By Ticket - Aggregated time per ticket
  - By Iteration - Total time per iteration
  - By Project - Project-level time summaries
- **Powerful Filtering:**
  - Filter by project
  - Filter by iteration
  - Search by ticket name or note
- **Export Ready** - View total duration and entry counts

## Requirements
- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

1. Clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/WorklogApp.git
cd WorklogApp
```

2. Open the project in Xcode:
```bash
open WorklogApp.xcodeproj
```

3. Build and run the project (⌘R)

## Usage

### First Launch
The app will appear in your menu bar with a clock icon. Click it to access the menu or open the main window.

### Creating a Project
1. Open the main window from menu bar
2. Click "New Project"
3. Enter project name and description
4. Create iterations (sprints/milestones) as needed

### Creating Tickets
1. Select a project
2. Click "New Ticket"
3. Fill in ticket ID, name, and description
4. Optionally assign to an iteration
5. Set start and due dates

### Tracking Time
1. Select a ticket from the list
2. Click "Start Timer" or use the menu bar timer controls
3. The elapsed time shows in menu bar and updates every second
4. Click "Stop Timer" to save the time entry

### Viewing Reports
1. Click "Reports" in the main window
2. Select grouping mode (Individual/By Ticket/By Iteration/By Project)
3. Apply filters by project, iteration, or search
4. View aggregated time and entry counts

## Architecture

- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Native persistence with model-driven approach
- **MenuBarExtra** - Native menu bar integration
- **Combine** - Reactive timer state management
- **ObservableObject** - Shared timer state across views

## Data Model

### TimeEntry
- `hours: Double` - Duration stored as decimal hours (e.g., 1.5 = 1h 30min)
- `loggedAt: Date` - Timestamp of the entry
- `ticket: Ticket?` - Associated ticket
- `note: String?` - Optional notes

### Ticket
- `ticketId: String` - Unique identifier
- `name: String` - Ticket title
- `detail: String` - Description
- `startDate: Date` - Start date
- `dueDate: Date?` - Optional due date
- `project: Project?` - Parent project
- `iteration: Iteration?` - Assigned iteration
- `entries: [TimeEntry]` - Time entries for this ticket

### Project
- `name: String` - Project name
- `detail: String` - Project description
- `tickets: [Ticket]` - Associated tickets
- `iterations: [Iteration]` - Project iterations

### Iteration
- `name: String` - Iteration name
- `type: IterationType` - Sprint or Milestone
- `startDate: Date` - Start date
- `dueDate: Date` - End date
- `project: Project?` - Parent project

## Future Enhancements
- CSV/Excel export for reports
- Customizable time format preferences
- Backup and restore functionality
- Dark mode optimizations
- Keyboard shortcuts for common actions
- Time entry templates
- Weekly/monthly report summaries

## License
MIT License - Feel free to use and modify for your needs.

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.
