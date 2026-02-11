import SwiftUI
import SwiftData

struct TicketListView: View {
    let tickets: [Ticket]
    @Binding var selectedTicket: Ticket?
    @Binding var presentedSheet: SheetType?
    @ObservedObject var timerState: TimerState
    let projectName: String?
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
                        TicketRowView(ticket: ticket, timerState: timerState)
                            .tag(ticket)
                            .contextMenu {
                                Button {
                                    presentedSheet = .editTicket(ticket)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
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
                            Text(timerState.formatElapsedTime())
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
                        presentedSheet = .newTicket
                    } label: {
                        Label("Single Ticket", systemImage: "plus")
                    }
                    Button {
                        presentedSheet = .bulkTickets
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

struct TicketRowView: View {
    let ticket: Ticket
    @ObservedObject var timerState: TimerState

    private var isTimerActive: Bool {
        timerState.currentTicket?.id == ticket.id && timerState.isRunning
    }

    private var totalSeconds: TimeInterval {
        ticket.entries.reduce(0) { $0 + ($1.hours * 3600) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isTimerActive {
                            Image(systemName: timerState.isPaused ? "pause.circle.fill" : "timer")
                                .font(.caption)
                                .foregroundStyle(timerState.isPaused ? .yellow : .orange)
                                .symbolEffect(.pulse, options: .repeating, isActive: !timerState.isPaused)
                        }
                        Text(ticket.name)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if !ticket.ticketId.isEmpty {
                        Text(ticket.ticketId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Spacer()

                Text(formatDuration(totalSeconds))
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(totalSeconds > 0 ? Color.accentColor : .secondary)
                    .monospacedDigit()
            }

            // Metadata row
            HStack(spacing: 8) {
                if let project = ticket.project {
                    Label(project.name, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let iteration = ticket.iteration {
                    Label(iteration.name, systemImage: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                if let dueDate = ticket.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(dueDate < Date() ? .red : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
