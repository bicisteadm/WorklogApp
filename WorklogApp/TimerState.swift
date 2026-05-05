import SwiftUI
import SwiftData
import Combine

/// Shared timer state. Publishes a per-second `elapsed` while running, so any view that
/// reads it animates. To keep the per-second republish from re-painting the entire ticket
/// list, leaf rows (`TicketRowView`) take plain `let` flags from their parent and **do not
/// observe `TimerState` directly** — SwiftUI then skips body evaluation when their inputs
/// don't change.
final class TimerState: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var currentTicket: Ticket?
    @Published private(set) var continuingEntry: TimeEntry?
    @Published private(set) var elapsed: TimeInterval = 0

    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?
    private var notes: [PersistentIdentifier: String] = [:]

    // MARK: - Notes

    func note(for ticket: Ticket) -> String {
        notes[ticket.persistentModelID] ?? ""
    }

    func setNote(_ value: String, for ticket: Ticket) {
        notes[ticket.persistentModelID] = value
    }

    func clearNote(for ticket: Ticket) {
        notes.removeValue(forKey: ticket.persistentModelID)
    }

    func noteBinding(for ticket: Ticket) -> Binding<String> {
        Binding(
            get: { self.note(for: ticket) },
            set: { self.setNote($0, for: ticket) }
        )
    }

    // MARK: - Queries

    func isTiming(_ ticket: Ticket) -> Bool {
        isRunning && currentTicket?.persistentModelID == ticket.persistentModelID
    }

    func isContinuing(_ entry: TimeEntry) -> Bool {
        continuingEntry?.persistentModelID == entry.persistentModelID
    }

    func formattedElapsed() -> String {
        formatDuration(elapsed)
    }

    // MARK: - Control

    func start(for ticket: Ticket, continuing entry: TimeEntry? = nil) {
        invalidateTicker()
        currentTicket = ticket
        continuingEntry = entry
        accumulated = 0
        startedAt = Date()
        elapsed = 0
        isRunning = true
        isPaused = false
        scheduleTicker()
    }

    func pause() {
        guard isRunning, !isPaused, let started = startedAt else { return }
        accumulated += Date().timeIntervalSince(started)
        startedAt = nil
        elapsed = accumulated
        invalidateTicker()
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused else { return }
        startedAt = Date()
        isPaused = false
        scheduleTicker()
    }

    /// Stop the timer and persist elapsed time:
    ///   - if a `continuingEntry` was set, append into it (and merge notes with newline)
    ///   - otherwise insert a new TimeEntry on the ticket
    @discardableResult
    func stopAndPersist(in context: ModelContext) -> Ticket? {
        guard let ticket = currentTicket else {
            reset()
            return nil
        }

        let total = currentElapsed()
        let noteText = noteValue(for: ticket)
        clearNote(for: ticket)
        let entryToContinue = continuingEntry

        reset()

        guard total > 0 else { return ticket }

        let hours = total / 3600.0
        if let entry = entryToContinue {
            entry.hours += hours
            mergeNote(noteText, into: entry)
        } else {
            let entry = TimeEntry(hours: hours, ticket: ticket, note: noteText)
            context.insert(entry)
        }
        try? context.save()
        return ticket
    }

    func cancel() {
        if let ticket = currentTicket {
            clearNote(for: ticket)
        }
        reset()
    }

    // MARK: - Private

    private func currentElapsed() -> TimeInterval {
        var total = accumulated
        if !isPaused, let started = startedAt {
            total += Date().timeIntervalSince(started)
        }
        return total
    }

    private func noteValue(for ticket: Ticket) -> String? {
        let raw = note(for: ticket).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private func mergeNote(_ newNote: String?, into entry: TimeEntry) {
        guard let newNote, !newNote.isEmpty else { return }
        if let existing = entry.note, !existing.isEmpty {
            entry.note = existing + "\n" + newNote
        } else {
            entry.note = newNote
        }
    }

    private func scheduleTicker() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused, let started = self.startedAt else { return }
            self.elapsed = self.accumulated + Date().timeIntervalSince(started)
        }
        // common-mode so it ticks while menus / scrolls are active
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func invalidateTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func reset() {
        invalidateTicker()
        startedAt = nil
        accumulated = 0
        currentTicket = nil
        continuingEntry = nil
        isRunning = false
        isPaused = false
        elapsed = 0
    }
}
