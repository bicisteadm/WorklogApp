import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

// Helper function to format duration in h/min/s format
func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    return "\(hours)h \(minutes)min \(secs)s"
}

enum SheetType: Identifiable {
    case newTicket
    case bulkTickets
    case newProject
    case newIteration
    case projectDetail(Project)
    case editProject(Project)
    case editTicket(Ticket)
    case editTimeEntry(TimeEntry)
    
    var id: String {
        switch self {
        case .newTicket: return "newTicket"
        case .bulkTickets: return "bulkTickets"
        case .newProject: return "newProject"
        case .newIteration: return "newIteration"
        case .projectDetail(let project): return "projectDetail-\(project.id)"
        case .editProject(let project): return "editProject-\(project.id)"
        case .editTicket(let ticket): return "editTicket-\(ticket.id)"
        case .editTimeEntry(let entry): return "editTimeEntry-\(entry.id)"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Ticket.name) private var tickets: [Ticket]
    
    @ObservedObject var timerState: TimerState
    
    @State private var selectedProject: Project?
    @State private var selectedIteration: Iteration?
    @State private var selectedTicket: Ticket?
    @State private var presentedSheet: SheetType?
    @State private var showReports = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Database backup/restore
    @State private var showImportDB = false
    @State private var showBackupAlert = false
    @State private var backupMessage = ""

    private var filteredTickets: [Ticket] {
        var result = tickets
        
        if let project = selectedProject {
            result = result.filter { $0.project?.id == project.id }
        }
        
        if let iteration = selectedIteration {
            result = result.filter { $0.iteration?.id == iteration.id }
        }
        
        return result
    }
    
    private var projectIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return project.iterations.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("Projects") {
                    Button {
                        selectedProject = nil
                        selectedIteration = nil
                    } label: {
                        Label("All Projects", systemImage: "tray.full")
                            .fontWeight(selectedProject == nil ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)

                    ForEach(projects) { project in
                        Button {
                            selectedProject = project
                            selectedIteration = nil
                        } label: {
                            Label(project.name, systemImage: "folder")
                                .fontWeight(selectedProject?.id == project.id ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Manage Iterations") {
                                presentedSheet = .projectDetail(project)
                            }
                            Button("Edit") {
                                presentedSheet = .editProject(project)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteProject(project)
                            }
                        }
                    }
                }
                
                if selectedProject != nil && !projectIterations.isEmpty {
                    Section("Iterations") {
                        Button {
                            selectedIteration = nil
                        } label: {
                            Label("All Iterations", systemImage: "calendar")
                                .fontWeight(selectedIteration == nil ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(projectIterations) { iteration in
                            Button {
                                selectedIteration = iteration
                            } label: {
                                HStack {
                                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                        .fontWeight(selectedIteration?.id == iteration.id ? .semibold : .regular)
                                    Spacer()
                                    if isIterationActive(iteration) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showReports = true
                    } label: {
                        Label("Reports", systemImage: "chart.bar.doc.horizontal")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            exportDatabaseAction()
                        } label: {
                            Label("Export Database", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showImportDB = true
                        } label: {
                            Label("Import Database", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Database", systemImage: "cylinder")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentedSheet = .newProject
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("New Project")
                }
            }
        } content: {
            List(selection: $selectedTicket) {
                Section("Tickets") {
                    if filteredTickets.isEmpty {
                        Text(selectedProject == nil ? "No tickets yet" : "No tickets in this project")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredTickets) { ticket in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ticket.name).font(.headline)
                                if let iteration = ticket.iteration {
                                    Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(ticket.ticketId).font(.subheadline).foregroundStyle(.secondary)
                            if let project = ticket.project {
                                Text(project.name)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 8) {
                                if let iteration = ticket.iteration {
                                    Text(iteration.name)
                                        .font(.caption)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(3)
                                }
                                if let dueDate = ticket.dueDate {
                                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(dueDate < Date() ? .red : .secondary)
                                }
                                let totalSeconds = ticket.entries.reduce(0) { $0 + ($1.hours * 3600) }
                                Text(formatDuration(totalSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(ticket)
                        .contextMenu {
                            Button("Edit") {
                                presentedSheet = .editTicket(ticket)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteTicket(ticket)
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedProject?.name ?? "Tickets")
            .toolbar {
                if let timerTicket = timerState.currentTicket, timerState.isRunning {
                    ToolbarItem(placement: .status) {
                        Button {
                            selectedTicket = timerTicket
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "timer")
                                    .foregroundStyle(.orange)
                                    .symbolEffect(.pulse, options: .repeating)
                                Text(timerTicket.name)
                                    .font(.headline)
                                Text(timerState.formatElapsedTime())
                                    .monospacedDigit()
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            presentedSheet = .newTicket
                        } label: {
                            Label("Single Ticket", systemImage: "plus")
                        }
                        Button {
                            presentedSheet = .bulkTickets
                        } label: {
                            Label("Bulk Import", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label("New Ticket", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let ticket = selectedTicket ?? filteredTickets.first ?? tickets.first {
                TicketDetailView(
                    ticket: ticket,
                    presentedSheet: $presentedSheet,
                    timerState: timerState
                )
            } else {
                ContentUnavailableView("Select a ticket", systemImage: "ticket")
            }
        }
        .sheet(isPresented: $showReports) {
            NavigationStack {
                ReportsView()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newTicket:
                NewTicketView(projects: projects, selectedProject: selectedProject) { ticket in
                    selectedTicket = ticket
                }
                .padding()
                .frame(width: 400)
            case .bulkTickets:
                BulkTicketView(projects: projects, selectedProject: selectedProject)
                    .padding()
                    .frame(width: 600, height: 500)

            case .newProject:
                NewProjectView { project in
                    selectedProject = project
                }
                .padding()
                .frame(width: 360)
            case .editProject(let project):
                EditProjectView(project: project)
                    .padding()
                    .frame(width: 360)
            case .editTicket(let ticket):
                EditTicketView(ticket: ticket, projects: projects)
                    .padding()
                    .frame(width: 400)
            case .newIteration:
                if let project = selectedProject {
                    NewIterationView(project: project)
                        .padding()
                        .frame(width: 400)
                }
            case .projectDetail(let project):
                ProjectDetailView(project: project)
                    .padding()
                    .frame(width: 500, height: 400)
            case .editTimeEntry(let entry):
                EditTimeEntryView(entry: entry)
                    .padding()
                    .frame(width: 400)
            }
        }
        .onChange(of: tickets) { _, newValue in
            if let selected = selectedTicket, newValue.contains(where: { $0.id == selected.id }) == false {
                selectedTicket = nil
            }
        }
        .onChange(of: selectedProject) { _, _ in
            selectedIteration = nil
            if let current = selectedTicket, filteredTickets.contains(where: { $0.id == current.id }) == false {
                selectedTicket = filteredTickets.first
            }
        }
        .onChange(of: selectedIteration) { _, _ in
            if let current = selectedTicket, filteredTickets.contains(where: { $0.id == current.id }) == false {
                selectedTicket = filteredTickets.first
            }
        }
        .onAppear {
            if selectedProject == nil {
                selectedProject = projects.first
            }
            if selectedTicket == nil {
                selectedTicket = filteredTickets.first ?? tickets.first
            }
        }
        .fileImporter(isPresented: $showImportDB, allowedContentTypes: [.data]) { result in
            importDatabase(result: result)
        }
        .alert("Database Backup", isPresented: $showBackupAlert) {
            Button("OK") { }
        } message: {
            Text(backupMessage)
        }
    }
    
    private func isIterationActive(_ iteration: Iteration) -> Bool {
        let now = Date()
        return iteration.startDate <= now && now <= iteration.dueDate
    }
    
    private func stopTimerFromStatusBar(ticket: Ticket) {
        guard let result = timerState.stopTimer() else { return }
        
        let elapsed = result.endDate.timeIntervalSince(result.startDate)
        
        if elapsed > 0 {
            let hours = elapsed / 3600
            let entry = TimeEntry(hours: hours, ticket: ticket, note: nil)
            modelContext.insert(entry)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to save timer entry: \(error)")
            }
        }
    }
    
    private func exportDatabaseAction() {
        let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")
        
        do {
            // Save current context before export
            try modelContext.save()
            
            // Create save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.database]
            savePanel.nameFieldStringValue = "WorklogApp_backup.sqlite"
            savePanel.message = "Choose where to save the database backup"
            
            savePanel.begin { response in
                guard response == .OK, let url = savePanel.url else { return }
                
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: dbURL, to: url)
                    
                    backupMessage = "Database exported successfully"
                    showBackupAlert = true
                } catch {
                    backupMessage = "Export failed: \(error.localizedDescription)"
                    showBackupAlert = true
                }
            }
        } catch {
            backupMessage = "Failed to save database: \(error.localizedDescription)"
            showBackupAlert = true
        }
    }
    
    private func deleteProject(_ project: Project) {
        if selectedProject?.id == project.id {
            selectedProject = nil
            selectedIteration = nil
        }
        modelContext.delete(project)
        try? modelContext.save()
    }
    
    private func deleteTicket(_ ticket: Ticket) {
        if selectedTicket?.id == ticket.id {
            selectedTicket = nil
        }
        modelContext.delete(ticket)
        try? modelContext.save()
    }
    
    private func importDatabase(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")
            
            do {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    backupMessage = "Failed to access import file"
                    showBackupAlert = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                // Backup current database
                let backupURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp_old.sqlite")
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                if FileManager.default.fileExists(atPath: dbURL.path) {
                    try FileManager.default.copyItem(at: dbURL, to: backupURL)
                }
                
                // Import new database
                if FileManager.default.fileExists(atPath: dbURL.path) {
                    try FileManager.default.removeItem(at: dbURL)
                }
                try FileManager.default.copyItem(at: url, to: dbURL)
                
                backupMessage = "Database imported successfully.\nPlease restart the app to see changes."
                showBackupAlert = true
            } catch {
                backupMessage = "Import failed: \(error.localizedDescription)"
                showBackupAlert = true
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                backupMessage = "Import cancelled: \(error.localizedDescription)"
                showBackupAlert = true
            }
        }
    }
}

struct NewTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var ticketId: String = ""
    @State private var name: String = ""
    @State private var detail: String = ""
    @State private var startDate: Date = Date()
    @State private var dueDate: Date?
    @State private var showDueDate: Bool = false
    @State private var projectSelection: Project?
    @State private var iterationSelection: Iteration?
    @Query private var iterations: [Iteration]
    let projects: [Project]
    let selectedProject: Project?
    let onComplete: (Ticket) -> Void
    
    private var availableIterations: [Iteration] {
        guard let project = projectSelection else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Ticket").font(.title2)
                
                TextField("Ticket ID", text: $ticketId)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Title", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $detail)
                        .font(.body)
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.3), width: 1)
                        .cornerRadius(4)
                }
                
                Picker("Project", selection: $projectSelection) {
                    Text("None").tag(Project?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project))
                    }
                }
                .onChange(of: projectSelection) { _, _ in
                    iterationSelection = nil
                }
                
                if projectSelection != nil {
                    Picker("Iteration", selection: $iterationSelection) {
                        Text("None").tag(Iteration?.none)
                        ForEach(availableIterations) { iteration in
                            Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Date")
                        .font(.headline)
                    DatePicker("", selection: $startDate, displayedComponents: [.date])
                        .labelsHidden()
                }
                
                Toggle("Due Date", isOn: $showDueDate)
                if showDueDate {
                    DatePicker("", selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = $0 }
                    ), displayedComponents: [.date])
                    .labelsHidden()
                }
                
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") {
                        saveTicket()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ticketId.isEmpty || name.isEmpty)
                }
            }
            .padding()
        }
        .onAppear {
            projectSelection = selectedProject
        }
    }
    
    private func saveTicket() {
        guard !ticketId.isEmpty, !name.isEmpty else { return }
        
        let ticket = Ticket(
            ticketId: ticketId,
            name: name,
            detail: detail,
            startDate: startDate,
            dueDate: showDueDate ? dueDate : nil,
            project: projectSelection,
            iteration: iterationSelection
        )
        modelContext.insert(ticket)
        
        do {
            try modelContext.save()
            dismiss()
            onComplete(ticket)
        } catch {
            print("Failed to save ticket: \(error)")
        }
    }
}

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var detail: String = ""
    let onComplete: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Project").font(.title2)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(height: 60)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .fixedSize()
    }
    
    private func saveProject() {
        guard !name.isEmpty else { return }
        
        let project = Project(name: name, detail: detail)
        modelContext.insert(project)
        
        do {
            try modelContext.save()
            dismiss()
            onComplete(project)
        } catch {
            print("Failed to save project: \(error)")
        }
    }
}

struct TicketDetailView: View {
    let ticket: Ticket
    @Environment(\.modelContext) private var modelContext
    @Query private var iterations: [Iteration]
    @Binding var presentedSheet: SheetType?
    @ObservedObject var timerState: TimerState
    
    @State private var logHours: String = "0"
    @State private var logMinutes: String = "30"
    @State private var logSeconds: String = "0"
    @State private var entryNote: String = ""
    @State private var timerNote: String = ""
    @State private var timerCancellable: Timer?
    
    // Edit mode
    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editDetail: String = ""
    @State private var editTicketId: String = ""
    @State private var editProject: Project?
    @State private var editIteration: Iteration?
    @State private var editStartDate: Date = Date()
    @State private var editDueDate: Date?
    @State private var editShowDueDate: Bool = false
    @Query private var projects: [Project]
    
    private var isTiming: Bool {
        timerState.currentTicket?.id == ticket.id && timerState.isRunning
    }
    
    private var availableIterations: [Iteration] {
        guard let project = ticket.project else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private var totalLoggedSeconds: TimeInterval {
        ticket.entries.reduce(0) { $0 + ($1.hours * 3600) }
    }
    
    private var sortedEntries: [TimeEntry] {
        ticket.entries.sorted { $0.loggedAt > $1.loggedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Ticket Info Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        if isEditing {
                            // Edit Mode
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Edit Ticket")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Ticket ID")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $editTicketId)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Title")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $editName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Description")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ZStack(alignment: .topLeading) {
                                        if editDetail.isEmpty {
                                            Text("Enter description...")
                                                .foregroundStyle(.secondary.opacity(0.5))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 8)
                                        }
                                        TextEditor(text: $editDetail)
                                            .font(.body)
                                            .frame(height: 100)
                                            .scrollContentBackground(.hidden)
                                            .padding(4)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Project")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: $editProject) {
                                            Text("None").tag(Project?.none)
                                            ForEach(projects) { project in
                                                Text(project.name).tag(Optional(project))
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity)
                                    }
                                    
                                    if editProject != nil {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Iteration")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Picker("", selection: $editIteration) {
                                                Text("None").tag(Iteration?.none)
                                                ForEach(availableIterations) { iteration in
                                                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                .onChange(of: editProject) { _, _ in
                                    if let iteration = editIteration,
                                       iteration.project?.id != editProject?.id {
                                        editIteration = nil
                                    }
                                }
                                
                                Divider()
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Start Date")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        DatePicker("", selection: $editStartDate, displayedComponents: [.date])
                                            .labelsHidden()
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Toggle("Due Date", isOn: $editShowDueDate)
                                            .font(.caption)
                                        if editShowDueDate {
                                            DatePicker("", selection: Binding(
                                                get: { editDueDate ?? Date() },
                                                set: { editDueDate = $0 }
                                            ), displayedComponents: [.date])
                                            .labelsHidden()
                                        }
                                    }
                                }
                            }
                        } else {
                            // View Mode
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ticket.ticketId)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        Text(ticket.name)
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        
                                        if let project = ticket.project {
                                            HStack(spacing: 4) {
                                                Image(systemName: "folder")
                                                    .font(.caption)
                                                Text(project.name)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                
                                if !ticket.detail.isEmpty {
                                    Text(ticket.detail)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Ticket Details", systemImage: "doc.text")
                            .font(.headline)
                        Spacer()
                        if isEditing {
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .buttonStyle(.bordered)
                            Button("Save") {
                                saveTicket()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(editTicketId.isEmpty || editName.isEmpty)
                        } else {
                            Button {
                                startEditing()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if !isEditing {
                    // Display iteration info (read-only)
                    if let iteration = ticket.iteration {
                        GroupBox {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(iteration.name)
                                        .font(.headline)
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                        Text("\(iteration.startDate.formatted(date: .abbreviated, time: .omitted))")
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                        Text("\(iteration.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        } label: {
                            Label("Iteration", systemImage: "flag.2.crossed")
                                .font(.headline)
                        }
                    }
                    
                    // Display timeline info (read-only)
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Label("Start Date", systemImage: "calendar.badge.clock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Spacer()
                                Text(ticket.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .fontWeight(.medium)
                            }
                            
                            if let dueDate = ticket.dueDate {
                                Divider()
                                HStack {
                                    Label("Due Date", systemImage: "calendar.badge.exclamationmark")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Spacer()
                                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                        .fontWeight(.medium)
                                    if dueDate < Date() {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.red)
                                            .help("Overdue")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Timeline", systemImage: "calendar")
                            .font(.headline)
                    }
                }
                
                // Log Time Section
                GroupBox {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            TextField("H", text: $logHours)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                            Text("h")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            
                            TextField("M", text: $logMinutes)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                            Text("m")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            
                            TextField("S", text: $logSeconds)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                            Text("s")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        
                        TextField("Note (optional)", text: $entryNote)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            addTimeEntry()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValidTimeInput())
                    }
                } label: {
                    Label("Log Time", systemImage: "clock.badge.checkmark")
                        .font(.headline)
                }
                
                // Timer Section
                GroupBox {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            if isTiming {
                                Image(systemName: "timer")
                                    .foregroundStyle(.orange)
                                    .symbolEffect(.pulse, options: .repeating)
                                    .font(.title3)
                            } else {
                                Image(systemName: "timer")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                            
                            Text(isTiming ? timerState.formatElapsedTime() : formatDuration(0))
                                .monospacedDigit()
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(isTiming ? .orange : .primary)
                                .frame(minWidth: 80)
                        }
                        
                        TextField("Note (optional)", text: $timerNote)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            toggleTimer()
                        } label: {
                            Label(isTiming ? "Stop" : "Start", systemImage: isTiming ? "stop.circle.fill" : "play.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isTiming ? .orange : .accentColor)
                    }
                } label: {
                    HStack {
                        Label("Timer", systemImage: "stopwatch")
                            .font(.headline)
                        if isTiming {
                            Text("Running")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Total Logged Section
                GroupBox {
                    HStack {
                        Image(systemName: "sum")
                            .foregroundStyle(Color.accentColor)
                        Text("Total logged:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(totalLoggedSeconds))
                            .monospacedDigit()
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                } label: {
                    Label("Summary", systemImage: "chart.bar")
                        .font(.headline)
                }
                
                // Time Entries Section
                GroupBox {
                    if sortedEntries.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "clock.badge.xmark")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No time entries yet")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sortedEntries) { entry in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.loggedAt, formatter: Self.timestampFormatter)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let note = entry.note, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(formatDuration(entry.hours * 3600))
                                        .monospacedDigit()
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button {
                                        presentedSheet = .editTimeEntry(entry)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        deleteTimeEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                
                                if entry.id != sortedEntries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Time Entries", systemImage: "list.bullet.clipboard")
                            .font(.headline)
                        Spacer()
                        Text("\(sortedEntries.count)")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(ticket.ticketId)
        .onAppear {
            startTimerIfNeeded()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func isValidTimeInput() -> Bool {
        guard let h = Int(logHours), let m = Int(logMinutes), let s = Int(logSeconds) else {
            return false
        }
        return h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 && (h > 0 || m > 0 || s > 0)
    }
    
    private func addTimeEntry() {
        guard let h = Int(logHours), let m = Int(logMinutes), let s = Int(logSeconds) else { return }
        
        // Convert to hours (decimal)
        let totalHours = Double(h) + (Double(m) / 60.0) + (Double(s) / 3600.0)
        guard totalHours > 0 else { return }
        
        let noteText = entryNote.isEmpty ? nil : entryNote
        let entry = TimeEntry(hours: totalHours, ticket: ticket, note: noteText)
        modelContext.insert(entry)
        
        do {
            try modelContext.save()
            entryNote = ""
            // Reset to default
            logHours = "0"
            logMinutes = "30"
            logSeconds = "0"
        } catch {
            print("Failed to save time entry: \(error)")
        }
    }
    
    private func startTimerIfNeeded() {
        // Timer is now managed by TimerState, no local timer needed
    }
    
    private func stopTimer() {
        // Timer is managed by TimerState
        timerCancellable?.invalidate()
        timerCancellable = nil
    }
    
    private func toggleTimer() {
        if isTiming {
            stopTimer()
            
            guard let result = timerState.stopTimer() else { return }
            
            let elapsed = result.endDate.timeIntervalSince(result.startDate)
            guard elapsed > 0 else { return }
            
            let hours = elapsed / 3600
            let noteText = timerNote.isEmpty ? nil : timerNote
            let entry = TimeEntry(hours: hours, ticket: ticket, note: noteText)
            modelContext.insert(entry)
            
            do {
                try modelContext.save()
                timerNote = ""
            } catch {
                print("Failed to save timer entry: \(error)")
            }
        } else {
            timerState.startTimer(for: ticket)
            timerNote = ""
        }
    }
    
    private func deleteTimeEntry(_ entry: TimeEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
    
    private func startEditing() {
        editName = ticket.name
        editDetail = ticket.detail
        editTicketId = ticket.ticketId
        editProject = ticket.project
        editIteration = ticket.iteration
        editStartDate = ticket.startDate
        editDueDate = ticket.dueDate
        editShowDueDate = ticket.dueDate != nil
        isEditing = true
    }
    
    private func cancelEditing() {
        isEditing = false
    }
    
    private func saveTicket() {
        ticket.name = editName
        ticket.detail = editDetail
        ticket.ticketId = editTicketId
        ticket.project = editProject
        ticket.iteration = editIteration
        ticket.startDate = editStartDate
        ticket.dueDate = editShowDueDate ? editDueDate : nil
        try? modelContext.save()
        isEditing = false
    }
}

struct ProjectDetailView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showNewIteration = false
    @State private var editingIteration: Iteration?
    
    var sortedIterations: [Iteration] {
        project.iterations.sorted { $0.startDate > $1.startDate }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Iterations: \(project.name)")
                    .font(.title2)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    if sortedIterations.isEmpty {
                        ContentUnavailableView("No Iterations", systemImage: "calendar.badge.clock", description: Text("Create your first iteration"))
                            .frame(maxHeight: .infinity)
                    } else {
                        ForEach(sortedIterations) { iteration in
                            IterationRowView(iteration: iteration, onEdit: {
                                editingIteration = iteration
                            }, onDelete: {
                                deleteIteration(iteration)
                            })
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button {
                    showNewIteration = true
                } label: {
                    Label("New Iteration", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .sheet(isPresented: $showNewIteration) {
            NewIterationView(project: project)
                .padding()
                .frame(width: 400)
        }
        .sheet(item: $editingIteration) { iteration in
            EditIterationView(iteration: iteration)
                .padding()
                .frame(width: 400)
        }
    }
    
    private func deleteIteration(_ iteration: Iteration) {
        modelContext.delete(iteration)
        try? modelContext.save()
    }
}

struct IterationRowView: View {
    let iteration: Iteration
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    
    var ticketCount: Int {
        iteration.tickets.count
    }
    
    var isActive: Bool {
        let now = Date()
        return iteration.startDate <= now && now <= iteration.dueDate
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                        .font(.headline)
                    Spacer()
                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                    
                    Menu {
                        Button("Edit") {
                            onEdit()
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                HStack {
                    Label("\(iteration.startDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    Image(systemName: "arrow.right")
                    Label("\(iteration.dueDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("\(ticketCount) ticket\(ticketCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct NewIterationView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var type: IterationType = .sprint
    @State private var startDate: Date = Date()
    @State private var dueDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Iteration").font(.title2)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            Picker("Type", selection: $type) {
                ForEach(IterationType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type == .sprint ? "arrow.clockwise" : "flag").tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
            
            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveIteration()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || dueDate <= startDate)
            }
        }
        .padding()
        .fixedSize()
    }
    
    private func saveIteration() {
        guard !name.isEmpty, dueDate > startDate else { return }
        
        let iteration = Iteration(name: name, type: type, startDate: startDate, dueDate: dueDate, project: project)
        modelContext.insert(iteration)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save iteration: \(error)")
        }
    }
}

struct EditProjectView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var detail: String
    
    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _detail = State(initialValue: project.detail)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Project").font(.title2)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            TextField("Description", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(height: 80)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .fixedSize()
    }
    
    private func saveProject() {
        guard !name.isEmpty else { return }
        
        project.name = name
        project.detail = detail
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save project: \(error)")
        }
    }
}

struct EditTicketView: View {
    let ticket: Ticket
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var iterations: [Iteration]
    
    @State private var ticketId: String
    @State private var name: String
    @State private var detail: String
    @State private var startDate: Date
    @State private var dueDate: Date?
    @State private var showDueDate: Bool
    @State private var projectSelection: Project?
    @State private var iterationSelection: Iteration?
    let projects: [Project]
    
    init(ticket: Ticket, projects: [Project]) {
        self.ticket = ticket
        self.projects = projects
        _ticketId = State(initialValue: ticket.ticketId)
        _name = State(initialValue: ticket.name)
        _detail = State(initialValue: ticket.detail)
        _startDate = State(initialValue: ticket.startDate)
        _dueDate = State(initialValue: ticket.dueDate)
        _showDueDate = State(initialValue: ticket.dueDate != nil)
        _projectSelection = State(initialValue: ticket.project)
        _iterationSelection = State(initialValue: ticket.iteration)
    }
    
    private var availableIterations: [Iteration] {
        guard let project = projectSelection else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Ticket").font(.title2)
                
                TextField("Ticket ID", text: $ticketId)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Title", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $detail)
                        .font(.body)
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.3), width: 1)
                        .cornerRadius(4)
                }
                
                Picker("Project", selection: $projectSelection) {
                    Text("None").tag(Project?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project))
                    }
                }
                .onChange(of: projectSelection) { _, _ in
                    if let currentIteration = iterationSelection,
                       !availableIterations.contains(where: { $0.id == currentIteration.id }) {
                        iterationSelection = nil
                    }
                }
                
                if projectSelection != nil {
                    Picker("Iteration", selection: $iterationSelection) {
                        Text("None").tag(Iteration?.none)
                        ForEach(availableIterations) { iteration in
                            Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Date")
                        .font(.headline)
                    DatePicker("", selection: $startDate, displayedComponents: [.date])
                        .labelsHidden()
                }
                
                Toggle("Due Date", isOn: $showDueDate)
                if showDueDate {
                    DatePicker("", selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = $0 }
                    ), displayedComponents: [.date])
                    .labelsHidden()
                }
                
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") {
                        saveTicket()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ticketId.isEmpty || name.isEmpty)
                }
            }
            .padding()
        }
    }
    
    private func saveTicket() {
        guard !ticketId.isEmpty, !name.isEmpty else { return }
        
        ticket.ticketId = ticketId
        ticket.name = name
        ticket.detail = detail
        ticket.startDate = startDate
        ticket.dueDate = showDueDate ? dueDate : nil
        ticket.project = projectSelection
        ticket.iteration = iterationSelection
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save ticket: \(error)")
        }
    }
}

struct EditIterationView: View {
    let iteration: Iteration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var type: IterationType
    @State private var startDate: Date
    @State private var dueDate: Date
    
    init(iteration: Iteration) {
        self.iteration = iteration
        _name = State(initialValue: iteration.name)
        _type = State(initialValue: iteration.type)
        _startDate = State(initialValue: iteration.startDate)
        _dueDate = State(initialValue: iteration.dueDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Iteration").font(.title2)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            Picker("Type", selection: $type) {
                ForEach(IterationType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type == .sprint ? "arrow.clockwise" : "flag").tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
            
            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveIteration()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || dueDate <= startDate)
            }
        }
        .padding()
        .fixedSize()
    }
    
    private func saveIteration() {
        guard !name.isEmpty, dueDate > startDate else { return }
        
        iteration.name = name
        iteration.type = type
        iteration.startDate = startDate
        iteration.dueDate = dueDate
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save iteration: \(error)")
        }
    }
}

struct EditTimeEntryView: View {
    let entry: TimeEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var hours: String
    @State private var minutes: String
    @State private var seconds: String
    @State private var note: String
    @State private var loggedAt: Date
    
    init(entry: TimeEntry) {
        self.entry = entry
        
        // Convert hours (decimal) to h:m:s
        let totalSeconds = Int(entry.hours * 3600)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        
        _hours = State(initialValue: String(h))
        _minutes = State(initialValue: String(m))
        _seconds = State(initialValue: String(s))
        _note = State(initialValue: entry.note ?? "")
        _loggedAt = State(initialValue: entry.loggedAt)
    }
    
    private var isValidTime: Bool {
        guard let h = Int(hours), let m = Int(minutes), let s = Int(seconds) else {
            return false
        }
        return h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 && (h > 0 || m > 0 || s > 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Time Entry").font(.title2)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Time")
                    .font(.headline)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("H", text: $hours)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("hours")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    HStack(spacing: 4) {
                        TextField("M", text: $minutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("minutes")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    HStack(spacing: 4) {
                        TextField("S", text: $seconds)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.body)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            
            DatePicker("Logged At", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveTimeEntry()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidTime)
            }
        }
        .padding()
        .fixedSize()
    }
    
    private func saveTimeEntry() {
        guard let h = Int(hours), let m = Int(minutes), let s = Int(seconds) else { return }
        
        // Convert to hours (decimal)
        let totalHours = Double(h) + (Double(m) / 60.0) + (Double(s) / 3600.0)
        guard totalHours > 0 else { return }
        
        entry.hours = totalHours
        entry.note = note.isEmpty ? nil : note
        entry.loggedAt = loggedAt
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save time entry: \(error)")
        }
    }
}

struct BulkTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var bulkText: String = ""
    @State private var projectSelection: Project?
    @State private var iterationSelection: Iteration?
    @State private var createdCount: Int = 0
    @State private var showingResult: Bool = false
    @Query private var iterations: [Iteration]
    let projects: [Project]
    let selectedProject: Project?
    
    init(projects: [Project], selectedProject: Project?) {
        self.projects = projects
        self.selectedProject = selectedProject
        _projectSelection = State(initialValue: selectedProject)
    }
    
    private var availableIterations: [Iteration] {
        guard let project = projectSelection else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bulk Import Tickets").font(.title2)
            
            Text("Enter one ticket per line. Format: TICKET-ID | Title | Description")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
            Picker("Project", selection: $projectSelection) {
                Text("None").tag(Project?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project))
                }
            }
            .onChange(of: projectSelection) { _, _ in
                if let currentIteration = iterationSelection,
                   !availableIterations.contains(where: { $0.id == currentIteration.id }) {
                    iterationSelection = nil
                }
            }
            
            if projectSelection != nil {
                Picker("Iteration", selection: $iterationSelection) {
                    Text("None").tag(Iteration?.none)
                    ForEach(availableIterations) { iteration in
                        Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                    }
                }
            }
            
            TextEditor(text: $bulkText)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.2))
                .frame(maxHeight: .infinity)
            
