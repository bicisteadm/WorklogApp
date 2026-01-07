import SwiftUI
import SwiftData

@main
struct WorklogAppApp: App {
    let modelContainer: ModelContainer
    @StateObject private var timerState = TimerState()
    @Environment(\.openWindow) private var openWindow
    
    init() {
        do {
            let schema = Schema([Project.self, Ticket.self, TimeEntry.self, Iteration.self])
            let dbURL = URL.applicationSupportDirectory.appendingPathComponent("WorklogApp.sqlite")
            let config = ModelConfiguration(schema: schema, url: dbURL)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(timerState: timerState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timerState.isRunning ? "timer" : "clock")
                if timerState.isRunning {
                    Text(timerState.formatElapsedTime())
                        .monospacedDigit()
                        .id(timerState.elapsedTime)
                }
            }
        }
        .menuBarExtraStyle(.menu)
        
        WindowGroup(id: "main") {
            ContentView(timerState: timerState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WorklogApp") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}