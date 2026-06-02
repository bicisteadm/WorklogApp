import SwiftUI
import SwiftData

/// Inspector panel showing how many hours were logged on the selected day,
/// grouped by project. Reads `TimeEntry` directly from the store — running
/// timer is **not** counted (entries are only persisted on stop), but the
/// project that currently has an active timer gets a small pulsing dot so
/// the user knows new time will land there.
struct DailySummaryView: View {
    @Query(sort: \TimeEntry.loggedAt, order: .reverse) private var allEntries: [TimeEntry]

    /// Project of the currently-running timer (nil = no timer). Passed in from
    /// `ContentView` instead of observing `TimerState` here, so this view doesn't
    /// repaint on every per-second tick.
    let activeProjectID: PersistentIdentifier?

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var expanded: Set<PersistentIdentifier> = []

    private struct ProjectTotal: Identifiable {
        let projectID: PersistentIdentifier
        let projectName: String
        let entries: [TimeEntry]
        var totalHours: Double { entries.reduce(0) { $0 + $1.hours } }
        var id: PersistentIdentifier { projectID }
    }

    private struct TicketTotal: Identifiable {
        let ticket: Ticket
        let hours: Double
        var id: PersistentIdentifier { ticket.persistentModelID }
    }

    private var dayEntries: [TimeEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDay)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return allEntries.filter { $0.loggedAt >= start && $0.loggedAt < end }
    }

    private var grouped: [ProjectTotal] {
        let buckets = Dictionary(grouping: dayEntries) { entry -> PersistentIdentifier? in
            entry.ticket?.project?.persistentModelID
        }
        return buckets.compactMap { (projectID, entries) -> ProjectTotal? in
            guard let projectID,
                  let name = entries.first?.ticket?.project?.name else { return nil }
            return ProjectTotal(projectID: projectID, projectName: name, entries: entries)
        }
        .sorted { $0.totalHours > $1.totalHours }
    }

    private var totalHours: Double {
        dayEntries.reduce(0) { $0 + $1.hours }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDay)
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            Divider()
            if grouped.isEmpty {
                emptyState
            } else {
                List {
                    totalSection
                    ForEach(grouped) { project in
                        projectSection(project)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 240, idealWidth: 280)
    }

    // MARK: - Header

    private var dayHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    shiftDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Previous day")

                Spacer()

                VStack(spacing: 2) {
                    Text(dayLabel)
                        .font(.headline)
                    Text(selectedDay, format: .dateTime.weekday(.wide).day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    shiftDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isToday)
                .help("Next day")
            }

            if !isToday {
                Button("Today") {
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(12)
    }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return "Today" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.day().month(.abbreviated))
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        let snapped = Calendar.current.startOfDay(for: next)
        // Don't let user navigate into the future.
        let todayStart = Calendar.current.startOfDay(for: Date())
        selectedDay = min(snapped, todayStart)
    }

    // MARK: - Empty / Total

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No time logged")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var totalSection: some View {
        Section {
            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDuration(totalHours * 3600))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Project section

    @ViewBuilder
    private func projectSection(_ project: ProjectTotal) -> some View {
        let isExpanded = expanded.contains(project.projectID)
        let isActive = activeProjectID == project.projectID
        let tickets = ticketTotals(for: project)

        Section {
            Button {
                toggleExpanded(project.projectID)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(project.projectName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .help("Timer is running on this project")
                    }
                    Spacer()
                    Text(formatDuration(project.totalHours * 3600))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(tickets) { item in
                    HStack(spacing: 6) {
                        Text(ticketLabel(for: item.ticket))
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Text(formatDuration(item.hours * 3600))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func ticketTotals(for project: ProjectTotal) -> [TicketTotal] {
        let byTicket = Dictionary(grouping: project.entries) { entry -> PersistentIdentifier? in
            entry.ticket?.persistentModelID
        }
        return byTicket.compactMap { (_, entries) -> TicketTotal? in
            guard let ticket = entries.first?.ticket else { return nil }
            let hours = entries.reduce(0) { $0 + $1.hours }
            return TicketTotal(ticket: ticket, hours: hours)
        }
        .sorted { $0.hours > $1.hours }
    }

    private func ticketLabel(for ticket: Ticket) -> String {
        ticket.ticketId.isEmpty ? ticket.name : "\(ticket.ticketId) — \(ticket.name)"
    }

    private func toggleExpanded(_ id: PersistentIdentifier) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}
