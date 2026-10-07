import Foundation

@main
struct QuotaRegression {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }

    static func payload(at date: Date) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let groups: [[String: Any]] = [
            ["name": "Gemini Models", "buckets": [
                ["id": "gemini-weekly", "remaining_fraction": 0.42, "reset_time": formatter.string(from: date.addingTimeInterval(604800))],
                ["id": "gemini-5h", "remaining_fraction": 0.31, "reset_time": formatter.string(from: date.addingTimeInterval(18000))]]],
            ["name": "Claude and GPT models", "buckets": [
                ["id": "3p-weekly", "remaining_fraction": 0.24, "reset_time": formatter.string(from: date.addingTimeInterval(604800))],
                ["id": "3p-5h", "remaining_fraction": 0.13, "reset_time": formatter.string(from: date.addingTimeInterval(18000))]]]
        ]
        return try! JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "command": ["name": "usage", "data": ["groups": groups]]])
    }

    static func main() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let bytes = payload(at: date)
        let data = QuotaFetcher.parse(bytes, fetchedAt: date)!
        expect(data.gemini5hRemaining == 0.31 && data.claude5hRemaining == 0.13, "actual fractions preserved")
        expect(data.fetchedAt == date, "fetch time stamped")
        expect(data.isFresh(at: date.addingTimeInterval(299.999)), "fresh before boundary")
        expect(!data.isFresh(at: date.addingTimeInterval(300)), "stale exactly at boundary")
        expect(!data.isFresh(at: date.addingTimeInterval(-1)), "future timestamp rejected")
        var invalid = data
        invalid.fetchedAt = nil
        expect(!invalid.isFresh(at: date), "legacy cache cannot claim freshness")
        let legacy = try JSONDecoder().decode(QuotaData.self, from: JSONEncoder().encode(invalid))
        expect(legacy.fetchedAt == nil, "legacy decode supported")
        for fraction in [-0.1, 1.1, Double.infinity, Double.nan] {
            invalid = data; invalid.gemini5hRemaining = fraction
            expect(!invalid.isFresh(at: date), "invalid fraction rejected")
        }
        for reset in ["", "garbage", "2027-01-15T08:00:00Z"] {
            invalid = data; invalid.gemini5hResetTime = reset
            expect(!invalid.isFresh(at: date), "invalid reset rejected")
        }
        invalid = data
        invalid.gemini5hResetTime = ISO8601DateFormatter().string(from: date.addingTimeInterval(10))
        expect(invalid.isFresh(at: date), "short reset accepted")
        expect(!invalid.isFresh(at: date.addingTimeInterval(10)), "expired reset suppresses pacing")
        expect(QuotaPolicy.timelineDates(for: data, now: date.addingTimeInterval(17)).contains(date.addingTimeInterval(300)), "exact age transition scheduled")
        expect(QuotaPolicy.timelineDates(for: invalid, now: date).contains(date.addingTimeInterval(10)), "exact reset transition scheduled")
        expect(QuotaPolicy.resetDate("2027-01-15T08:00:00.123Z") != nil, "fractional ISO reset")
        expect(QuotaPolicy.resetDate("2027-01-15T08:00:00Z") != nil, "whole second ISO reset")
        expect(QuotaFetcher.parse(Data("{}".utf8), fetchedAt: date) == nil, "malformed payload")
        let text = String(data: bytes, encoding: .utf8)!
        expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "SUCCESS", with: "ERROR").utf8), fetchedAt: date) == nil, "error envelope cannot publish otherwise-valid quota")
        expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "\"usage\"", with: "\"other\"").utf8), fetchedAt: date) == nil, "wrong command cannot publish quota")
        var envelope = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        envelope.removeValue(forKey: "status")
        expect(QuotaFetcher.parse(try! JSONSerialization.data(withJSONObject: envelope), fetchedAt: date) == nil, "missing status cannot claim success")
        for replacement in ["null", "-0.1", "1.1", "\"bad\""] {
            expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "0.31", with: replacement).utf8), fetchedAt: date) == nil, "invalid bucket cannot publish")
        }
        expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "gemini-5h", with: "unknown").utf8), fetchedAt: date) == nil, "missing required bucket")
        expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "gemini-5h", with: "gemini-weekly").utf8), fetchedAt: date) == nil, "duplicate required bucket")
        expect(QuotaFetcher.parse(Data(text.replacingOccurrences(of: "Gemini Models", with: "Unknown").utf8), fetchedAt: date) == nil, "wrong group")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = QuotaStore(fileURL: directory.appendingPathComponent("widget/Documents/quota.json"))
        expect(store.read() == nil, "missing file unavailable")
        try store.write(data)
        expect(store.read() == data, "production atomic store roundtrip")
        try Data("broken".utf8).write(to: store.fileURL)
        expect(store.read() == nil, "malformed cache unavailable")
        try store.write(data)

        var clock = date
        var completions: [(QuotaData?) -> Void] = []
        var publications = 0
        var writeFails = false
        let coordinator = QuotaRefreshCoordinator(now: { clock }, fetch: { completions.append($0) }, publish: {
            if writeFails { throw CocoaError(.fileWriteNoPermission) }
            try store.write($0); publications += 1
        })
        coordinator.start(); coordinator.start()
        expect(completions.count == 1, "idempotent startup")
        coordinator.activity(); clock = clock.addingTimeInterval(4); coordinator.tick()
        expect(completions.count == 1, "single-flight event coordination")
        completions.removeFirst()(data)
        coordinator.tick()
        expect(completions.count == 1, "in-flight event coalesced into followup")
        completions.removeFirst()(nil)
        expect(store.read() == data, "failure retains last actual quota")
        for delay in [10.0, 20, 40, 80, 160, 300, 300] {
            coordinator.activity()
            clock = clock.addingTimeInterval(delay - 1)
            coordinator.tick()
            expect(completions.isEmpty, "events and polls must not bypass backoff")
            clock = clock.addingTimeInterval(1); coordinator.tick()
            expect(completions.count == 1, "bounded ongoing retry")
            completions.removeFirst()(nil)
        }
        expect(!store.read()!.isFresh(at: clock), "offline retained cache becomes stale")
        clock = clock.addingTimeInterval(300); coordinator.tick()
        let recovered = QuotaFetcher.parse(payload(at: clock), fetchedAt: clock)!
        completions.removeFirst()(recovered)
        expect(coordinator.failures == 0 && store.read() == recovered, "recovery publishes actual fractions and resets backoff")
        expect(store.read()!.claude5hRemaining == 0.13, "recovery never assumes 100 percent")
        clock = clock.addingTimeInterval(239); coordinator.tick()
        expect(completions.isEmpty, "no early polling")
        clock = clock.addingTimeInterval(1); coordinator.tick()
        expect(completions.count == 1, "240 second polling")
        writeFails = true
        completions.removeFirst()(QuotaFetcher.parse(payload(at: clock), fetchedAt: clock))
        expect(coordinator.failures == 1 && publications == 2, "publication failure enters retry without success")
        clock = clock.addingTimeInterval(10); coordinator.tick()
        coordinator.stop(); coordinator.start()
        expect(completions.count == 2, "restart permits new generation")
        completions.removeFirst()(QuotaFetcher.parse(payload(at: clock), fetchedAt: clock))
        expect(coordinator.inFlight && publications == 2, "late response rejected")
        writeFails = false
        completions.removeFirst()(QuotaFetcher.parse(payload(at: clock), fetchedAt: clock))
        expect(!coordinator.inFlight && publications == 3, "new generation publishes")
        coordinator.stop(); clock = clock.addingTimeInterval(1000); coordinator.activity(); coordinator.tick()
        expect(completions.isEmpty, "shutdown cancels future work")

        var resetClock = date
        var resetCompletions: [(QuotaData?) -> Void] = []
        var resetPublications = 0
        let resetCoordinator = QuotaRefreshCoordinator(now: { resetClock },
            fetch: { resetCompletions.append($0) }, publish: { _ in resetPublications += 1 })
        resetCoordinator.start()
        resetCompletions.removeFirst()(invalid)
        resetClock = date.addingTimeInterval(69); resetCoordinator.tick()
        expect(resetCompletions.isEmpty, "reset does not fetch before reset plus 60")
        resetClock = date.addingTimeInterval(70); resetCoordinator.tick()
        expect(resetCompletions.count == 1, "reset plus 60 preempts periodic refresh")
        resetCompletions.removeFirst()(invalid)
        expect(resetCoordinator.failures == 1 && resetPublications == 1, "expired response rejected")
        resetClock = date.addingTimeInterval(80); resetCoordinator.tick()
        var future = data; future.fetchedAt = resetClock.addingTimeInterval(1)
        resetCompletions.removeFirst()(future)
        expect(resetCoordinator.failures == 2 && resetPublications == 1, "future completion cannot publish")
        resetCoordinator.stop()

        // Production connectivity callbacks use this same coordinator; no host network changes.
        var networkClock = date
        var networkCompletions: [(QuotaData?) -> Void] = []
        var networkPublished: [QuotaData] = []
        let networkCoordinator = QuotaRefreshCoordinator(now: { networkClock }, networkAvailable: false,
            fetch: { networkCompletions.append($0) }, publish: { networkPublished.append($0) })
        networkCoordinator.start()
        networkCoordinator.activity(); networkClock = date.addingTimeInterval(1000); networkCoordinator.tick()
        expect(networkCompletions.isEmpty, "offline startup and activity do not launch CLI")
        networkCoordinator.connectivityChanged(available: true)
        expect(networkCompletions.count == 1, "first usable network path starts one fetch")
        networkCompletions.removeFirst()(nil)
        networkCoordinator.connectivityChanged(available: true); networkCoordinator.activity(); networkCoordinator.tick()
        expect(networkCompletions.isEmpty, "duplicate path updates do not bypass failure backoff")
        networkClock = networkClock.addingTimeInterval(9); networkCoordinator.tick()
        expect(networkCompletions.isEmpty, "connectivity retry waits for deadline")
        networkClock = networkClock.addingTimeInterval(1); networkCoordinator.tick()
        expect(networkCompletions.count == 1, "connectivity retry runs at deadline")
        let beforeLoss = QuotaFetcher.parse(payload(at: networkClock), fetchedAt: networkClock)!
        networkCoordinator.connectivityChanged(available: false)
        networkCoordinator.tick()
        networkCoordinator.connectivityChanged(available: true)
        expect(networkCompletions.count == 1, "reconnect does not overlap a still-running fetch")
        networkCompletions.removeFirst()(beforeLoss)
        expect(networkPublished.isEmpty && networkCompletions.count == 1,
               "response spanning loss is discarded and one fresh followup starts")
        var afterReconnect = beforeLoss; afterReconnect.gemini5hRemaining = 0.19
        networkCompletions.removeFirst()(afterReconnect)
        expect(networkPublished == [afterReconnect], "reconnect publishes actual returned quota")
        networkClock = networkClock.addingTimeInterval(240); networkCoordinator.tick()
        expect(networkCompletions.count == 1, "online periodic cadence preserved")
        networkCoordinator.connectivityChanged(available: false)
        networkCompletions.removeFirst()(QuotaFetcher.parse(payload(at: networkClock), fetchedAt: networkClock))
        expect(networkPublished.count == 1, "late cached success while offline cannot renew freshness")
        networkClock = networkClock.addingTimeInterval(700); networkCoordinator.activity(); networkCoordinator.tick()
        expect(networkCompletions.isEmpty && !networkPublished.last!.isFresh(at: networkClock),
               "prolonged outage ages last quota and does not poll CLI")
        networkCoordinator.connectivityChanged(available: true)
        expect(networkCompletions.count == 1, "recovery after prolonged outage is immediate")
        networkCompletions.removeFirst()(nil)
        networkCoordinator.connectivityChanged(available: false)
        networkCoordinator.connectivityChanged(available: true)
        expect(networkCompletions.count == 1, "real path transition preempts pending retry")
        networkCompletions.removeFirst()(QuotaFetcher.parse(payload(at: networkClock), fetchedAt: networkClock))
        expect(networkPublished.count == 2 && networkCoordinator.failures == 0, "recovery resets failures")
        networkCoordinator.stop()
        networkCoordinator.connectivityChanged(available: false)
        networkCoordinator.connectivityChanged(available: true)
        networkCoordinator.tick()
        expect(networkCompletions.isEmpty, "connectivity changes after stop cannot start work")

        // Use a fake executable only; never invoke the installed CLI or live services.
        let executable = directory.appendingPathComponent("fake-agy")
        func script(_ contents: String) throws {
            try ("#!/bin/sh\n" + contents).write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        let liveFixture = String(data: payload(at: Date()), encoding: .utf8)!
        try script("cat <<'JSON'\n" + liveFixture + "\nJSON\n")
        expect(QuotaFetcher.fetchQuota(executable: executable)?.gemini5hRemaining == 0.31, "production process success")
        try script("cat <<'JSON'\n" + liveFixture + "\nJSON\nexit 1\n")
        expect(QuotaFetcher.fetchQuota(executable: executable) == nil, "nonzero exit cannot fabricate fresh data")
        try script("exec /bin/sleep 5\n")
        let start = Date()
        expect(QuotaFetcher.fetchQuota(executable: executable, timeout: 0.1) == nil, "hung process timeout")
        expect(Date().timeIntervalSince(start) < 2, "timeout bounded")
        try script("/usr/bin/yes x | /usr/bin/head -c 1500000\n")
        expect(QuotaFetcher.fetchQuota(executable: executable, timeout: 2) == nil, "oversized output bounded without pipe deadlock")
        print("Passed \(checks) production-code regression checks; no live CLI/network/widget access.")
    }
}
