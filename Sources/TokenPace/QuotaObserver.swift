import Foundation
import WidgetKit

class QuotaObserver: ObservableObject {
    private var cliWatcher: DispatchSourceFileSystemObject?
    private var ideWatcher: DispatchSourceFileSystemObject?
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 3.0
    private var resetTimer: Timer?
    
    init() {
        // Initial fetch
        fetchAndPublish()
        
        // Setup watchers
        setupWatchers()
    }
    
    private func setupWatchers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cliURL = home.appendingPathComponent(".gemini/antigravity-cli/conversations")
        let ideURL = home.appendingPathComponent(".gemini/antigravity-ide/conversations")
        
        cliWatcher = createWatcher(for: cliURL)
        ideWatcher = createWatcher(for: ideURL)
    }
    
    private func createWatcher(for url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return nil }
        
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .global(qos: .background))
        
        watcher.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.handleDatabaseChange()
            }
        }
        
        watcher.setCancelHandler {
            close(fd)
        }
        
        watcher.resume()
        return watcher
    }
    
    private func handleDatabaseChange() {
        try? "Database change detected, debouncing...\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.fetchAndPublish()
        }
    }
    
    private func scheduleNextResetFetch(from data: QuotaData) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        let resetStrings = [
            data.geminiWeeklyResetTime,
            data.gemini5hResetTime,
            data.claudeWeeklyResetTime,
            data.claude5hResetTime
        ]
        
        let currentDate = Date()
        var nextResetDate: Date? = nil
        
        for dateString in resetStrings {
            if let date = formatter.date(from: dateString) {
                if date > currentDate {
                    if let currentNext = nextResetDate {
                        if date < currentNext {
                            nextResetDate = date
                        }
                    } else {
                        nextResetDate = date
                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.resetTimer?.invalidate()
            
            if let nextDate = nextResetDate {
                // Schedule timer 60 seconds after the next reset
                let fireDate = nextDate.addingTimeInterval(60)
                let timeUntilFire = fireDate.timeIntervalSince(Date())
                
                if timeUntilFire > 0 {
                    try? "Scheduling next fetch in \(timeUntilFire) seconds (at \(fireDate))\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
                    self?.resetTimer = Timer.scheduledTimer(withTimeInterval: timeUntilFire, repeats: false) { _ in
                        try? "Auto-fetch triggered from reset timer!\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
                        self?.fetchAndPublish()
                    }
                }
            }
        }
    }
    
    private func fetchAndPublish() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = QuotaFetcher.fetchQuota() else {
                try? "Fetch failed\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
                return
            }
            
            try? "Fetched data successfully\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
            
            // Save directly to the Widget's Sandbox Container
            let fileManager = FileManager.default
            let homeDir = fileManager.homeDirectoryForCurrentUser
            let widgetDocsDir = homeDir.appendingPathComponent("Library/Containers/\(Bundle.main.bundleIdentifier!)Extension/Data/Documents")
            
            do {
                try fileManager.createDirectory(at: widgetDocsDir, withIntermediateDirectories: true, attributes: nil)
                let fileURL = widgetDocsDir.appendingPathComponent("quota.json")
                let encoded = try JSONEncoder().encode(data)
                try encoded.write(to: fileURL, options: .atomic)
                try? "Saved to Sandbox\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
            } catch {
                try? "Failed to write quota.json: \(error)\n".appendLineToURL(fileURL: URL(fileURLWithPath: "/tmp/agy_widget.log"))
            }
            
            // Trigger Widget reload
            WidgetCenter.shared.reloadAllTimelines()
            
            // Schedule the auto-fetch for the next quota reset
            self?.scheduleNextResetFetch(from: data)
        }
    }
}

extension String {
    func appendLineToURL(fileURL: URL) throws {
        let data = self.data(using: .utf8)!
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }
}
