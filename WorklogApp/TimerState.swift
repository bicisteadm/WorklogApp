import SwiftUI
import Combine

class TimerState: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentTicket: Ticket?
    @Published var startDate: Date?
    @Published var elapsedTime: TimeInterval = 0
    @Published var ticketNotes: [String: String] = [:]
    
    /// Time accumulated from previous run segments (before pauses)
    private var accumulatedTime: TimeInterval = 0
    
    func noteBinding(for ticket: Ticket) -> Binding<String> {
        let key = ticket.id.hashValue.description
        return Binding(
            get: { self.ticketNotes[key] ?? "" },
            set: { self.ticketNotes[key] = $0 }
        )
    }
    
    func getNote(for ticket: Ticket) -> String {
        ticketNotes[ticket.id.hashValue.description] ?? ""
    }
    
    func clearNote(for ticket: Ticket) {
        ticketNotes.removeValue(forKey: ticket.id.hashValue.description)
    }
    
    private var timer: Timer?
    
    func startTimer(for ticket: Ticket) {
        currentTicket = ticket
        startDate = Date()
        isRunning = true
        isPaused = false
        elapsedTime = 0
        accumulatedTime = 0
        
        timer?.invalidate()
        timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startDate else { return }
            self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(start)
        }
        
        // Add timer to run loop with common modes so it runs even when menu is open
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func pauseTimer() {
        guard isRunning, !isPaused, let start = startDate else { return }
        
        timer?.invalidate()
        timer = nil
        
        accumulatedTime += Date().timeIntervalSince(start)
        elapsedTime = accumulatedTime
        isPaused = true
    }
    
    func resumeTimer() {
        guard isRunning, isPaused else { return }
        
        startDate = Date()
        isPaused = false
        
        timer?.invalidate()
        timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startDate else { return }
            self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(start)
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stopTimer() -> (ticket: Ticket, elapsed: TimeInterval)? {
        timer?.invalidate()
        timer = nil
        
        guard let ticket = currentTicket else {
            isRunning = false
            isPaused = false
            currentTicket = nil
            startDate = nil
            elapsedTime = 0
            accumulatedTime = 0
            return nil
        }
        
        // Calculate final elapsed: accumulated + current segment (if not paused)
        var totalElapsed = accumulatedTime
        if !isPaused, let start = startDate {
            totalElapsed += Date().timeIntervalSince(start)
        }
        
        let result = (ticket: ticket, elapsed: totalElapsed)
        
        isRunning = false
        isPaused = false
        currentTicket = nil
        startDate = nil
        elapsedTime = 0
        accumulatedTime = 0
        
        return result
    }
    
    func formatElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = Int(elapsedTime) / 60 % 60
        let seconds = Int(elapsedTime) % 60
        return "\(hours)h \(minutes)min \(seconds)s"
    }
}
