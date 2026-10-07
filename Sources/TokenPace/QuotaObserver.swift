import Foundation
import AppKit
import WidgetKit

class QuotaObserver: ObservableObject {
    private var cliWatcher: DispatchSourceFileSystemObject?
    private var ideWatcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private lazy var coordinator = QuotaRefreshCoordinator(fetch: { completion in
        DispatchQueue.global(qos: .utility).async {
            let data = QuotaFetcher.fetchQuota()
            DispatchQueue.main.async { completion(data) }
        }
    }, publish: { data in
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileNoSuchFile)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent("Library/Containers/\(bundleID)Extension/Data/Documents/quota.json")
        try QuotaStore(fileURL: file).write(data)
        WidgetCenter.shared.reloadAllTimelines()
    })

    init() { start() }

    func start() {
        guard timer == nil else { return }
        setupWatchers()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.coordinator.tick()
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stop() }
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
        timer?.invalidate()
        timer = nil
        cliWatcher?.cancel()
        ideWatcher?.cancel()
        cliWatcher = nil
        ideWatcher = nil
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    deinit {
        timer?.invalidate()
        cliWatcher?.cancel()
        ideWatcher?.cancel()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
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
                self?.coordinator.activity()
            }
        }
        
        watcher.setCancelHandler {
            close(fd)
        }
        
        watcher.resume()
        return watcher
    }
    
}
