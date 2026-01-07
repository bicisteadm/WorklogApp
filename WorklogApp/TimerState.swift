import SwiftUI
import Combine

class TimerState: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var currentTicket: Ticket?
    @Published var startDate: Date?
    @Published var elapsedTime: TimeInterval = 0
    
    private var timer: Timer?
    
    func startTimer(for ticket: Ticket) {
        currentTicket = ticket
        startDate = Date()
        isRunning = true
        elapsedTime = 0
        
        timer?.invalidate()
        timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startDate else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
        
        // Add timer to run loop with common modes so it runs even when menu is open
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stopTimer() -> (ticket: Ticket, startDate: Date, endDate: Date)? {
        timer?.invalidate()
        timer = nil
        
        guard let ticket = currentTicket, let start = startDate else {
            isRunning = false
            currentTicket = nil
            startDate = nil
            elapsedTime = 0
            return nil
        }
        
        let end = Date()
        let result = (ticket: ticket, startDate: start, endDate: end)
        
        isRunning = false
        currentTicket = nil
        startDate = nil
        elapsedTime = 0
        
        return result
    }
    
    func formatElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = Int(elapsedTime) / 60 % 60
        let seconds = Int(elapsedTime) % 60
        return "\(hours)h \(minutes)min \(seconds)s"
    }
}
