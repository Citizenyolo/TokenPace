import Foundation
import WidgetKit

class QuotaObserver: ObservableObject {
    private var cliWatcher: DispatchSourceFileSystemObject?
    private var ideWatcher: DispatchSourceFileSystemObject?
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 3.0
    private var resetTimer: Timer?
    private var pendingFetchWorkItem: DispatchWorkItem?
    
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
                    self?.resetTimer = Timer.scheduledTimer(withTimeInterval: timeUntilFire, repeats: false) { _ in
                        self?.fetchAndPublish()
                    }
                }
            }
        }
    }
    
    private func scheduleRetry(retryCount: Int, delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.fetchAndPublish(retryCount: retryCount)
        }
        pendingFetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private var currentFetchID: Int = 0

    private func fetchAndPublish(retryCount: Int = 0) {
        pendingFetchWorkItem?.cancel()
        pendingFetchWorkItem = nil
        
        currentFetchID += 1
        let fetchID = currentFetchID
        
        let fetchWork = DispatchWorkItem { [weak self] in
            guard let data = QuotaFetcher.fetchQuota() else {
                if retryCount < 5 {
                    let delay = min(pow(2.0, Double(retryCount)) * 10.0, 300.0)
                    DispatchQueue.main.async {
                        if self?.currentFetchID == fetchID {
                            self?.scheduleRetry(retryCount: retryCount + 1, delay: delay)
                        }
                    }
                }
                return
            }
            
            // Move publication and state check back to the main queue to guarantee atomicity
            // with respect to currentFetchID increments, avoiding race conditions post-check.
            DispatchQueue.main.async {
                guard self?.currentFetchID == fetchID else { return }
                
                // Save directly to the Widget's Sandbox Container
                let fileManager = FileManager.default
                let homeDir = fileManager.homeDirectoryForCurrentUser
                guard let bundleId = Bundle.main.bundleIdentifier else { return }
                let widgetDocsDir = homeDir.appendingPathComponent("Library/Containers/\(bundleId)Extension/Data/Documents")
                
                do {
                    try fileManager.createDirectory(at: widgetDocsDir, withIntermediateDirectories: true, attributes: nil)
                    let fileURL = widgetDocsDir.appendingPathComponent("quota.json")
                    let encoded = try JSONEncoder().encode(data)
                    try encoded.write(to: fileURL, options: .atomic)
                } catch {
                    print("Failed to write quota.json: \(error)")
                }
                
                // Trigger Widget reload
                WidgetCenter.shared.reloadAllTimelines()
                
                // Schedule the auto-fetch for the next quota reset
                self?.scheduleNextResetFetch(from: data)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async(execute: fetchWork)
    }
}
