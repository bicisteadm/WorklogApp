import SwiftUI
import SwiftData

struct TicketDetailView: View {
    @Bindable var ticket: Ticket
    @Environment(\.modelContext) private var modelContext
    @Query private var iterations: [Iteration]
    @Query private var projects: [Project]
    @ObservedObject var timerState: TimerState

    // Manual log fields
    @State private var logHours: String = "0"
    @State private var logMinutes: String = "30"
    @State private var logSeconds: String = "0"
    @State private var entryNote: String = ""
    @State private var logDate: Date = Date()

    // Inline edit
    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editDetail: String = ""
    @State private var editTicketId: String = ""
    @State private var editProject: Project?
    @State private var editIteration: Iteration?
    @State private var editStartDate: Date = Date()
    @State private var editDueDate: Date?
    @State private var editShowDueDate: Bool = false

    @State private var entryToEdit: TimeEntry?

    private var availableEditIterations: [Iteration] {
        guard let project = editProject else { return [] }
        // Keep the ticket's currently-assigned iteration available even if it's archived,
        // so the user can see/preserve it; otherwise hide archived options.
        return iterations.filter { iter in
            iter.project?.id == project.id && (!iter.isArchived || iter.id == ticket.iteration?.id)
        }
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
            VStack(alignment: .leading, spacing: 16) {
                ticketInfoSection
                if !isEditing {
                    if let iteration = ticket.iteration {
                        iterationSection(iteration)
                    }
                    timelineSection
                }
                timerSection
                logTimeSection
                summarySection
                entriesSection
            }
            .padding()
        }
        .navigationTitle(ticket.ticketId.isEmpty ? ticket.name : ticket.ticketId)
        .sheet(item: $entryToEdit) { entry in
            EditTimeEntryView(entry: entry)
        }
    }

    // MARK: - Ticket Info

    @ViewBuilder
    private var ticketInfoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if isEditing {
                    editFormContent
                } else {
                    viewModeContent
                }
            }
        } label: {
            HStack {
                Label("Ticket Details", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                if isEditing {
                    Button("Cancel") { cancelEditing() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Save") { saveTicket() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editName.isEmpty)
                } else {
                    Button {
                        startEditing()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var viewModeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !ticket.ticketId.isEmpty {
                Text(ticket.ticketId)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .textSelection(.enabled)
            }

            Text(ticket.name)
                .font(.title2.weight(.bold))
                .textSelection(.enabled)

            if let project = ticket.project {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                    Text(project.name)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if !ticket.detail.isEmpty {
                Text(ticket.detail)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var editFormContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormField("Ticket ID") {
                TextField("e.g. PROJ-123", text: $editTicketId)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Title") {
                TextField("Ticket title", text: $editName)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Description") {
                TextEditor(text: $editDetail)
                    .font(.body)
                    .frame(height: 100)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack(spacing: 16) {
                FormField("Project") {
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
                    FormField("Iteration") {
                        Picker("", selection: $editIteration) {
                            Text("None").tag(Iteration?.none)
                            ForEach(availableEditIterations) { iteration in
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
                FormField("Start Date") {
                    DatePicker("", selection: $editStartDate, displayedComponents: [.date])
                        .labelsHidden()
                }

                FormField("Due Date") {
                    Toggle("", isOn: $editShowDueDate)
                        .labelsHidden()
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
    }

    // MARK: - Iteration Section

    @ViewBuilder
    private func iterationSection(_ iteration: Iteration) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag.fill")
                    .font(.title3)
                    .foregroundStyle(iteration.isArchived ? .secondary : Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(iteration.name)
                            .font(.headline)
                        if iteration.isArchived {
                            StatusPill(text: "Archived", color: .gray)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(iteration.startDate.formatted(date: .abbreviated, time: .omitted))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text(iteration.dueDate.formatted(date: .abbreviated, time: .omitted))
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

    // MARK: - Timeline Section

    @ViewBuilder
    private var timelineSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                HStack {
                    Label("Start Date", systemImage: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    Spacer()
                    Text(ticket.startDate.formatted(date: .abbreviated, time: .omitted))
                        .fontWeight(.medium)
                }

                if let dueDate = ticket.dueDate {
                    Divider()
                    HStack {
                        Label("Due Date", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                            .frame(width: 130, alignment: .leading)
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

    // MARK: - Timer Section

    @ViewBuilder
    private var timerSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                LiveTimerLabel(timerState: timerState, ticket: ticket)
                    .frame(minWidth: 110, alignment: .leading)

                TextField("Note (optional)", text: timerState.noteBinding(for: ticket))
                    .textFieldStyle(.roundedBorder)

                if timerState.isTiming(ticket) {
                    Button {
                        if timerState.isPaused {
                            timerState.resume()
                        } else {
                            timerState.pause()
                        }
                    } label: {
                        Label(timerState.isPaused ? "Resume" : "Pause",
                              systemImage: timerState.isPaused ? "play.circle" : "pause.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(timerState.isPaused ? .green : .yellow)
                    .controlSize(.small)
                }

                Button {
                    toggleTimer()
                } label: {
                    Label(timerState.isTiming(ticket) ? "Stop" : "Start",
                          systemImage: timerState.isTiming(ticket) ? "stop.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(timerState.isTiming(ticket) ? .orange : .accentColor)
                .controlSize(.small)
                .keyboardShortcut(timerState.isTiming(ticket) ? "." : "t", modifiers: .command)
            }
        } label: {
            HStack(spacing: 6) {
                Label("Timer", systemImage: "stopwatch")
                    .font(.headline)
                if timerState.isTiming(ticket) {
                    StatusPill(text: timerState.isPaused ? "Paused" : "Running",
                               color: timerState.isPaused ? .yellow : .orange)
                    if timerState.continuingEntry != nil {
                        StatusPill(text: "Continuing", color: .green)
                    }
                }
            }
        }
    }

    // MARK: - Log Time Section

    @ViewBuilder
    private var logTimeSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        TextField("H", text: $logHours)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Text("h")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        TextField("M", text: $logMinutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Text("m")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        TextField("S", text: $logSeconds)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
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
                    .controlSize(.small)
                    .disabled(!isValidTimeInput())
                }

                HStack {
                    DatePicker("Day:", selection: $logDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    if !Calendar.current.isDateInToday(logDate) {
                        Button {
                            logDate = Date()
                        } label: {
                            Text("Today")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Spacer()
                }
            }
        } label: {
            Label("Log Time", systemImage: "clock.badge.checkmark")
                .font(.headline)
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        GroupBox {
            HStack {
                Image(systemName: "sum")
                    .foregroundStyle(Color.accentColor)
                Text("Total logged:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(totalLoggedSeconds))
                    .monospacedDigit()
                    .font(.system(.title3, design: .monospaced).weight(.bold))
            }
        } label: {
            Label("Summary", systemImage: "chart.bar")
                .font(.headline)
        }
    }

    // MARK: - Entries Section

    @ViewBuilder
    private var entriesSection: some View {
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
                        timeEntryRow(entry)
                        if entry.id != sortedEntries.last?.id {
                            Divider()
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("Time Entries", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                if !sortedEntries.isEmpty {
                    CountBadge(count: sortedEntries.count, color: .accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func timeEntryRow(_ entry: TimeEntry) -> some View {
        let continuingThis = timerState.isContinuing(entry)
        HStack(spacing: 12) {
            if continuingThis {
                Image(systemName: "arrow.trianglehead.counterclockwise")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.loggedAt, formatter: Self.timestampFormatter)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    if continuingThis {
                        StatusPill(text: "Continuing…", color: .green)
                    }
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if !timerState.isRunning {
                    Button {
                        continueEntry(entry)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Continue this entry")
                }
                Text(formatDuration(entry.hours * 3600))
                    .monospacedDigit()
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if !timerState.isRunning {
                Button {
                    continueEntry(entry)
                } label: {
                    Label("Continue Timer", systemImage: "play.circle")
                }
                Divider()
            }
            Button {
                entryToEdit = entry
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTimeEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func isValidTimeInput() -> Bool {
        guard let h = Int(logHours), let m = Int(logMinutes), let s = Int(logSeconds) else {
            return false
        }
        return h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 && (h > 0 || m > 0 || s > 0)
    }

    private func addTimeEntry() {
        guard let h = Int(logHours), let m = Int(logMinutes), let s = Int(logSeconds) else { return }
        let totalHours = Double(h) + (Double(m) / 60.0) + (Double(s) / 3600.0)
        guard totalHours > 0 else { return }

        let noteText = entryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TimeEntry(hours: totalHours, loggedAt: logDate, ticket: ticket, note: noteText.isEmpty ? nil : noteText)
        modelContext.insert(entry)

        do {
            try modelContext.save()
            entryNote = ""
            logDate = Date()
            logHours = "0"
            logMinutes = "30"
            logSeconds = "0"
        } catch {
            print("Failed to save time entry: \(error)")
        }
    }

    private func toggleTimer() {
        if timerState.isTiming(ticket) {
            timerState.stopAndPersist(in: modelContext)
        } else {
            // Stop any running timer first (saves whatever was tracked).
            if timerState.isRunning {
                timerState.stopAndPersist(in: modelContext)
            }
            timerState.start(for: ticket)
        }
    }

    private func continueEntry(_ entry: TimeEntry) {
        if timerState.isRunning {
            timerState.stopAndPersist(in: modelContext)
        }
        timerState.start(for: ticket, continuing: entry)
        if let existingNote = entry.note, !existingNote.isEmpty {
            timerState.setNote(existingNote, for: ticket)
        }
    }

    private func deleteTimeEntry(_ entry: TimeEntry) {
        if timerState.continuingEntry?.persistentModelID == entry.persistentModelID {
            timerState.cancel()
        }
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

// MARK: - LiveTimerLabel

/// Live timer label. Re-renders once per second when running, but it's a tiny
/// leaf view so the cost is negligible. Heavy parents (`TicketRowView`) avoid
/// observing `TimerState` and only get plain `let` flags.
private struct LiveTimerLabel: View {
    @ObservedObject var timerState: TimerState
    let ticket: Ticket

    var body: some View {
        HStack(spacing: 8) {
            if timerState.isTiming(ticket) {
                Image(systemName: timerState.isPaused ? "pause.circle.fill" : "timer")
                    .foregroundStyle(timerState.isPaused ? .yellow : .orange)
                    .font(.title3)
                Text(formatDuration(timerState.elapsed))
                    .monospacedDigit()
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(timerState.isPaused ? .yellow : .orange)
            } else {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Text(formatDuration(0))
                    .monospacedDigit()
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
    }
}
