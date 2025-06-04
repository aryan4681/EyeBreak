import Cocoa
import SwiftUI
import Combine

// Create a strong top-level reference to prevent the app from closing
let app = NSApplication.shared
let delegate = AppDelegate()

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var breakWindow: NSWindow?
    var timeUntilBreak = 20 * 60 // 20 minutes until next break
    var breakDuration = 30 // 30-second break
    var isOnBreak = false
    var menuIsOpen = false
    var menuUpdateTimer: Timer?
    
    private var selfReference: AppDelegate?
    private var nextBreakDate: Date?
    private var breakWorkItem: DispatchWorkItem?
    private var nextBreakWorkItem: DispatchWorkItem?
    private var nextBreakTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.accessory)
        selfReference = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "👀"
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuWillOpen(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidClose(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        // Listen for system wake to reschedule the break timer
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                         selector: #selector(handleWake(_:)),
                                                         name: NSWorkspace.didWakeNotification,
                                                       object: nil)
        
        // Schedule the first break trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scheduleNextBreak()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("AppDelegate: applicationShouldTerminateAfterLastWindowClosed -> false")
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cancel scheduled tasks
        nextBreakWorkItem?.cancel()
        breakWorkItem?.cancel()
        menuUpdateTimer?.invalidate()
        nextBreakTimer?.invalidate()
        selfReference = nil
    }
    
    // --- Menu Handling ---
    @objc func menuWillOpen(_ notification: Notification) {
        if let menu = notification.object as? NSMenu, menu === statusItem?.menu {
            menuIsOpen = true
            menuUpdateTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateMenuTimeDisplay), userInfo: nil, repeats: true)
            RunLoop.current.add(menuUpdateTimer!, forMode: .common)
            updateMenuTimeDisplay()
        }
    }
    
    @objc func menuDidClose(_ notification: Notification) {
        if let menu = notification.object as? NSMenu, menu === statusItem?.menu {
            menuIsOpen = false
            menuUpdateTimer?.invalidate()
            menuUpdateTimer = nil
        }
    }
    
    @objc func updateMenuTimeDisplay() {
        if menuIsOpen, let menu = statusItem?.menu, let timeItem = menu.items.first {
            let remaining = max(0, Int(nextBreakDate?.timeIntervalSinceNow ?? 0))
            timeItem.title = "Your break begins in \(formatTimeRemaining(remaining))"
        }
    }
    
    @objc func statusBarButtonClicked() {
        setupMenu()
        statusItem?.button?.performClick(nil)
    }
    
    func setupMenu() {
        let menu = NSMenu()
        let timeString = formatTimeRemaining(timeUntilBreak)
        menu.addItem(NSMenuItem(title: "Your break begins in \(timeString)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop EyeBreak", action: #selector(stopApp), keyEquivalent: "T"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About...", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "Q"))
        let breakSubmenu = NSMenu()
        breakSubmenu.addItem(NSMenuItem(title: "Start this break now", action: #selector(takeBreakNow), keyEquivalent: ""))
        breakSubmenu.addItem(NSMenuItem.separator())
        breakSubmenu.addItem(NSMenuItem(title: "Add 1 minute", action: #selector(add1Minute), keyEquivalent: ""))
        breakSubmenu.addItem(NSMenuItem(title: "Add 5 minutes", action: #selector(add5Minutes), keyEquivalent: ""))
        breakSubmenu.addItem(NSMenuItem.separator())
        let pauseItem = NSMenuItem(title: "Pause for", action: nil, keyEquivalent: "")
        let pauseSubmenu = NSMenu()
        pauseSubmenu.addItem(NSMenuItem(title: "10 minutes", action: #selector(pauseFor10), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "15 minutes", action: #selector(pauseFor15), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "30 minutes", action: #selector(pauseFor30), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "45 minutes", action: #selector(pauseFor45), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "1 hour", action: #selector(pauseFor60), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "2 hours", action: #selector(pauseFor120), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "4 hours", action: #selector(pauseFor240), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "8 hours", action: #selector(pauseFor480), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem(title: "24 hours", action: #selector(pauseFor1440), keyEquivalent: ""))
        pauseSubmenu.addItem(NSMenuItem.separator())
        pauseSubmenu.addItem(NSMenuItem(title: "Until I resume", action: #selector(pauseUntilResume), keyEquivalent: ""))
        pauseItem.submenu = pauseSubmenu
        breakSubmenu.addItem(pauseItem)
        breakSubmenu.addItem(NSMenuItem(title: "Skip this break", action: #selector(skipNextBreak), keyEquivalent: "S"))
        if let firstItem = menu.items.first {
            firstItem.submenu = breakSubmenu
        }
        statusItem?.menu = menu
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "EyeBreak"
        alert.informativeText = "A simple eye break reminder app to help reduce eye strain."
        alert.runModal()
    }
    
    @objc func showSettings() {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Settings would go here in a real app."
        alert.runModal()
    }
    
    @objc func stopApp() {
        statusItem?.button?.title = "👁️"
    }
    
    @objc func add1Minute() {
        adjustNextBreak(by: 60)
    }

    @objc func add5Minutes() {
        adjustNextBreak(by: 5 * 60)
    }
    
    @objc func pauseFor10() { pauseFor(minutes: 10) }
    @objc func pauseFor15() { pauseFor(minutes: 15) }
    @objc func pauseFor30() { pauseFor(minutes: 30) }
    @objc func pauseFor45() { pauseFor(minutes: 45) }
    @objc func pauseFor60() { pauseFor(minutes: 60) }
    @objc func pauseFor120() { pauseFor(minutes: 120) }
    @objc func pauseFor240() { pauseFor(minutes: 240) }
    @objc func pauseFor480() { pauseFor(minutes: 480) }
    @objc func pauseFor1440() { pauseFor(minutes: 1440) }
    
    @objc func pauseUntilResume() {
        scheduleBreak(in: Int.max / 2)
    }

    func pauseFor(minutes: Int) {
        scheduleBreak(in: minutes * 60)
    }
    // --- End Menu Handling ---
    
    @objc func takeBreakNow() {
        print("AppDelegate: takeBreakNow called.")
        startBreak()
    }
    
    @objc func skipNextBreak() {
        print("AppDelegate: skipNextBreak called.")
        timeUntilBreak = 20 * 60 // Reset to 20 minutes
        updateMenuTimeDisplay()
    }
    
    // Triggered when it's time to start a break
    func startBreak() {
        isOnBreak = true
        nextBreakWorkItem = nil
        print("AppDelegate: Break started.")
        
        // Always create a fresh BreakView and replace the window's contentView
        let breakView = BreakView(remainingSeconds: breakDuration)
        let containerView = BreakViewContainer(breakView: breakView) { [weak self] in
            print("AppDelegate: Skip pressed; triggering endBreak.")
            self?.endBreak()
        }
        // If window doesn't exist yet, create and configure it
        if breakWindow == nil {
            print("AppDelegate: Creating break window for first time.")
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .black
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            if let screen = NSScreen.main {
                window.setFrame(screen.frame, display: true)
            }
            breakWindow = window
        }
        guard let window = breakWindow else { return }
        // Replace contentView with new BreakView
        window.contentView = NSHostingView(rootView: containerView)
        window.makeKeyAndOrderFront(nil)
        print("AppDelegate: Showing break window with new content.")
        // Fade-in animation
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            window.animator().alphaValue = 1
        })
        print("AppDelegate: Break window fade-in started.")
        
        // Schedule end of break
        breakWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.endBreak()
        }
        breakWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(breakDuration), execute: work)
    }
    
    // Triggered when the break duration finishes
    func endBreak() {
        isOnBreak = false
        print("AppDelegate: Break ended.")
        // Hide the break window
        breakWindow?.orderOut(nil)
        print("AppDelegate: Break cleanup complete. Scheduling next break.")
        // Schedule next break after cleanup
        scheduleNextBreak()
    }
    
    // --- Formatting (Unchanged) ---
    func formatTimeRemaining(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "\(hours):\(String(format: "%02d", remainingMinutes))"
            } else {
                return "\(hours):00"
            }
        } else {
            return "\(minutes):\(String(format: "%02d", remainingSeconds))"
        }
    }
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    // --- End Formatting ---
    
    private func scheduleBreak(in seconds: Int) {
        timeUntilBreak = seconds
        let date = Date().addingTimeInterval(TimeInterval(seconds))
        nextBreakDate = date
        print("AppDelegate: Scheduling next break in \(seconds) seconds at \(date)")
        nextBreakWorkItem?.cancel()
        nextBreakTimer?.invalidate()
        let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(nextBreakTimerFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        nextBreakTimer = timer
        updateMenuTimeDisplay()
    }

    private func adjustNextBreak(by seconds: Int) {
        let remaining = max(0, Int(nextBreakDate?.timeIntervalSinceNow ?? TimeInterval(timeUntilBreak)))
        scheduleBreak(in: remaining + seconds)
    }

    private func scheduleNextBreak() {
        scheduleBreak(in: 20 * 60)
    }
    
    @objc private func nextBreakTimerFired() {
        // Clear the timer reference and start break
        nextBreakTimer?.invalidate()
        nextBreakTimer = nil
        startBreak()
    }
    
    @objc func handleWake(_ notification: Notification) {
        print("AppDelegate: system woke up, rescheduling break")
        guard let nextDate = nextBreakDate else {
            scheduleNextBreak()
            return
        }
        let remaining = max(0, Int(nextDate.timeIntervalSinceNow))
        if remaining <= 0 {
            startBreak()
        } else {
            nextBreakWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.startBreak()
            }
            nextBreakWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(remaining), execute: work)
        }
    }
}

// Container to help with state updates
struct BreakViewContainer: View {
    @ObservedObject var breakView: BreakView
    var onSkip: () -> Void
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(breakView: BreakView, onSkip: @escaping () -> Void) {
        self.breakView = breakView
        self.onSkip = onSkip
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 80) {
                Text("Current time is \(currentTimeString())")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Eyes to the horizon")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Find a distant spot to rest your eyes on while you wait")
                    .font(.title2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(width: 200)
                
                Text(formatTime(breakView.remainingSeconds))
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                
                Button(action: onSkip) {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("Skip")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .opacity(breakView.opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 1.0)) {
                    breakView.opacity = 1.0
                }
            }
            // Decrement breakView.remainingSeconds every second
            .onReceive(tick) { _ in
                if breakView.remainingSeconds > 0 {
                    breakView.remainingSeconds -= 1
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

// Use ObservableObject to trigger UI updates
class BreakView: ObservableObject {
    @Published var remainingSeconds: Int
    @Published var opacity: Double = 0
    
    init(remainingSeconds: Int) {
        self.remainingSeconds = remainingSeconds
    }
}

// Initialize app
app.delegate = delegate
app.run() 