            if showingResult {
                Text("✓ Created \(createdCount) ticket(s)")
                    .foregroundStyle(.green)
                    .font(.headline)
            }
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") {
                    importTickets()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private func importTickets() {
        let lines = bulkText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        createdCount = 0
        
        for line in lines {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            
            let ticketId: String
            let name: String
            let detail: String
            
            if parts.count >= 3 {
                // Format: ID | Title | Description
                ticketId = parts[0]
                name = parts[1]
                detail = parts[2]
            } else if parts.count == 2 {
                // Format: ID | Title
                ticketId = parts[0]
                name = parts[1]
                detail = ""
            } else {
                continue
            }
            
            guard !name.isEmpty else { continue }
            
            let ticket = Ticket(
                ticketId: ticketId,
                name: name,
                detail: detail,
                startDate: Date(),
                project: projectSelection,
                iteration: iterationSelection
            )
            modelContext.insert(ticket)
            createdCount += 1
        }
        
        do {
            try modelContext.save()
            showingResult = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            print("Failed to save tickets: \(error)")
        }
    }
}

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TimeEntry.loggedAt, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var iterations: [Iteration]
    
    @State private var selectedProject: Project?
    @State private var selectedIteration: Iteration?
    @State private var searchText = ""
    @State private var groupingMode: GroupingMode = .individual
    
    enum GroupingMode: String, CaseIterable, Identifiable {
        case individual = "Individual Time Entries"
        case byTicket = "By Ticket"
        case byIteration = "By Iteration"
        case byProject = "By Project"
        
        var id: String { rawValue }
    }
    
    struct GroupedData: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let hours: Double
        let entries: [TimeEntry]
    }
    
    private var availableIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }
    
    private var filteredEntries: [TimeEntry] {
        var result = allEntries
        
        // Filter by project
        if let project = selectedProject {
            result = result.filter { $0.ticket?.project?.id == project.id }
        }
        
        // Filter by iteration
        if let iteration = selectedIteration {
            result = result.filter { $0.ticket?.iteration?.id == iteration.id }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.ticket?.name.localizedCaseInsensitiveContains(searchText) == true ||
                entry.ticket?.ticketId.localizedCaseInsensitiveContains(searchText) == true ||
                (entry.note?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return result
    }
    
    private var totalHours: Double {
        filteredEntries.reduce(0) { $0 + $1.hours }
    }
    
    private var groupedData: [GroupedData] {
        switch groupingMode {
        case .individual:
            return filteredEntries.map { entry in
                GroupedData(
                    name: entry.ticket?.name ?? "Unknown",
                    subtitle: entry.ticket?.ticketId,
                    hours: entry.hours,
                    entries: [entry]
                )
            }
            
        case .byTicket:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.id.hashValue.description ?? "unknown"
            }
            return grouped.map { _, entries in
                let ticket = entries.first?.ticket
                return GroupedData(
                    name: ticket?.name ?? "Unknown",
                    subtitle: ticket?.ticketId,
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }
            
        case .byIteration:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.iteration?.name ?? "No Iteration"
            }
            return grouped.map { name, entries in
                GroupedData(
                    name: name,
                    subtitle: entries.first?.ticket?.iteration?.project?.name,
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }
            
        case .byProject:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.project?.name ?? "No Project"
            }
            return grouped.map { name, entries in
                GroupedData(
                    name: name,
                    subtitle: "\(entries.count) tickets",
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Time Reports")
                    .font(.title)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            // Filters
            VStack(spacing: 12) {
                HStack {
                    // Grouping mode picker
                    Picker("Group by", selection: $groupingMode) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 450)
                    
                    Spacer()
                    
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search tickets or notes...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)
                }
                
                HStack(spacing: 12) {
                    // Project filter
                    Picker("Project", selection: $selectedProject) {
                        Text("All Projects").tag(nil as Project?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                    .onChange(of: selectedProject) { _, _ in
                        // Reset iteration if it doesn't belong to selected project
                        if let iteration = selectedIteration,
                           !availableIterations.contains(where: { $0.id == iteration.id }) {
                            selectedIteration = nil
                        }
                    }
                    
                    // Iteration filter
                    Picker("Iteration", selection: $selectedIteration) {
                        Text("All Iterations").tag(nil as Iteration?)
                        ForEach(availableIterations) { iteration in
                            HStack {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                Text(iteration.name)
                            }
                            .tag(iteration as Iteration?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                    .disabled(selectedProject == nil)
                    
                    Spacer()
                    
                    // Clear filters
                    Button {
                        selectedProject = nil
                        selectedIteration = nil
                        searchText = ""
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                    .disabled(selectedProject == nil && selectedIteration == nil && searchText.isEmpty)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Stats bar
            HStack {
                Text(groupingMode == .individual ? "\(filteredEntries.count) time entries" : "\(groupedData.count) groups")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total: \(formatDuration(totalHours * 3600))")
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Table
            if groupingMode == .individual {
                // Individual entries view (original table)
                Table(filteredEntries) {
                    TableColumn("Date") { entry in
                        Text(entry.loggedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    .width(min: 100, max: 120)
                    
                    TableColumn("Ticket") { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.ticket?.name ?? "Unknown")
                                .font(.headline)
                            Text(entry.ticket?.ticketId ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("Project") { entry in
                        Text(entry.ticket?.project?.name ?? "No project")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Iteration") { entry in
                        if let iteration = entry.ticket?.iteration {
                            HStack(spacing: 4) {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                    .font(.caption)
                                Text(iteration.name)
                            }
                            .font(.caption)
                        } else {
                            Text("—")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 100, ideal: 130)
                    
                    TableColumn("Note") { entry in
                        Text(entry.note ?? "")
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 150)
                    
                    TableColumn("Duration") { entry in
                        Text(formatDuration(entry.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 120, max: 150)
                }
                .alternatingRowBackgrounds()
            } else {
                // Grouped view
                Table(groupedData) {
                    TableColumn("Name") { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.headline)
                            if let subtitle = group.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 200, ideal: 300)
                    
                    TableColumn("Time Entries") { group in
                        Text("\(group.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, max: 140)
                    
                    TableColumn("Total Duration") { group in
                        Text(formatDuration(group.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    .width(min: 140, max: 160)
                }
                .alternatingRowBackgrounds()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// Helper view modifier for alternating row backgrounds
extension View {
    func alternatingRowBackgrounds() -> some View {
        self
    }
}
