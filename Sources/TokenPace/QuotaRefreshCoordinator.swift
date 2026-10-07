import Foundation

// All methods are called on the main queue; fetch work alone runs off queue.
final class QuotaRefreshCoordinator {
    private let fetch: (@escaping (QuotaData?) -> Void) -> Void
    private let publish: (QuotaData) throws -> Void
    private let now: () -> Date
    private(set) var running = false
    private(set) var inFlight = false
    private(set) var failures = 0
    private var generation = 0
    private var nextPoll = Date.distantFuture
    private var retryAt: Date?
    private var resetAt: Date?
    private var eventAt: Date?
    private var networkAvailable: Bool
    private var networkGeneration = 0

    init(now: @escaping () -> Date = Date.init,
         networkAvailable: Bool = true,
         fetch: @escaping (@escaping (QuotaData?) -> Void) -> Void,
         publish: @escaping (QuotaData) throws -> Void) {
        self.now = now
        self.networkAvailable = networkAvailable
        self.fetch = fetch
        self.publish = publish
    }

    func start() {
        guard !running else { return }
        running = true
        nextPoll = now()
        tick()
    }

    func stop() {
        running = false
        generation += 1
        inFlight = false
        failures = 0
        retryAt = nil
        resetAt = nil
        eventAt = nil
        nextPoll = .distantFuture
    }

    func activity() {
        guard running else { return }
        // Do not let continuous writes postpone the first event indefinitely.
        if eventAt == nil { eventAt = now().addingTimeInterval(3) }
    }

    func connectivityChanged(available: Bool) {
        guard networkAvailable != available else { return }
        networkAvailable = available
        networkGeneration += 1
        guard available, running else { return }
        // A real path recovery gets one immediate attempt, not a five-minute wait.
        // Repeated identical path callbacks do not bypass retry backoff.
        failures = 0
        retryAt = nil
        nextPoll = now()
        tick()
    }

    func tick() {
        guard running, networkAvailable, !inFlight else { return }
        let date = now()
        if let retryAt {
            guard date >= retryAt else { return }
        } else {
            guard date >= nextPoll || eventAt.map({ date >= $0 }) == true
                    || resetAt.map({ date >= $0 }) == true else { return }
        }
        inFlight = true
        eventAt = nil
        retryAt = nil
        resetAt = nil
        generation += 1
        let id = generation
        let networkID = networkGeneration
        fetch { [weak self] data in
            guard let self, self.running, self.generation == id else { return }
            self.inFlight = false
            let completed = self.now()
            // A response spanning a network loss cannot re-stamp the old quota.
            // Keep the single-flight slot until that fetch actually completes.
            guard self.networkAvailable else { return }
            if self.networkGeneration != networkID {
                self.nextPoll = completed
                self.tick()
                return
            }
            if let data, data.isFresh(at: completed), (try? self.publish(data)) != nil {
                self.failures = 0
                self.retryAt = nil
                self.nextPoll = completed.addingTimeInterval(QuotaPolicy.pollInterval)
                self.resetAt = data.buckets.compactMap { QuotaPolicy.resetDate($0.1) }
                    .min()?.addingTimeInterval(60)
            } else {
                self.failures += 1
                let delay = min(10 * pow(2, Double(min(self.failures - 1, 5))), 300)
                self.retryAt = completed.addingTimeInterval(delay)
            }
        }
    }
}
