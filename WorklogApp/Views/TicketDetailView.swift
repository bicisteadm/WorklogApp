import SwiftUI
import SwiftData

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
    @State private var logDate: Date = Date()

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

    private var isTimingPaused: Bool {
        isTiming && timerState.isPaused
    }

    private var isContinuingEntry: Bool {
        isTiming && timerState.continuingEntry != nil
    }

    private var availableIterations: [Iteration] {
        guard let project = ticket.project else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }

    private var editAvailableIterations: [Iteration] {
        guard let project = editProject else { return [] }
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

    private func isEntryFromToday(_ entry: TimeEntry) -> Bool {
        Calendar.current.isDateInToday(entry.loggedAt)
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
            Text("Edit Ticket")
                .font(.headline)
                .foregroundStyle(.secondary)

            FormField("Ticket ID") {
                TextField("", text: $editTicketId)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Title") {
                TextField("", text: $editName)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Description") {
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
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
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
                            ForEach(editAvailableIterations) { iteration in
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
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(iteration.name)
                        .font(.headline)
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
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Timer icon & display
                    HStack(spacing: 8) {
                        if isTiming {
                            Image(systemName: isTimingPaused ? "pause.circle.fill" : "timer")
                                .foregroundStyle(isTimingPaused ? .yellow : .orange)
                                .symbolEffect(.pulse, options: .repeating, isActive: !isTimingPaused)
                                .font(.title3)
                        } else {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }

                        Text(isTiming ? timerState.formatElapsedTime() : formatDuration(0))
                            .monospacedDigit()
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(isTiming ? (isTimingPaused ? .yellow : .orange) : .primary)
                            .frame(minWidth: 90)
                    }

                    // Note field
                    TextField("Note (optional)", text: timerState.noteBinding(for: ticket))
                        .textFieldStyle(.roundedBorder)

                    // Controls
                    if isTiming {
                        Button {
                            if isTimingPaused {
                                timerState.resumeTimer()
                            } else {
                                timerState.pauseTimer()
                            }
                        } label: {
                            Label(isTimingPaused ? "Resume" : "Pause", systemImage: isTimingPaused ? "play.circle" : "pause.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(isTimingPaused ? .green : .yellow)
                        .controlSize(.small)
                    }

                    Button {
                        toggleTimer()
                    } label: {
                        Label(isTiming ? "Stop" : "Start", systemImage: isTiming ? "stop.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isTiming ? .orange : .accentColor)
                    .controlSize(.small)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Label("Timer", systemImage: "stopwatch")
                    .font(.headline)
                if isTiming {
                    StatusPill(text: isTimingPaused ? "Paused" : "Running",
                               color: isTimingPaused ? .yellow : .orange)
                    if isContinuingEntry {
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
        HStack(spacing: 12) {
            if isContinuingEntry && timerState.continuingEntry?.id == entry.id {
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
                    if isContinuingEntry && timerState.continuingEntry?.id == entry.id {
                        StatusPill(text: "Continuing...", color: .green)
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
            Text(formatDuration(entry.hours * 3600))
                .monospacedDigit()
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if isEntryFromToday(entry) && !isTiming {
                Button {
                    continueEntry(entry)
                } label: {
                    Label("Continue Timer", systemImage: "play.circle")
                }
                Divider()
            }
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

        let noteText = entryNote.isEmpty ? nil : entryNote
        let entry = TimeEntry(hours: totalHours, loggedAt: logDate, ticket: ticket, note: noteText)
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
        if isTiming {
            let note = timerState.getNote(for: ticket)
            let noteText = note.isEmpty ? nil : note
            timerState.clearNote(for: ticket)
            guard let result = timerState.stopTimer() else { return }
            guard result.elapsed > 0 else { return }

            let hours = result.elapsed / 3600
            if let existingEntry = result.continuingEntry {
                existingEntry.hours += hours
                if let newNote = noteText, !newNote.isEmpty {
                    if let existing = existingEntry.note, !existing.isEmpty {
                        existingEntry.note = existing + "; " + newNote
                    } else {
                        existingEntry.note = newNote
                    }
                }
            } else {
                let entry = TimeEntry(hours: hours, ticket: ticket, note: noteText)
                modelContext.insert(entry)
            }
            try? modelContext.save()
        } else {
            // Stop timer on another ticket first
            if timerState.isRunning, let otherTicket = timerState.currentTicket {
                let note = timerState.getNote(for: otherTicket)
                let noteText = note.isEmpty ? nil : note
                timerState.clearNote(for: otherTicket)
                if let result = timerState.stopTimer() {
                    if result.elapsed > 0 {
                        let hours = result.elapsed / 3600
                        if let existingEntry = result.continuingEntry {
                            existingEntry.hours += hours
                            if let newNote = noteText, !newNote.isEmpty {
                                if let existing = existingEntry.note, !existing.isEmpty {
                                    existingEntry.note = existing + "; " + newNote
                                } else {
                                    existingEntry.note = newNote
                                }
                            }
                        } else {
                            let entry = TimeEntry(hours: hours, ticket: otherTicket, note: noteText)
                            modelContext.insert(entry)
                        }
                        try? modelContext.save()
                    }
                }
            }
            timerState.startTimer(for: ticket)
        }
    }

    private func continueEntry(_ entry: TimeEntry) {
        // Stop any running timer first
        if timerState.isRunning, let otherTicket = timerState.currentTicket {
            let note = timerState.getNote(for: otherTicket)
            let noteText = note.isEmpty ? nil : note
            timerState.clearNote(for: otherTicket)
            if let result = timerState.stopTimer() {
                if result.elapsed > 0 {
                    let hours = result.elapsed / 3600
                    if let existingEntry = result.continuingEntry {
                        existingEntry.hours += hours
                        if let newNote = noteText, !newNote.isEmpty {
                            if let existing = existingEntry.note, !existing.isEmpty {
                                existingEntry.note = existing + "; " + newNote
                            } else {
                                existingEntry.note = newNote
                            }
                        }
                    } else {
                        let newEntry = TimeEntry(hours: hours, ticket: otherTicket, note: noteText)
                        modelContext.insert(newEntry)
                    }
                    try? modelContext.save()
                }
            }
        }

        timerState.startTimer(for: ticket, continuing: entry)

        // Pre-fill note from entry
        if let existingNote = entry.note, !existingNote.isEmpty {
            let key = ticket.id.hashValue.description
            timerState.ticketNotes[key] = existingNote
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
