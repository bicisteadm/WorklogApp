import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private struct SidebarWidthKey: PreferenceKey {
    static var defaultValue: Double = 200
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: Double = 280
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
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
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 200
    @AppStorage("contentWidth") private var contentWidth: Double = 280

    @State private var showImportDB = false
    @State private var showBackupAlert = false
    @State private var backupMessage = ""

    private var filteredTickets: [Ticket] {
        var result = tickets
        if let project = selectedProject {
            result = result.filter { $0.project?.id == project.id }
        }
        if let iteration = selectedIteration {
            // User picked a specific iteration — show its tickets even if archived.
            result = result.filter { $0.iteration?.id == iteration.id }
        } else {
            // No specific iteration selected — hide tickets that belong to an archived one.
            result = result.filter { ticket in
                guard let iter = ticket.iteration else { return true }
                return !iter.isArchived
            }
        }
        return result
    }

    private var projectActiveIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return project.iterations
            .filter { !$0.isArchived }
            .sorted { $0.startDate > $1.startDate }
    }

    private var projectArchivedIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return project.iterations
            .filter { $0.isArchived }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Resolve the ticket to show in the detail pane. The selection lives in
    /// `selectedTicket`, but we tolerate it pointing at a ticket that no longer
    /// matches the current filter — in that case fall back to the first match.
    /// This avoids a stale selection flashing when filters change.
    private var detailTicket: Ticket? {
        if let selected = selectedTicket, filteredTickets.contains(where: { $0.id == selected.id }) {
            return selected
        }
        return filteredTickets.first
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                activeIterations: projectActiveIterations,
                archivedIterations: projectArchivedIterations,
                selectedProject: $selectedProject,
                selectedIteration: $selectedIteration,
                presentedSheet: $presentedSheet,
                showReports: $showReports,
                showImportDB: $showImportDB,
                onExportDB: exportDatabaseAction,
                onDeleteProject: deleteProject
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: sidebarWidth, max: 400)
            .background(GeometryReader { geo in
                Color.clear.preference(key: SidebarWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(SidebarWidthKey.self) { sidebarWidth = $0 }
        } content: {
            TicketListView(
                tickets: filteredTickets,
                selectedTicket: $selectedTicket,
                timerState: timerState,
                projectName: selectedProject?.name,
                onNewTicket: { presentedSheet = .newTicket },
                onBulkImport: { presentedSheet = .bulkTickets },
                onDeleteTicket: deleteTicket
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: contentWidth, max: 500)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
        } detail: {
            if let ticket = detailTicket {
                TicketDetailView(
                    ticket: ticket,
                    timerState: timerState
                )
                .id(ticket.id)
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
            sheetContent(for: sheet)
        }
        .onChange(of: selectedProject) { _, _ in
            // Project switched — clear any iteration filter from the previous project.
            selectedIteration = nil
        }
        .onAppear {
            if selectedProject == nil {
                selectedProject = projects.first
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

    // MARK: - Sheet Router

    @ViewBuilder
    private func sheetContent(for sheet: SheetType) -> some View {
        switch sheet {
        case .newTicket:
            NewTicketView(projects: projects, selectedProject: selectedProject, selectedIteration: selectedIteration) { ticket in
                selectedTicket = ticket
            }
            .frame(width: 420)
        case .bulkTickets:
            BulkTicketView(projects: projects, selectedProject: selectedProject)
                .padding()
                .frame(width: 600, height: 500)
        case .newProject:
            NewProjectView { project in
                selectedProject = project
            }
        case .editProject(let project):
            EditProjectView(project: project)
        case .newIteration:
            if let project = selectedProject {
                NewIterationView(project: project)
                    .padding()
                    .frame(width: 400)
            }
        case .projectDetail(let project):
            ProjectDetailView(project: project)
                .padding()
                .frame(width: 520, height: 450)
        }
    }

    // MARK: - Actions

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
        if timerState.currentTicket?.id == ticket.id {
            timerState.cancel()
        }
        modelContext.delete(ticket)
        try? modelContext.save()
    }

    private func exportDatabaseAction() {
        let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")

        do {
            try modelContext.save()

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

    private func importDatabase(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    backupMessage = "Failed to access import file"
                    showBackupAlert = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let backupURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp_old.sqlite")
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                if FileManager.default.fileExists(atPath: dbURL.path) {
                    try FileManager.default.copyItem(at: dbURL, to: backupURL)
                }
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
