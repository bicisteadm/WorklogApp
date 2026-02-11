import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var timerState: TimerState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            bringWindowToFront()
        } label: {
            Label("Open WorklogApp", systemImage: "clock.badge.checkmark")
        }
        .keyboardShortcut("o")

        Divider()

        if timerState.isRunning, let ticket = timerState.currentTicket {
            // Timer info
            Label {
                Text(ticket.name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: timerState.isPaused ? "pause.circle.fill" : "timer")
            }

            Text(timerState.formatElapsedTime())
                .monospacedDigit()
                .font(.system(.body, design: .monospaced))

            if timerState.isPaused {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(timerState.isPaused ? "Resume Timer" : "Pause Timer") {
                if timerState.isPaused {
                    timerState.resumeTimer()
                } else {
                    timerState.pauseTimer()
                }
            }
            .keyboardShortcut("p")

            Button("Stop Timer") {
                stopAndSaveTimer(ticket: ticket)
            }
            .keyboardShortcut("s")

            Divider()
        } else {
            Text("No timer running")
                .foregroundStyle(.secondary)
            Divider()
        }

        Button("Quit WorklogApp") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private func bringWindowToFront() {
        if let existingWindow = NSApp.windows.first(where: { window in
            window.canBecomeKey &&
            !(window is NSPanel) &&
            window.styleMask.contains(.titled)
        }) {
            NSApp.activate(ignoringOtherApps: true)
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) && $0.styleMask.contains(.titled) })?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    private func stopAndSaveTimer(ticket: Ticket) {
        let note = timerState.getNote(for: ticket)
        let noteText = note.isEmpty ? nil : note
        timerState.clearNote(for: ticket)

        guard let result = timerState.stopTimer(), result.elapsed > 0 else { return }

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
    }
}
