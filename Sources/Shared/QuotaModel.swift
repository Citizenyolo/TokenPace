import Foundation

struct QuotaData: Codable, Equatable {
    var geminiWeeklyRemaining: Double
    var geminiWeeklyResetTime: String
    var gemini5hRemaining: Double
    var gemini5hResetTime: String
    
    var claudeWeeklyRemaining: Double
    var claudeWeeklyResetTime: String
    var claude5hRemaining: Double
    var claude5hResetTime: String
    var fetchedAt: Date? = nil
    var producerRevision: String? = nil
    // Optional for backward-compatible decoding of existing local snapshots.
    var gemini5hDisabled: Bool? = nil
    var claude5hDisabled: Bool? = nil

    var buckets: [(Double, String, TimeInterval)] {
        var active = [(geminiWeeklyRemaining, geminiWeeklyResetTime, TimeInterval(7 * 24 * 3600)),
                      (claudeWeeklyRemaining, claudeWeeklyResetTime, TimeInterval(7 * 24 * 3600))]
        if gemini5hDisabled != true { active.append((gemini5hRemaining, gemini5hResetTime, 5 * 3600)) }
        if claude5hDisabled != true { active.append((claude5hRemaining, claude5hResetTime, 5 * 3600)) }
        return active
    }

    func isValid(at date: Date) -> Bool {
        // A disabled five-hour bucket is legitimate only when its weekly limit is exhausted.
        // Its reset is not applicable; never fabricate a five-hour deadline.
        guard gemini5hDisabled != true || (gemini5hRemaining == 0 && geminiWeeklyRemaining == 0),
              claude5hDisabled != true || (claude5hRemaining == 0 && claudeWeeklyRemaining == 0) else { return false }
        return buckets.allSatisfy { fraction, reset, duration in
            guard fraction.isFinite, (0...1).contains(fraction),
                  let end = QuotaPolicy.resetDate(reset) else { return false }
            return end > date && end.timeIntervalSince(date) <= duration + 60
        }
    }

    func isFresh(at date: Date) -> Bool {
        guard let fetchedAt, fetchedAt <= date,
              date.timeIntervalSince(fetchedAt) < QuotaPolicy.staleAfter,
              isValid(at: fetchedAt) else { return false }
        return buckets.allSatisfy { QuotaPolicy.resetDate($0.1).map { $0 > date } ?? false }
    }
}

enum QuotaBuildIdentity {
    static var revision: String {
        Bundle.main.object(forInfoDictionaryKey: "TokenPaceSourceRevision") as? String ?? "unversioned"
    }
}

// A local successful read is not proof that the CLI contacted its upstream service.
enum QuotaPolicy {
    static let pollInterval: TimeInterval = 240
    static let staleAfter: TimeInterval = 300
    static let fetchTimeout: TimeInterval = 30

    static func resetDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func timelineDates(for data: QuotaData?, now: Date) -> [Date] {
        let end = now.addingTimeInterval(120 * 60)
        var dates = (0..<120).map { now.addingTimeInterval(Double($0) * 60) }
        if let data {
            let transitions = data.buckets.compactMap { resetDate($0.1) }
                + (data.fetchedAt.map { [$0.addingTimeInterval(staleAfter)] } ?? [])
            dates += transitions.filter { $0 > now && $0 <= end }
        }
        return Array(Set(dates)).sorted()
    }
}

struct QuotaStore {
    let fileURL: URL

    func read() -> QuotaData? {
        guard let bytes = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(QuotaData.self, from: bytes)
    }

    func write(_ data: QuotaData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
    }
}

// Data models corresponding to `agy --output-format json -p "/usage"`
struct UsageResponse: Codable {
    let status: String?
    let command: UsageCommand
}

struct UsageCommand: Codable {
    let name: String?
    let data: UsageData
}

struct UsageData: Codable {
    let groups: [UsageGroup]
}

struct UsageGroup: Codable {
    let name: String
    let buckets: [UsageBucket]
}

struct UsageBucket: Codable {
    let id: String
    let remaining_fraction: Double?
    let reset_time: String?
    let disabled: Bool?
}
