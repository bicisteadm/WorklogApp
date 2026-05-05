import SwiftUI
import SwiftData

struct SidebarView: View {
    let projects: [Project]
    let activeIterations: [Iteration]
    let archivedIterations: [Iteration]
    @Binding var selectedProject: Project?
    @Binding var selectedIteration: Iteration?
    @Binding var presentedSheet: SheetType?
    @Binding var showReports: Bool
    @Binding var showImportDB: Bool
    let onExportDB: () -> Void
    let onDeleteProject: (Project) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showArchived = false

    var body: some View {
        List {
            Section("Projects") {
                Button {
                    selectedProject = nil
                    selectedIteration = nil
                } label: {
                    HStack {
                        Label("All Projects", systemImage: "tray.full.fill")
                            .fontWeight(selectedProject == nil ? .semibold : .regular)
                        Spacer()
                        CountBadge(count: activeTicketCount(for: nil))
                    }
                }
                .buttonStyle(.plain)

                ForEach(projects) { project in
                    Button {
                        selectedProject = project
                        selectedIteration = nil
                    } label: {
                        HStack {
                            Label(project.name, systemImage: "folder.fill")
                                .fontWeight(selectedProject?.id == project.id ? .semibold : .regular)
                            if project.isJiraSynced {
                                Image(systemName: "link")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("Jira-synced project")
                            }
                            Spacer()
                            CountBadge(count: activeTicketCount(for: project))
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if project.isJiraSynced {
                            Button {
                                presentedSheet = .jiraSync(project)
                            } label: {
                                Label("Sync from Jira", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Divider()
                        }
                        Button {
                            presentedSheet = .projectDetail(project)
                        } label: {
                            Label("Manage Iterations", systemImage: "calendar.badge.clock")
                        }
                        Button {
                            presentedSheet = .editProject(project)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            onDeleteProject(project)
                        }
                    }
                }
            }

            if selectedProject != nil {
                if !activeIterations.isEmpty {
                    Section("Iterations") {
                        Button {
                            selectedIteration = nil
                        } label: {
                            Label("All Iterations", systemImage: "calendar")
                                .fontWeight(selectedIteration == nil ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)

                        ForEach(activeIterations) { iteration in
                            iterationRow(iteration, isArchived: false)
                        }
                    }
                }

                if !archivedIterations.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showArchived) {
                            ForEach(archivedIterations) { iteration in
                                iterationRow(iteration, isArchived: true)
                            }
                        } label: {
                            HStack {
                                Label("Archived", systemImage: "archivebox")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                CountBadge(count: archivedIterations.count)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("WorklogApp")
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
                        onExportDB()
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

            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
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
    }

    @ViewBuilder
    private func iterationRow(_ iteration: Iteration, isArchived: Bool) -> some View {
        Button {
            selectedIteration = iteration
        } label: {
            HStack {
                Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag.fill")
                    .fontWeight(selectedIteration?.id == iteration.id ? .semibold : .regular)
                    .foregroundStyle(isArchived ? .secondary : .primary)
                Spacer()
                CountBadge(count: iteration.tickets.count)
                if !isArchived, isIterationActive(iteration) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleArchive(iteration)
            } label: {
                Label(iteration.isArchived ? "Unarchive" : "Archive",
                      systemImage: iteration.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
        }
    }

    private func toggleArchive(_ iteration: Iteration) {
        iteration.isArchived.toggle()
        // If we just archived the currently-selected iteration, drop the selection so the
        // ticket list doesn't keep showing archived tickets after the user expected them gone.
        if iteration.isArchived, selectedIteration?.id == iteration.id {
            selectedIteration = nil
        }
        try? modelContext.save()
    }

    /// Active tickets = tickets not in an archived iteration. Mirrors `filteredTickets`
    /// in `ContentView` so the sidebar count agrees with what's displayed.
    private func activeTicketCount(for project: Project?) -> Int {
        let scope: [Ticket]
        if let project {
            scope = project.tickets
        } else {
            scope = projects.flatMap(\.tickets)
        }
        return scope.filter { ticket in
            guard let iter = ticket.iteration else { return true }
            return !iter.isArchived
        }.count
    }

    private func isIterationActive(_ iteration: Iteration) -> Bool {
        let now = Date()
        return iteration.startDate <= now && now <= iteration.dueDate
    }
}
