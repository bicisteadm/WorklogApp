import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @Query(sort: \TimeEntry.loggedAt, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var iterations: [Iteration]

    @State private var selectedProject: Project?
    @State private var selectedIteration: Iteration?
    @State private var searchText = ""
    @State private var groupingMode: GroupingMode = .individual

    // Date range filters. nil = bound is inactive.
    @State private var entryDateFrom: Date?
    @State private var entryDateTo: Date?
    @State private var ticketDateFrom: Date?
    @State private var ticketDateTo: Date?
    @State private var showDateFilters = false

    enum GroupingMode: String, CaseIterable, Identifiable {
        case individual = "Individual"
        case byTicket = "By Ticket"
        case byIteration = "By Iteration"
        case byProject = "By Project"

        var id: String { rawValue }
    }

    struct GroupedData: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let ticketId: String?
        let hours: Double
        let entries: [TimeEntry]
    }

    private var availableIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }

    private var hasDateFilter: Bool {
        entryDateFrom != nil || entryDateTo != nil ||
            ticketDateFrom != nil || ticketDateTo != nil
    }

    private var hasAnyFilter: Bool {
        selectedProject != nil || selectedIteration != nil ||
            !searchText.isEmpty || hasDateFilter
    }

    private var filteredEntries: [TimeEntry] {
        var result = allEntries

        if let project = selectedProject {
            result = result.filter { $0.ticket?.project?.id == project.id }
        }

        if let iteration = selectedIteration {
            result = result.filter { $0.ticket?.iteration?.id == iteration.id }
        }

        if let from = entryDateFrom {
            let startOfDay = Calendar.current.startOfDay(for: from)
            result = result.filter { $0.loggedAt >= startOfDay }
        }
        if let to = entryDateTo {
            let endOfDay = Calendar.current.startOfDay(for: to).addingTimeInterval(86_400)
            result = result.filter { $0.loggedAt < endOfDay }
        }

        if let from = ticketDateFrom {
            let startOfDay = Calendar.current.startOfDay(for: from)
            result = result.filter { ($0.ticket?.startDate ?? .distantPast) >= startOfDay }
        }
        if let to = ticketDateTo {
            let endOfDay = Calendar.current.startOfDay(for: to).addingTimeInterval(86_400)
            result = result.filter { ($0.ticket?.startDate ?? .distantFuture) < endOfDay }
        }

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
                    subtitle: nil,
                    ticketId: entry.ticket?.ticketId,
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
                    subtitle: nil,
                    ticketId: ticket?.ticketId,
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
                    ticketId: nil,
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
                    ticketId: nil,
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
                    .font(.title.weight(.bold))
                Spacer()
                Button("Close") { dismissWindow(id: WindowIDs.reports) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            .padding()

            Divider()

            // Filters
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Group by", selection: $groupingMode) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)

                    Spacer()

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search...", text: $searchText)
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
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 250)
                }

                HStack(spacing: 12) {
                    Picker("Project", selection: $selectedProject) {
                        Text("All Projects").tag(nil as Project?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                    .onChange(of: selectedProject) { _, _ in
                        if let iteration = selectedIteration,
                           !availableIterations.contains(where: { $0.id == iteration.id }) {
                            selectedIteration = nil
                        }
                    }

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
                    .frame(minWidth: 180)
                    .disabled(selectedProject == nil)

                    Button {
                        showDateFilters.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text("Date filters")
                            if hasDateFilter {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .popover(isPresented: $showDateFilters, arrowEdge: .bottom) {
                        DateFiltersPopover(
                            entryDateFrom: $entryDateFrom,
                            entryDateTo: $entryDateTo,
                            ticketDateFrom: $ticketDateFrom,
                            ticketDateTo: $ticketDateTo
                        )
                    }

                    Spacer()

                    Button {
                        selectedProject = nil
                        selectedIteration = nil
                        searchText = ""
                        entryDateFrom = nil
                        entryDateTo = nil
                        ticketDateFrom = nil
                        ticketDateTo = nil
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                    .disabled(!hasAnyFilter)
                }

                if hasDateFilter {
                    ActiveDateFiltersBar(
                        entryDateFrom: $entryDateFrom,
                        entryDateTo: $entryDateTo,
                        ticketDateFrom: $ticketDateFrom,
                        ticketDateTo: $ticketDateTo
                    )
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Stats bar
            HStack {
                Text(groupingMode == .individual ? "\(filteredEntries.count) time entries" : "\(groupedData.count) groups")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .textSelection(.enabled)
                Spacer()
                Text("Total: \(formatDuration(totalHours * 3600))")
                    .font(.headline)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Table
            if groupingMode == .individual {
                Table(filteredEntries) {
                    TableColumn("Date & Time") { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.loggedAt.formatted(date: .abbreviated, time: .omitted))
                                .textSelection(.enabled)
                            Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        }
                    }
                    .width(min: 110, max: 140)

                    TableColumn("Ticket ID") { entry in
                        if let id = entry.ticket?.ticketId, !id.isEmpty {
                            Text(id)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 90, ideal: 110, max: 140)

                    TableColumn("Title") { entry in
                        Text(entry.ticket?.name ?? "Unknown")
                            .font(.headline)
                            .textSelection(.enabled)
                    }
                    .width(min: 150, ideal: 220)

                    TableColumn("Project") { entry in
                        Text(entry.ticket?.project?.name ?? "No project")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 110, ideal: 140)

                    TableColumn("Iteration") { entry in
                        if let iteration = entry.ticket?.iteration {
                            HStack(spacing: 4) {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                    .font(.caption)
                                Text(iteration.name)
                                    .textSelection(.enabled)
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
                            .textSelection(.enabled)
                    }
                    .width(min: 150)

                    TableColumn("Duration") { entry in
                        Text(formatDuration(entry.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 120, max: 150)
                }
            } else {
                Table(groupedData) {
                    TableColumn("Ticket ID") { group in
                        if let id = group.ticketId, !id.isEmpty {
                            Text(id)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 90, ideal: 110, max: 140)

                    TableColumn("Name") { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.headline)
                                .textSelection(.enabled)
                            if let subtitle = group.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Entries") { group in
                        Text("\(group.entries.count)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 80, max: 120)

                    TableColumn("Total Duration") { group in
                        Text(formatDuration(group.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    }
                    .width(min: 140, max: 160)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Date Filters Popover

private struct DateFiltersPopover: View {
    @Binding var entryDateFrom: Date?
    @Binding var entryDateTo: Date?
    @Binding var ticketDateFrom: Date?
    @Binding var ticketDateTo: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DateRangeSection(
                title: "Entry date (loggedAt)",
                hint: "Filters individual time entries by when they were logged.",
                from: $entryDateFrom,
                to: $entryDateTo
            )

            Divider()

            DateRangeSection(
                title: "Ticket date (startDate)",
                hint: "Filters by the ticket's start date — all entries on matching tickets are kept.",
                from: $ticketDateFrom,
                to: $ticketDateTo
            )
        }
        .padding(16)
        .frame(width: 360)
    }
}

private struct DateRangeSection: View {
    let title: String
    let hint: String
    @Binding var from: Date?
    @Binding var to: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OptionalDateRow(label: "From", date: $from)
            OptionalDateRow(label: "To", date: $to)

            HStack(spacing: 8) {
                Button("Last 7 days") {
                    from = Calendar.current.date(byAdding: .day, value: -6, to: Date())
                    to = Date()
                }
                .controlSize(.small)
                Button("This month") {
                    let cal = Calendar.current
                    let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))
                    from = start
                    to = Date()
                }
                .controlSize(.small)
                Button("Clear") {
                    from = nil
                    to = nil
                }
                .controlSize(.small)
                .disabled(from == nil && to == nil)
            }
        }
    }
}

private struct OptionalDateRow: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(.secondary)
            if let unwrapped = date {
                DatePicker(
                    "",
                    selection: Binding(get: { unwrapped }, set: { date = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Set date") {
                    date = Date()
                }
                .controlSize(.small)
                Spacer()
            }
        }
    }
}

// MARK: - Active filters chips bar

private struct ActiveDateFiltersBar: View {
    @Binding var entryDateFrom: Date?
    @Binding var entryDateTo: Date?
    @Binding var ticketDateFrom: Date?
    @Binding var ticketDateTo: Date?

    var body: some View {
        HStack(spacing: 8) {
            if entryDateFrom != nil || entryDateTo != nil {
                FilterChip(
                    label: "Entry \(rangeText(entryDateFrom, entryDateTo))",
                    icon: "clock"
                ) {
                    entryDateFrom = nil
                    entryDateTo = nil
                }
            }
            if ticketDateFrom != nil || ticketDateTo != nil {
                FilterChip(
                    label: "Ticket \(rangeText(ticketDateFrom, ticketDateTo))",
                    icon: "ticket"
                ) {
                    ticketDateFrom = nil
                    ticketDateTo = nil
                }
            }
            Spacer()
        }
    }

    private func rangeText(_ from: Date?, _ to: Date?) -> String {
        let fmt: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }
        switch (from, to) {
        case let (f?, t?): return "\(fmt(f)) – \(fmt(t))"
        case let (f?, nil): return "from \(fmt(f))"
        case let (nil, t?): return "until \(fmt(t))"
        default: return ""
        }
    }
}

private struct FilterChip: View {
    let label: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }
}
