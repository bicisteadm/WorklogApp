import SwiftUI
import SwiftData

// MARK: - New Ticket

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
    let selectedIteration: Iteration?
    let onComplete: (Ticket) -> Void

    init(projects: [Project], selectedProject: Project?, selectedIteration: Iteration?, onComplete: @escaping (Ticket) -> Void) {
        self.projects = projects
        self.selectedProject = selectedProject
        self.selectedIteration = selectedIteration
        self.onComplete = onComplete
        _projectSelection = State(initialValue: selectedProject)
        _iterationSelection = State(initialValue: selectedIteration)
    }

    private var availableIterations: [Iteration] {
        guard let project = projectSelection else { return [] }
        return iterations.filter { $0.project?.id == project.id && !$0.isArchived }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("New Ticket")
                    .font(.title2.weight(.bold))

                FormField("Ticket ID") {
                    TextField("e.g. PROJ-123", text: $ticketId)
                        .textFieldStyle(.roundedBorder)
                }

                FormField("Title") {
                    TextField("Ticket title", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                FormField("Description") {
                    TextEditor(text: $detail)
                        .font(.body)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                Divider()

                FormField("Project") {
                    Picker("", selection: $projectSelection) {
                        Text("None").tag(Project?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }
                    .labelsHidden()
                }
                .onChange(of: projectSelection) { _, _ in
                    iterationSelection = nil
                }

                if projectSelection != nil {
                    FormField("Iteration") {
                        Picker("", selection: $iterationSelection) {
                            Text("None").tag(Iteration?.none)
                            ForEach(availableIterations) { iteration in
                                Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                            }
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                FormField("Start Date") {
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

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Create") { saveTicket() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty)
                }
            }
            .padding()
        }
    }

    private func saveTicket() {
        guard !name.isEmpty else { return }
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

// MARK: - Bulk Ticket Import

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
        return iterations.filter { $0.project?.id == project.id && !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bulk Import Tickets")
                .font(.title2.weight(.bold))

            Text("Enter one ticket per line.\nFormat: **TICKET-ID | Title | Description**")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                FormField("Project") {
                    Picker("", selection: $projectSelection) {
                        Text("None").tag(Project?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }
                    .labelsHidden()
                }
                .onChange(of: projectSelection) { _, _ in
                    if let currentIteration = iterationSelection,
                       !availableIterations.contains(where: { $0.id == currentIteration.id }) {
                        iterationSelection = nil
                    }
                }

                if projectSelection != nil {
                    FormField("Iteration") {
                        Picker("", selection: $iterationSelection) {
                            Text("None").tag(Iteration?.none)
                            ForEach(availableIterations) { iteration in
                                Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag").tag(Optional(iteration))
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            TextEditor(text: $bulkText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .frame(maxHeight: .infinity)

            if showingResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Created \(createdCount) ticket(s)")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { importTickets() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
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
                ticketId = parts[0]
                name = parts[1]
                detail = parts[2]
            } else if parts.count == 2 {
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
