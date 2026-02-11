import SwiftUI
import SwiftData

// MARK: - New Project

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var detail: String = ""
    let onComplete: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title2.weight(.bold))

            FormField("Name") {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Description") {
                TextField("Optional description", text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { saveProject() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
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

// MARK: - Edit Project

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project")
                .font(.title2.weight(.bold))

            FormField("Name") {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Description") {
                TextField("Optional description", text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveProject() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
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

// MARK: - Project Detail (Iterations Management)

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
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Iterations")
                        .font(.title2.weight(.bold))
                    Text(project.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if sortedIterations.isEmpty {
                        ContentUnavailableView(
                            "No Iterations",
                            systemImage: "calendar.badge.clock",
                            description: Text("Create your first iteration to organize work")
                        )
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

// MARK: - Iteration Row

struct IterationRowView: View {
    let iteration: Iteration
    let onEdit: () -> Void
    let onDelete: () -> Void

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
                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag.fill")
                        .font(.headline)
                    Spacer()
                    if isActive {
                        StatusPill(text: "Active", color: .green)
                    }

                    Menu {
                        Button("Edit") { onEdit() }
                        Divider()
                        Button("Delete", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack {
                    Label(iteration.startDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    Image(systemName: "arrow.right")
                    Label(iteration.dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "ticket")
                        .font(.caption2)
                    Text("\(ticketCount) ticket\(ticketCount == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }
}
