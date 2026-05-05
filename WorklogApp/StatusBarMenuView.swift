import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var timerState: TimerState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            WindowOpener.bringMainToFront(openWindow: openWindow)
        } label: {
            Label("Open WorklogApp", systemImage: "clock.badge.checkmark")
        }
        .keyboardShortcut("o")

        Divider()

        if timerState.isRunning, let ticket = timerState.currentTicket {
            Label {
                Text(ticket.name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: timerState.isPaused ? "pause.circle.fill" : "timer")
            }

            // Custom-format snapshot is fine here: the menu re-renders each time it opens.
            Text(timerState.formattedElapsed())
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
                    timerState.resume()
                } else {
                    timerState.pause()
                }
            }
            .keyboardShortcut("p")

            Button("Stop Timer") {
                timerState.stopAndPersist(in: modelContext)
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
}
