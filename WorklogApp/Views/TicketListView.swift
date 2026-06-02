import SwiftUI
import SwiftData

struct TicketListView: View {
    let tickets: [Ticket]
    @Binding var selectedTicket: Ticket?
    @ObservedObject var timerState: TimerState
    let projectName: String?
    let onNewTicket: () -> Void
    let onBulkImport: () -> Void
    let onDeleteTicket: (Ticket) -> Void

    var body: some View {
        List(selection: $selectedTicket) {
            if tickets.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Tickets",
                        systemImage: "ticket",
                        description: Text(projectName == nil
                            ? "Create your first ticket to get started"
                            : "No tickets in this project yet")
                    )
                }
            } else {
                Section("Tickets") {
                    ForEach(tickets) { ticket in
                        TicketRowView(
                            ticket: ticket,
                            isTimerActiveHere: timerState.isTiming(ticket),
                            isPaused: timerState.isPaused
                        )
                        .tag(ticket)
                        .contextMenu {
                            Button {
                                selectedTicket = ticket
                            } label: {
                                Label("Open", systemImage: "doc.text")
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                onDeleteTicket(ticket)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(projectName ?? "All Tickets")
        .toolbar {
            if let timerTicket = timerState.currentTicket, timerState.isRunning {
                ToolbarItem(placement: .status) {
                    Button {
                        selectedTicket = timerTicket
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: timerState.isPaused ? "pause.circle.fill" : "timer")
                                .foregroundStyle(timerState.isPaused ? .yellow : .orange)
                                .symbolEffect(.pulse, options: .repeating, isActive: !timerState.isPaused)
                            Text(timerTicket.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(formatDuration(timerState.elapsed))
                                .monospacedDigit()
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            if timerState.isPaused {
                                StatusPill(text: "Paused", color: .yellow)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((timerState.isPaused ? Color.yellow : Color.orange).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        onNewTicket()
                    } label: {
                        Label("Single Ticket", systemImage: "plus")
                    }
                    Button {
                        onBulkImport()
                    } label: {
                        Label("Bulk Import", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("New Ticket", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Ticket Row

/// Row uses plain `let` flags from the parent rather than observing `TimerState`
/// directly. Result: per-second timer publishes don't repaint every row.
struct TicketRowView: View {
    let ticket: Ticket
    let isTimerActiveHere: Bool
    let isPaused: Bool

    private var totalSeconds: TimeInterval {
        ticket.entries.reduce(0) { $0 + ($1.hours * 3600) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isTimerActiveHere {
                    Image(systemName: isPaused ? "pause.circle.fill" : "timer")
                        .font(.caption)
                        .foregroundStyle(isPaused ? .yellow : .orange)
                        .symbolEffect(.pulse, options: .repeating, isActive: !isPaused)
                }
                Text(ticket.name)
                    .font(.headline)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if totalSeconds > 0 {
                    Text(formatDuration(totalSeconds))
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(spacing: 6) {
                if !ticket.ticketId.isEmpty {
                    Text(ticket.ticketId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if ticket.isImported {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Imported from Jira")
                }
                if let project = ticket.project {
                    Label(project.name, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let iteration = ticket.iteration {
                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let dueDate = ticket.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(dueDate < Date() ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
