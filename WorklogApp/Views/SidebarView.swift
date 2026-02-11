import SwiftUI
import SwiftData

struct SidebarView: View {
    let projects: [Project]
    let projectIterations: [Iteration]
    @Binding var selectedProject: Project?
    @Binding var selectedIteration: Iteration?
    @Binding var presentedSheet: SheetType?
    @Binding var showReports: Bool
    @Binding var showImportDB: Bool
    let onExportDB: () -> Void
    let onDeleteProject: (Project) -> Void

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
                        CountBadge(count: projects.reduce(0) { $0 + $1.tickets.count })
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
                            Spacer()
                            CountBadge(count: project.tickets.count)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
                                Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag.fill")
                                    .fontWeight(selectedIteration?.id == iteration.id ? .semibold : .regular)
                                Spacer()
                                CountBadge(count: iteration.tickets.count)
                                if isIterationActive(iteration) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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

    private func isIterationActive(_ iteration: Iteration) -> Bool {
        let now = Date()
        return iteration.startDate <= now && now <= iteration.dueDate
    }
}
