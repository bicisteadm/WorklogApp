import AppKit
import SwiftUI
import Combine

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    @Published var timerState: TimerState
    var onStopTimer: (() -> Void)?
    var openWindowAction: (() -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(timerState: TimerState) {
        self.timerState = timerState
        setupStatusBar()
        observeTimerState()
    }
    
    private func observeTimerState() {
        timerState.$isRunning
            .combineLatest(timerState.$elapsedTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateButton()
            }
            .store(in: &cancellables)
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if statusItem?.button != nil {
            updateButton()
        }
    }
    
    private func showMenu() {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open WorklogApp", action: #selector(openApplication), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        if timerState.isRunning {
            menu.addItem(NSMenuItem.separator())
            let stopItem = NSMenuItem(title: "Stop Timer", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        
        // Clear menu after display to allow clicks to work
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }
    
    @objc private func openApplication() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.openWindowAction?()
        }
    }
    
    @objc private func stopTimer() {
        onStopTimer?()
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateButton() {
        guard let button = statusItem?.button else { return }
        
        // Setup button action and event handling
        button.target = self
        button.action = #selector(statusBarAction)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        if timerState.isRunning {
            // Timer is running - orange icon with time
            let symbolConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            let image = NSImage(systemSymbolName: "timer.circle.fill", accessibilityDescription: "Timer Running")?.withSymbolConfiguration(symbolConfig)
            
            button.image = image
            button.imagePosition = .imageLeading
            button.title = timerState.formatElapsedTime()
        } else {
            // Timer is stopped - gray icon without text
            let symbolConfig = NSImage.SymbolConfiguration(paletteColors: [.systemGray])
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer Stopped")?.withSymbolConfiguration(symbolConfig)
            
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }
    
    @objc private func statusBarAction() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            // Left click - activate and open window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.openWindowAction?()
            }
        }
    }
    
    func removeStatusBar() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
