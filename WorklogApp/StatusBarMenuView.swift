import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var timerState: TimerState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Button("Open WorklogApp") {
            // First check if window already exists
            if let existingWindow = NSApp.windows.first(where: { window in
                window.canBecomeKey &&
                !(window is NSPanel) &&
                window.styleMask.contains(.titled)
            }) {
                // Window exists - just bring it to front
                NSApp.activate(ignoringOtherApps: true)
                if existingWindow.isMiniaturized {
                    existingWindow.deminiaturize(nil)
                }
                existingWindow.makeKeyAndOrderFront(nil)
            } else {
                // No window exists - open a new one
                openWindow(id: "main")
                
                // Activate and bring window to front
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { window in
                        window.canBecomeKey &&
                        !(window is NSPanel) &&
                        window.styleMask.contains(.titled)
                    }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        
        Divider()
        
        if timerState.isRunning, let ticket = timerState.currentTicket {
            Text("Running: \(ticket.name)")
                .font(.headline)
            Text(timerState.formatElapsedTime())
                .monospacedDigit()
                .font(.system(.body, design: .monospaced))
            
            Button("Stop Timer") {
                if let result = timerState.stopTimer() {
                    let elapsed = result.endDate.timeIntervalSince(result.startDate)
                    if elapsed > 0 {
                        let hours = elapsed / 3600
                        let entry = TimeEntry(hours: hours, ticket: ticket, note: nil)
                        modelContext.insert(entry)
                        
                        do {
                            try modelContext.save()
                        } catch {
                            print("Failed to save timer entry: \(error)")
                        }
                    }
                }
            }
            
            Divider()
        }
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
